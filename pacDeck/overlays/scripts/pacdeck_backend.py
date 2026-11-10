#!/usr/bin/env python3
"""pacDeck's per-user JSON bridge, PTY runner, and transient sudo askpass bridge."""
from __future__ import annotations

import concurrent.futures
import fcntl
import hmac
import json
import os
from pathlib import Path
import pty
import re
import secrets
import selectors
import shlex
import shutil
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import threading
import time

HELPERS = ("paru", "yay")
NAME = re.compile(r"^[a-zA-Z0-9@_+][a-zA-Z0-9@._+:-]{0,199}$")
ANSI = re.compile(r"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\))")
PERCENT = re.compile(r"(?<!\d)(\d{1,3})(?:\.\d+)?%")
PROMPT = re.compile(r"(?:\[[YyNn]/[YyNn]\]|[?:>]\s*$)")
MAX_OUTPUT = 2 * 1024 * 1024


def executable(name):
    path = shutil.which(name)
    if not path:
        raise RuntimeError(f"Required command is missing: {name}")
    return path


def environment():
    return dict(os.environ, LC_ALL="C", LANG="C", TERM="dumb", NO_COLOR="1")


def parse_search(text):
    rows, current = [], None
    for line in text.splitlines():
        if line and not line[0].isspace():
            parts = line.split()
            if parts and "/" in parts[0] and len(parts) > 1:
                repo, name = parts[0].split("/", 1)
                current = dict(name=name, repo=repo, version=parts[1],
                               installed="[installed" in line.lower(), description="")
                rows.append(current)
            else:
                current = None
        elif current and not current["description"]:
            current["description"] = line.strip()
    return rows


def parse_info(text):
    result, key = {}, ""
    for line in text.splitlines():
        if line and not line[0].isspace() and ":" in line:
            key, value = line.split(":", 1)
            key = key.strip()
            result[key] = value.strip()
        elif key and line.strip():
            result[key] += " " + line.strip()
    return result


def parse_updates(text):
    updates = {}
    for line in text.splitlines():
        parts = line.split()
        if len(parts) >= 4 and parts[2] == "->":
            updates[parts[0]] = {"from": parts[1], "to": parts[3]}
    return updates


def rank(rows, query):
    term = query.strip().lower().split(" ")[0]
    def key(row):
        name = row["name"].lower()
        band = 0 if not term or name == term else 1 if name.startswith(term) else 2 if term in name else 3
        return band, name, row.get("repo") == "aur"
    return sorted(rows, key=key)


class Bridge:
    def __init__(self, emit=None):
        self.output_lock = threading.Lock()
        self.emit_callback = emit
        self.lock = threading.RLock()
        self.interaction_lock = threading.Lock()
        self.executor = concurrent.futures.ThreadPoolExecutor(max_workers=4)
        self.read_tasks = {}
        self.installed = set()
        self.installed_rows = []
        self.helpers = []
        self.helper = ""
        self.job = None
        self.worker = None
        self.master = None
        self.pending = {}
        self.prompt_id = None
        self.last_prompt = ""
        self.stopping = False
        self.cancelled = False
        self.cancel_requested = False
        self.cancellable = False
        self.commit_active = False
        self.phase_label = "Preparing"
        self.token = secrets.token_urlsafe(32)
        runtime = os.environ.get("XDG_RUNTIME_DIR")
        self.runtime = Path(tempfile.mkdtemp(prefix="pd-", dir=runtime if runtime and os.access(runtime, os.W_OK) else None))
        self.server = socket.socket(socket.AF_UNIX)
        self.socket_path = self.runtime / "auth.sock"
        try:
            self.server.bind(str(self.socket_path))
        except OSError:
            self.server.close()
            shutil.rmtree(self.runtime, ignore_errors=True)
            raise
        self.socket_path.chmod(0o600)
        self.server.listen(4)
        self.server.settimeout(0.3)
        self.auth_thread = threading.Thread(target=self.serve_auth, daemon=True)
        self.auth_thread.start()

    def emit(self, event, **data):
        with self.output_lock:
            if self.emit_callback:
                self.emit_callback(dict(event=event, **data))
            else:
                try:
                    print(json.dumps(dict(event=event, **data), ensure_ascii=False), flush=True)
                except (BrokenPipeError, OSError):
                    pass

    def read_command(self, argv, stop=None, timeout=40):
        if stop and stop.is_set():
            raise InterruptedError()
        argv = [executable(argv[0]), *argv[1:]]
        with tempfile.TemporaryFile() as output, tempfile.TemporaryFile() as error:
            proc = subprocess.Popen(argv, stdout=output, stderr=error, env=environment(), start_new_session=True)
            deadline = time.monotonic() + timeout
            while proc.poll() is None:
                if (stop and stop.is_set()) or self.stopping:
                    os.killpg(proc.pid, signal.SIGKILL)
                    proc.wait()
                    raise InterruptedError()
                if time.monotonic() > deadline or output.tell() > MAX_OUTPUT or error.tell() > MAX_OUTPUT:
                    os.killpg(proc.pid, signal.SIGKILL)
                    proc.wait()
                    raise RuntimeError("Package query timed out or returned too much output")
                time.sleep(0.03)
            output.seek(0)
            error.seek(0)
            return proc.returncode, output.read(MAX_OUTPUT).decode(errors="replace"), error.read(4096).decode(errors="replace")

    def choose_helper(self, preference="auto"):
        available = [name for name in HELPERS if shutil.which(name)]
        selected = preference if preference in available else next(iter(available), "")
        with self.lock:
            self.helpers, self.helper = available, selected
        return selected

    def scan(self, request, stop):
        helper = self.choose_helper(request.get("helper", "auto"))
        code, text, error = self.read_command(["pacman", "-Qe"], stop)
        if code:
            raise RuntimeError(error.strip() or "Could not read installed packages")
        _, foreign_text, _ = self.read_command(["pacman", "-Qmq"], stop)
        foreign = set(foreign_text.splitlines())
        _, installed_text, _ = self.read_command(["pacman", "-Qq"], stop)
        rows = []
        for line in text.splitlines():
            parts = line.split()
            if len(parts) >= 2:
                rows.append(dict(name=parts[0], version=parts[1], repo="aur" if parts[0] in foreign else "installed", installed=True, description=""))
        with self.lock:
            self.installed = set(installed_text.splitlines())
            self.installed_rows = rank(rows, "")
        self.emit("scan", id=request["id"], helper=helper, helpers=self.helpers, rows=self.installed_rows)
        _, output, _ = self.read_command(["pacman", "-Qu", "--color", "never"], stop)
        updates = parse_updates(output)
        if helper:
            _, output, _ = self.read_command([helper, "-Qua", "--color", "never"], stop)
            updates.update(parse_updates(output))
        self.emit("updates", id=request["id"], updates=updates)

    def search(self, request, stop):
        query = str(request.get("query", "")).strip()[:256]
        if not query:
            self.emit("search", id=request["id"], rows=self.installed_rows, done=True)
            return
        code, output, error = self.read_command(["pacman", "-Ss", "--color", "never", "--", query], stop)
        if code not in (0, 1):
            raise RuntimeError(error.strip() or "Repository search failed")
        rows = {row["name"]: row for row in parse_search(output)}
        helper = self.choose_helper(request.get("helper", "auto"))
        self.emit("search", id=request["id"], rows=rank(list(rows.values()), query), done=not bool(helper))
        if helper:
            code, output, error = self.read_command([helper, "-Ss", "--color", "never", "--", query], stop)
            if code not in (0, 1):
                raise RuntimeError(error.strip() or f"{helper} search failed")
            for row in parse_search(output):
                rows.setdefault(row["name"], row)
            for row in rows.values():
                row["installed"] |= row["name"] in self.installed
            self.emit("search", id=request["id"], rows=rank(list(rows.values()), query), done=True)

    def details(self, request, stop):
        name = self.package_name(request)
        helper = self.choose_helper(request.get("helper", "auto"))
        command = helper if request.get("repo") == "aur" and helper else "pacman"
        code, text, error = self.read_command([command, "-Si", "--color", "never", "--", name], stop)
        if code:
            code, text, error = self.read_command(["pacman", "-Qi", "--color", "never", "--", name], stop)
        self.emit("details", id=request["id"], name=name, details=parse_info(text) if not code else {}, error=error.strip() if code else "")

    @staticmethod
    def package_name(request):
        name = str(request.get("name", ""))
        if not NAME.fullmatch(name):
            raise ValueError("Invalid package name")
        return name

    def dispatch(self, request):
        command = request.get("command")
        if command in ("scan", "search", "details"):
            with self.lock:
                previous = self.read_tasks.get(command)
                if previous:
                    previous.set()
                stop = threading.Event()
                self.read_tasks[command] = stop
            def run():
                try:
                    getattr(self, command)(request, stop)
                except InterruptedError:
                    pass
                except Exception as error:
                    if not stop.is_set():
                        self.emit("error", id=request.get("id"), command=command, message=str(error)[:1000])
            self.executor.submit(run)
        elif command == "transaction":
            self.start_transaction(request)
        elif command == "answer":
            self.answer(request)
        elif command == "input":
            self.write_input(request)
        elif command == "cancel":
            self.cancel(request)
        else:
            self.emit("error", id=request.get("id"), message="Unknown request")

    def prepare_environment(self):
        env = environment()
        python = sys.executable
        script = str(Path(__file__).resolve())
        sudo = executable("sudo")
        wrappers = {
            "sudo": "#!/bin/sh\nexec " + shlex.join([sudo, "-A"]) + ' "$@"\n',
            "askpass": "#!/bin/sh\nexec " + shlex.join([python, script, "--askpass"]) + ' "$@"\n',
            "review": "#!/bin/sh\nexec " + shlex.join([python, script, "--review"]) + ' "$@"\n',
        }
        for name, content in wrappers.items():
            target = self.runtime / name
            target.write_text(content)
            target.chmod(0o700)
        env.update(PATH=str(self.runtime) + os.pathsep + env.get("PATH", ""),
                   SUDO_ASKPASS=str(self.runtime / "askpass"), PACDECK_SOCKET=str(self.socket_path),
                   PACDECK_TOKEN=self.token, PAGER="cat", GIT_PAGER="cat", PARU_PAGER="cat",
                   EDITOR=str(self.runtime / "review"), VISUAL=str(self.runtime / "review"))
        return env

    def start_transaction(self, request):
        try:
            if os.geteuid() == 0:
                raise ValueError("Run pacDeck as your desktop user, not root")
            if request.get("confirmed") is not True:
                raise ValueError("Confirm the transaction first")
            operation = request.get("operation")
            if operation not in ("install", "remove", "upgrade", "bootstrap"):
                raise ValueError("Unknown transaction")
            if operation in ("install", "remove"):
                self.package_name(request)
            if operation == "bootstrap" and request.get("helper") not in HELPERS:
                raise ValueError("Choose paru or yay")
            with self.lock:
                if self.job is not None:
                    raise ValueError("Another transaction is already running")
                self.job = request["id"]
                self.cancelled = False
                self.cancel_requested = False
                self.cancellable = False
            self.emit("started", job=self.job, operation=operation)
            self.worker = threading.Thread(target=self.transaction, args=(dict(request),), daemon=False)
            self.worker.start()
        except Exception as error:
            self.emit("error", id=request.get("id"), command="transaction", message=str(error))

    def transaction(self, request):
        job = request["id"]
        code, message = 1, ""
        try:
            env = self.prepare_environment()
            operation = request["operation"]
            helper = self.choose_helper(request.get("helper", "auto"))
            if operation == "bootstrap":
                self.bootstrap(request["helper"], env)
            else:
                name = request.get("name", "")
                use_helper = helper and (operation == "upgrade" or operation == "install" and request.get("repo") == "aur")
                if operation == "install" and request.get("repo") == "aur" and not helper:
                    raise RuntimeError("Install paru or yay before installing AUR packages")
                flag = {"install": "-S", "remove": "-Rns", "upgrade": "-Syu"}[operation]
                if use_helper:
                    argv = [executable(helper), flag, "--noconfirm", "--color", "never", "--sudo", str(self.runtime / "sudo"), "--sudoflags="]
                    if helper == "paru":
                        argv += ["--fm", str(self.runtime / "review"), "--fmflags=", "--nosudoloop"]
                    else:
                        argv += ["--editor", str(self.runtime / "review"), "--editorflags="]
                else:
                    argv = [str(self.runtime / "sudo"), executable("pacman"), flag, "--noconfirm", "--color", "never"]
                if name:
                    argv += ["--", name]
                self.run_pty(argv, env)
            code, message = 0, "Completed successfully"
        except Exception as error:
            message = "Cancelled" if self.cancelled else str(error)
        finally:
            with self.lock:
                self.job = None
                self.master = None
                self.prompt_id = None
            self.emit("finished", job=job, ok=code == 0, message=message, cancelled=self.cancelled)

    def bootstrap(self, helper, env):
        if shutil.which(helper):
            self.emit("log", job=self.job, text=f"{helper} is already installed.")
            return
        self.emit("phase", job=self.job, label="Installing build dependencies", progress=None, cancellable=False)
        self.run_pty([str(self.runtime / "sudo"), executable("pacman"), "-S", "--needed", "--noconfirm", "base-devel", "git"], env)
        with tempfile.TemporaryDirectory(prefix="pacdeck-build-") as temp:
            checkout = Path(temp) / helper
            self.run_pty([executable("git"), "clone", "--", f"https://aur.archlinux.org/{helper}.git", str(checkout)], env, safe=True)
            files = []
            for path in sorted(checkout.iterdir()):
                if path.is_file() and (path.name in ("PKGBUILD", ".SRCINFO") or path.suffix == ".install"):
                    files.append(f"--- {path.name} ---\n" + path.read_text(errors="replace")[:128000])
            if not files:
                raise RuntimeError("The helper checkout contains no build files")
            if not self.interact("review", prompt=f"Review {helper}'s build files before building", content="\n\n".join(files)):
                raise RuntimeError("Build review declined")
            self.run_pty([executable("makepkg"), "-si", "--noconfirm"], env, cwd=str(checkout), safe=True)
        if not shutil.which(helper):
            raise RuntimeError(f"The build finished but {helper} is not available in PATH")

    def run_pty(self, argv, env, cwd=None, safe=False):
        if self.cancel_requested:
            self.cancelled = True
        if self.cancelled or self.cancel_requested or self.stopping:
            raise RuntimeError("Operation cancelled")
        master, slave = pty.openpty()
        attrs = termios.tcgetattr(slave)
        attrs[3] &= ~(termios.ECHO | termios.ECHONL)
        termios.tcsetattr(slave, termios.TCSANOW, attrs)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
        launcher = [sys.executable, str(Path(__file__).resolve()), "--exec", *argv]
        try:
            proc = subprocess.Popen(launcher, stdin=slave, stdout=slave, stderr=slave, cwd=cwd,
                                    env=env, start_new_session=True, close_fds=True)
        finally:
            os.close(slave)
        with self.lock:
            self.master = master
            self.cancellable = safe
            self.commit_active = False
            self.phase_label = "Preparing"
            self.last_prompt = ""
        self.emit("phase", job=self.job, label="Preparing", progress=None, cancellable=safe)
        buffer = ""
        decoder = __import__("codecs").getincrementaldecoder("utf-8")("replace")
        selector = selectors.DefaultSelector()
        selector.register(master, selectors.EVENT_READ)
        try:
            while True:
                ready = selector.select(0.15)
                if ready:
                    try:
                        data = os.read(master, 8192)
                    except OSError:
                        break
                    if not data:
                        break
                    text = ANSI.sub("", decoder.decode(data))
                    buffer += text
                    self.emit("log", job=self.job, text=text[:16000])
                    self.track_progress(text)
                    tail = re.split(r"[\r\n]", buffer)[-1].strip()[-1500:]
                    if tail and PROMPT.search(tail) and tail != self.last_prompt:
                        self.last_prompt = tail
                        self.prompt_id = secrets.token_hex(8)
                        self.emit("prompt", job=self.job, id=self.prompt_id, prompt=tail)
                    buffer = buffer[-8000:]
                if proc.poll() is not None and not ready:
                    break
            code = proc.wait()
            if code:
                raise RuntimeError(f"Package command exited with code {code}. See the activity log.")
        finally:
            selector.close()
            os.close(master)
            with self.lock:
                self.master = None
                self.prompt_id = None
            self.emit("prompt_clear", job=self.job)
            if proc.poll() is None:
                # A live transaction must be reaped; never leave a package tool orphaned.
                proc.wait()

    def track_progress(self, text):
        for line in re.split(r"[\r\n]", text):
            self.track_progress_line(line)

    def track_progress_line(self, text):
        lower = text.lower()
        label, cancellable = None, self.cancellable
        if any(word in lower for word in ("retrieving packages", "downloading", "receiving objects", "cloning into")):
            label, cancellable = "Downloading", True
            self.commit_active = False
        elif any(word in lower for word in ("starting build", "compiling", "building ", "making package")):
            label, cancellable = "Building", True
            self.commit_active = False
        elif any(word in lower for word in ("installing ", "upgrading ", "removing ", "checking ", "running post-transaction", "processing package changes")):
            label, cancellable = "Applying package changes", False
            self.commit_active = True
        matches = PERCENT.findall(text)
        progress = min(100, int(matches[-1])) if matches else None
        if label or progress is not None:
            self.cancellable = cancellable
            self.phase_label = label or self.phase_label
            self.emit("phase", job=self.job, label=self.phase_label, progress=progress, cancellable=cancellable)
            if self.cancel_requested and cancellable and not self.cancelled:
                self.cancel({"job": self.job, "confirmed": True})

    def write_input(self, request):
        text = str(request.get("value", ""))
        if len(text) > 4096 or any(c in text for c in "\r\n\x00"):
            return
        with self.lock:
            if request.get("job") != self.job or self.master is None or request.get("prompt") != self.prompt_id or self.prompt_id is None:
                return
            os.write(self.master, (text + "\n").encode())
            self.prompt_id = None
            self.last_prompt = ""
            self.cancellable = False
        self.emit("prompt_clear", job=self.job)
        self.emit("phase", job=self.job, label="Continuing", progress=None, cancellable=False)

    def cancel(self, request):
        with self.lock:
            if self.job is None or request.get("job") != self.job or request.get("confirmed") is not True or self.cancelled:
                return
            self.cancel_requested = True
            if not self.cancellable:
                self.emit("notice", job=self.job, message="Stop requested. Waiting for current package changes to finish.")
                return
            self.cancelled = True
            if self.master is not None:
                os.write(self.master, b"\x03")
            for pending in self.pending.values():
                pending["value"] = None
                pending["ready"].set()

    def interact(self, kind, **data):
        # Helpers may run sudo keep-alive requests concurrently with review.
        # Present one challenge at a time instead of overwriting a pending one.
        with self.interaction_lock:
            return self._interact(kind, **data)

    def _interact(self, kind, **data):
        interaction = secrets.token_hex(16)
        pending = {"ready": threading.Event(), "value": None, "job": self.job}
        with self.lock:
            if self.stopping or self.job is None:
                return None
            self.pending[interaction] = pending
        self.emit("challenge", job=self.job, id=interaction, kind=kind, **data)
        deadline = time.monotonic() + 600
        while not pending["ready"].wait(0.2):
            if self.stopping or self.cancelled or time.monotonic() > deadline:
                break
        with self.lock:
            self.pending.pop(interaction, None)
        self.emit("challenge_clear", id=interaction)
        return pending["value"]

    def answer(self, request):
        with self.lock:
            pending = self.pending.get(request.get("challenge"))
            if pending and request.get("job") == pending["job"] == self.job:
                value = request.get("value")
                if value is None or isinstance(value, bool) or isinstance(value, str) and len(value) <= 4096 and not any(c in value for c in "\r\n\x00"):
                    pending["value"] = value
                    pending["ready"].set()
                    self.cancellable = False

    def serve_auth(self):
        while not self.stopping:
            try:
                connection, _ = self.server.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            threading.Thread(target=self.auth_connection, args=(connection,), daemon=True).start()

    def auth_connection(self, connection):
        with connection:
            try:
                connection.settimeout(620)
                _, uid, _ = struct.unpack("3i", connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
                request = json.loads(connection.makefile("rb").readline(262145))
                if uid != os.getuid() or not hmac.compare_digest(str(request.get("token", "")), self.token):
                    return
                kind = request.get("kind")
                if kind not in ("password", "review"):
                    return
                value = self.interact(kind, prompt=str(request.get("prompt", ""))[:1500], content=str(request.get("content", ""))[:256000])
                connection.sendall((json.dumps({"value": value}) + "\n").encode())
            except (OSError, ValueError):
                return

    def shutdown(self):
        self.stopping = True
        for stop in self.read_tasks.values():
            stop.set()
        for pending in list(self.pending.values()):
            pending["ready"].set()
        if self.job and not self.commit_active:
            self.cancellable = True
            self.cancel({"job": self.job, "confirmed": True})
        if self.worker:
            self.worker.join()
        self.executor.shutdown(wait=True, cancel_futures=True)
        self.server.close()
        shutil.rmtree(self.runtime, ignore_errors=True)


def ask_client(kind, prompt, content=""):
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(620)
        client.connect(os.environ["PACDECK_SOCKET"])
        client.sendall((json.dumps(dict(token=os.environ["PACDECK_TOKEN"], kind=kind, prompt=prompt, content=content)) + "\n").encode())
        return json.loads(client.makefile("rb").readline(65536)).get("value")


def main():
    if len(sys.argv) > 1:
        mode = sys.argv[1]
        if mode == "--exec":
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)
            os.execvpe(sys.argv[2], sys.argv[2:], os.environ)
        if mode == "--askpass":
            value = ask_client("password", " ".join(sys.argv[2:]) or "Administrator password")
            if not isinstance(value, str):
                return 1
            print(value, flush=True)
            return 0
        if mode == "--review":
            files = []
            for name in sys.argv[2:32]:
                path = Path(name)
                if path.is_dir():
                    files.extend(p for p in sorted(path.iterdir()) if p.is_file() and (p.name in ("PKGBUILD", ".SRCINFO") or p.suffix == ".install"))
                elif path.is_file():
                    files.append(path)
            content = "\n\n".join(f"--- {p.name} ---\n{p.read_text(errors='replace')[:128000]}" for p in files)[:256000]
            return 0 if ask_client("review", "Review package build files", content or "No readable build files were provided.") else 1
        return 2
    bridge = Bridge()
    stop = threading.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, lambda *_: stop.set())
    bridge.emit("ready")
    selector = selectors.DefaultSelector()
    selector.register(sys.stdin, selectors.EVENT_READ)
    buffer = b""
    try:
        while not stop.is_set():
            if not selector.select(0.2):
                continue
            chunk = os.read(sys.stdin.fileno(), 8192)
            if not chunk:
                break
            buffer += chunk
            if len(buffer) > 65536:
                raise ValueError("Request exceeds the size limit")
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                try:
                    request = json.loads(line)
                    if not isinstance(request, dict):
                        raise ValueError("Expected a request object")
                    bridge.dispatch(request)
                except (ValueError, KeyError, TypeError):
                    bridge.emit("error", message="Invalid request")
    finally:
        selector.close()
        bridge.shutdown()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError):
        sys.exit(1)
