import concurrent.futures
import importlib.util
import json
import os
from pathlib import Path
import queue
import socket
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("pacdeck_backend", ROOT / "overlays/scripts/pacdeck_backend.py")
backend = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(backend)


class ParserTests(unittest.TestCase):
    def test_search_and_ranking(self):
        rows = backend.parse_search("extra/kitty 1.0 [installed]\n    Terminal emulator\naur/kitty-git 2.0\n    Development build\n")
        self.assertTrue(rows[0]["installed"])
        self.assertEqual(rows[1]["description"], "Development build")
        self.assertEqual([r["name"] for r in backend.rank(rows[::-1], "kitty")], ["kitty", "kitty-git"])

    def test_multiline_details_and_updates(self):
        self.assertEqual(backend.parse_info("Name : kitty\nDepends On : glibc\n    python\n")["Depends On"], "glibc python")
        self.assertEqual(backend.parse_updates("kitty 1 -> 2\n"), {"kitty": {"from": "1", "to": "2"}})

    def test_package_name_rejects_options_and_shell_input(self):
        for name in ("-Syu", "x; touch /tmp/pwn", "a\nb", "", "a/b"):
            with self.assertRaises(ValueError):
                backend.Bridge.package_name({"name": name})


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.events = queue.Queue()
        self.recorded = []
        def emit(event):
            self.recorded.append(event)
            self.events.put(event)
        self.bridge = backend.Bridge(emit)

    def tearDown(self):
        self.bridge.job = None
        self.bridge.shutdown()

    def event(self, kind):
        while True:
            value = self.events.get(timeout=5)
            if value["event"] == kind:
                return value

    def test_automatic_detection_and_preferred_fallback(self):
        with patch.object(backend.shutil, "which", side_effect=lambda name: "/usr/bin/yay" if name == "yay" else None):
            self.assertEqual(self.bridge.choose_helper("auto"), "yay")
            self.assertEqual(self.bridge.choose_helper("paru"), "yay")
        with patch.object(backend.shutil, "which", side_effect=lambda name: "/usr/bin/" + name):
            self.assertEqual(self.bridge.choose_helper("yay"), "yay")
            self.assertEqual(self.bridge.helpers, ["paru", "yay"])

    def test_repository_results_are_preserved_when_helper_returns_duplicates(self):
        responses = [
            (0, "extra/kitty 1\n    Official\n", ""),
            (0, "extra/kitty 1\n    Duplicate\naur/kitty-git 2\n    AUR\n", ""),
        ]
        with patch.object(self.bridge, "read_command", side_effect=responses), patch.object(self.bridge, "choose_helper", return_value="yay"):
            self.bridge.search({"id": 1, "query": "kitty"}, threading.Event())
        self.assertEqual(self.recorded[-1]["rows"][0]["description"], "Official")
        self.assertEqual(len(self.recorded[-1]["rows"]), 2)
        self.assertFalse(self.recorded[0]["done"])
        self.assertTrue(self.recorded[-1]["done"])

    def test_transaction_requires_confirmation_and_valid_target(self):
        self.bridge.start_transaction({"id": 1, "operation": "remove", "name": "kitty"})
        self.assertEqual(self.event("error")["message"], "Confirm the transaction first")
        self.bridge.start_transaction({"id": 2, "operation": "install", "name": "--help", "confirmed": True})
        self.assertEqual(self.event("error")["message"], "Invalid package name")
        self.assertIsNone(self.bridge.job)

    def test_askpass_roundtrip_does_not_emit_credentials(self):
        self.bridge.job = 42
        env = {"PACDECK_SOCKET": str(self.bridge.socket_path), "PACDECK_TOKEN": self.bridge.token}
        with patch.dict(os.environ, env), concurrent.futures.ThreadPoolExecutor() as pool:
            result = pool.submit(backend.ask_client, "password", "Administrator password")
            challenge = self.event("challenge")
            self.bridge.answer({"job": 999, "challenge": challenge["id"], "value": "wrong-job"})
            self.assertFalse(result.done())
            self.bridge.answer({"job": 42, "challenge": challenge["id"], "value": "secret-sentinel"})
            self.assertEqual(result.result(timeout=5), "secret-sentinel")
        self.assertNotIn("secret-sentinel", json.dumps(self.recorded))
        self.assertEqual(self.bridge.socket_path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.bridge.runtime.stat().st_mode & 0o777, 0o700)

    def test_authentication_rejects_unknown_token(self):
        self.bridge.job = 1
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(3)
            client.connect(str(self.bridge.socket_path))
            client.sendall(b'{"token":"wrong","kind":"password"}\n')
            self.assertEqual(client.recv(100), b"")
        self.assertFalse(self.recorded)

    def test_pty_prompt_response_progress_and_echo(self):
        self.bridge.job = 7
        code = "import sys; print('Proceed? [Y/n]', end='', flush=True); answer=input(); print('Downloading 25%', flush=True); print('Finished', flush=True)"
        with concurrent.futures.ThreadPoolExecutor() as pool:
            task = pool.submit(self.bridge.run_pty, [sys.executable, "-c", code], backend.environment(), safe=True)
            prompt = self.event("prompt")
            self.bridge.write_input({"job": 7, "prompt": prompt["id"], "value": "yes-sentinel"})
            task.result(timeout=5)
        output = "".join(event.get("text", "") for event in self.recorded)
        self.assertIn("Finished", output)
        self.assertNotIn("yes-sentinel", output)
        self.assertTrue(any(event.get("progress") == 25 for event in self.recorded))

    def test_package_query_cancel_and_locale(self):
        stop = threading.Event()
        stop.set()
        with self.assertRaises(InterruptedError):
            self.bridge.read_command(["sleep", "10"], stop)
        code, output, _ = self.bridge.read_command([sys.executable, "-c", "import os;print(os.environ['LC_ALL'])"])
        self.assertEqual((code, output.strip()), (0, "C"))

    def test_cancellation_is_blocked_during_commit(self):
        self.bridge.job = 7
        self.bridge.cancellable = False
        self.bridge.cancel({"job": 7, "confirmed": True})
        self.assertFalse(self.bridge.cancelled)
        self.assertTrue(self.bridge.cancel_requested)
        self.assertIn("finish", self.event("notice")["message"])

    def test_stop_requires_explicit_confirmation(self):
        self.bridge.job = 7
        self.bridge.cancellable = True
        self.bridge.cancel({"job": 7})
        self.assertFalse(self.bridge.cancel_requested)
        self.assertFalse(self.bridge.cancelled)

    def test_queued_stop_prevents_next_command_after_commit(self):
        self.bridge.job = 7
        self.bridge.cancel_requested = True
        with self.assertRaisesRegex(RuntimeError, "cancelled"):
            self.bridge.run_pty(["unused"], {})
        self.assertTrue(self.bridge.cancelled)

    def test_queued_stop_activates_when_the_next_stage_is_safe(self):
        self.bridge.job = 7
        self.bridge.cancellable = False
        self.bridge.cancel({"job": 7, "confirmed": True})
        self.assertTrue(self.bridge.cancel_requested)
        self.assertFalse(self.bridge.cancelled)
        self.bridge.track_progress("==> Starting build()")
        self.assertTrue(self.bridge.cancelled)
        with self.assertRaisesRegex(RuntimeError, "cancelled"):
            self.bridge.run_pty(["unused"], {})

    def test_real_progress_switches_to_indeterminate_for_building(self):
        self.bridge.job = 7
        self.bridge.track_progress("Downloading 67%")
        self.bridge.track_progress("==> Starting build()")
        self.assertEqual(self.recorded[-1]["label"], "Building")
        self.assertIsNone(self.recorded[-1]["progress"])
        self.bridge.track_progress("installing kitty")
        self.assertFalse(self.bridge.cancellable)

    def test_both_helpers_use_embedded_sudo_and_review_wrappers(self):
        for helper in backend.HELPERS:
            self.bridge.job = 12
            argv = []
            with patch.object(self.bridge, "choose_helper", return_value=helper), patch.object(self.bridge, "run_pty", side_effect=lambda args, *_, **__: argv.append(args)):
                self.bridge.transaction({"id": 12, "operation": "install", "name": "kitty-git", "repo": "aur", "helper": helper})
            self.assertEqual(Path(argv[0][0]).name, helper)
            self.assertIn("--sudo", argv[0])
            self.assertIn("--noconfirm", argv[0])
            self.assertIn("--fm" if helper == "paru" else "--editor", argv[0])
            self.assertEqual(argv[0][-2:], ["--", "kitty-git"])
            self.assertIn("sudo -A", (self.bridge.runtime / "sudo").read_text())
            self.assertTrue(self.recorded[-1]["ok"])

    def test_official_packages_do_not_require_an_aur_helper(self):
        self.bridge.job = 12
        argv = []
        with patch.object(self.bridge, "choose_helper", return_value=""), patch.object(self.bridge, "run_pty", side_effect=lambda args, *_, **__: argv.append(args)):
            self.bridge.transaction({"id": 12, "operation": "install", "name": "kitty", "repo": "extra"})
        self.assertEqual(Path(argv[0][1]).name, "pacman")
        self.assertTrue(self.recorded[-1]["ok"])

    def test_complete_background_transaction_with_askpass_and_confirmation(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            sudo = directory / "sudo"
            pacman = directory / "pacman"
            sudo.write_text("#!" + sys.executable + "\n" +
                "import os, subprocess, sys\n" +
                "auth = subprocess.run([os.environ['SUDO_ASKPASS'], 'Test password'], capture_output=True, text=True)\n" +
                "if auth.returncode or auth.stdout.strip() != 'credential-sentinel': sys.exit(1)\n" +
                "args = sys.argv[1:]; args.remove('-A')\n" +
                "sys.exit(subprocess.call(args))\n")
            pacman.write_text("#!" + sys.executable + "\n" +
                "print('Proceed? [Y/n]', end='', flush=True)\n" +
                "answer = input()\n" +
                "print('Downloading packages 50%', flush=True)\n" +
                "print('installing example', flush=True)\n" +
                "raise SystemExit(0 if answer.lower() == 'y' else 1)\n")
            sudo.chmod(0o700)
            pacman.chmod(0o700)
            original = backend.executable
            def executable(name):
                return str(directory / name) if name in ('sudo', 'pacman') else original(name)
            with patch.object(backend, "executable", side_effect=executable), patch.object(self.bridge, "choose_helper", return_value=""):
                self.bridge.start_transaction({"id": 71, "operation": "install", "name": "example", "repo": "extra", "confirmed": True})
                challenge = self.event("challenge")
                self.bridge.answer({"job": 71, "challenge": challenge["id"], "value": "credential-sentinel"})
                prompt = self.event("prompt")
                self.bridge.write_input({"job": 71, "prompt": prompt["id"], "value": "y"})
                finished = self.event("finished")
                self.bridge.worker.join(timeout=5)
            self.assertTrue(finished["ok"], finished)
            self.assertNotIn("credential-sentinel", json.dumps(self.recorded))
            self.assertTrue(any(e.get("progress") == 50 for e in self.recorded))

    def test_bootstrap_both_helpers_build_after_review(self):
        original = backend.shutil.which
        for helper in backend.HELPERS:
            self.bridge.job = 15
            installed = False
            calls = []
            def which(name):
                if name == helper:
                    return "/usr/bin/" + helper if installed else None
                return original(name)
            def run(argv, *args, **kwargs):
                nonlocal installed
                calls.append(argv)
                if Path(argv[0]).name == "git":
                    checkout = Path(argv[-1])
                    checkout.mkdir()
                    (checkout / "PKGBUILD").write_text("pkgname=" + helper + "\n")
                if Path(argv[0]).name == "makepkg":
                    installed = True
            env = self.bridge.prepare_environment()
            with patch.object(backend.shutil, "which", side_effect=which), patch.object(self.bridge, "run_pty", side_effect=run), patch.object(self.bridge, "interact", return_value=True) as review:
                self.bridge.bootstrap(helper, env)
            self.assertTrue(installed)
            self.assertEqual(len(calls), 3)
            review.assert_called_once()
            self.assertEqual(calls[-1][1:], ["-si", "--noconfirm"])

    def test_commit_in_same_output_chunk_disables_cancellation(self):
        self.bridge.job = 7
        self.bridge.track_progress("Downloading packages 100%\nchecking package integrity\ninstalling example\n")
        self.assertFalse(self.bridge.cancellable)
        self.assertEqual(self.recorded[-1]["label"], "Applying package changes")

    def test_bootstrap_requires_build_review_before_makepkg(self):
        self.bridge.job = 15
        calls = []
        original = backend.shutil.which
        def which(name):
            return None if name == "yay" else original(name)
        def run(argv, *args, **kwargs):
            calls.append(argv)
            if Path(argv[0]).name == "git":
                checkout = Path(argv[-1])
                checkout.mkdir()
                (checkout / "PKGBUILD").write_text("pkgname=yay\n")
        env = self.bridge.prepare_environment()
        with patch.object(backend.shutil, "which", side_effect=which), patch.object(self.bridge, "run_pty", side_effect=run), patch.object(self.bridge, "interact", return_value=False):
            with self.assertRaisesRegex(RuntimeError, "review declined"):
                self.bridge.bootstrap("yay", env)
        self.assertEqual(len(calls), 2)
        self.assertFalse(any(Path(argv[0]).name == "makepkg" for argv in calls))


if __name__ == "__main__":
    unittest.main()
