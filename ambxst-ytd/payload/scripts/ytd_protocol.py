#!/usr/bin/env python3
import json
import re
import shutil
import subprocess
import sys
from urllib.parse import parse_qs, urlencode, urlparse, urlunparse

FORMAT_MAP = {
    "audio": "mp3",
    "mp3": "mp3",
    "sd": "480p",
    "hd": "720p",
    "fhd": "1080p",
    "qhd": "1440p",
    "uhd": "2160p",
    "480p": "480p",
    "720p": "720p",
    "1080p": "1080p",
    "1440p": "1440p",
    "2160p": "2160p",
}

GENERATION_MARKER = "/ambxst/mods/generations/"

YOUTUBE_HOSTS = frozenset({
    "youtube.com",
    "www.youtube.com",
    "m.youtube.com",
    "music.youtube.com",
    "youtu.be",
    "www.youtu.be",
})

VIDEO_PATH_PREFIXES = ("/shorts/", "/embed/", "/live/", "/v/")
ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{6,}$")

INVALID_URL_MESSAGE = "Not a valid YouTube or YouTube Music URL"
PLAYLIST_REQUIRED_MESSAGE = "This is a playlist link, choose Whole playlist to download it"


def decode_protocol(value):
    for prefix in ("ytd://", "ytd:"):
        if value.startswith(prefix):
            return value[len(prefix):]
    return value


def _video_id(parsed):
    host = parsed.netloc.lower()
    if host in ("youtu.be", "www.youtu.be"):
        candidate = parsed.path.strip("/").split("/")[0]
        return candidate if ID_PATTERN.match(candidate) else ""
    if parsed.path == "/watch":
        candidate = (parse_qs(parsed.query).get("v") or [""])[0]
        return candidate if ID_PATTERN.match(candidate) else ""
    for prefix in VIDEO_PATH_PREFIXES:
        if parsed.path.startswith(prefix):
            candidate = parsed.path[len(prefix):].split("/")[0]
            return candidate if ID_PATTERN.match(candidate) else ""
    return ""


def is_youtube_url(url):
    """True for a YouTube or YouTube Music link naming a video or a playlist."""
    parsed = urlparse(str(url or "").strip())
    if parsed.scheme not in ("http", "https"):
        return False
    if parsed.netloc.lower() not in YOUTUBE_HOSTS:
        return False
    if _video_id(parsed):
        return True
    return bool(parse_qs(parsed.query).get("list", [""])[0])


def parse_request(value, default_scope="single"):
    """Return (media URL, format, scope, error) for a ytd: request.

    The link is validated here so an invalid URL is reported to the desktop
    instead of being forwarded to the shell. ``scope`` is "playlist" only when
    the link asks for it; otherwise the list parameter is dropped so a shared
    playlist link never downloads the whole playlist by accident.
    """
    decoded = decode_protocol(value)
    parsed = urlparse(decoded)
    params = parse_qs(parsed.query, keep_blank_values=True)

    requested = params.get("format", ["1080p"])[0].strip().lower()
    media_format = FORMAT_MAP.get(requested, "1080p")

    if params.get("playlist", ["0"])[0].strip().lower() in ("1", "true", "yes"):
        scope = "playlist"
    elif params.get("scope", [""])[0].strip().lower() == "playlist":
        scope = "playlist"
    else:
        scope = default_scope

    if not is_youtube_url(decoded):
        return "", media_format, scope, INVALID_URL_MESSAGE

    # A playlist-only link names no single video, so single scope cannot be
    # honoured by dropping the list parameter.
    if scope != "playlist" and not _video_id(parsed):
        return "", media_format, scope, PLAYLIST_REQUIRED_MESSAGE

    drop = {"format", "scope", "playlist"}
    if scope != "playlist":
        drop.add("list")
    query = [
        (key, item)
        for key, values in params.items()
        if key not in drop
        for item in values
    ]
    clean_url = urlunparse(parsed._replace(query=urlencode(query)))
    return clean_url, media_format, scope, None


def is_ambxst_shell(entry):
    if not isinstance(entry, dict):
        return False
    config_path = str(entry.get("config_path") or "")
    return entry.get("shell_id") == "ambxst" and GENERATION_MARKER in config_path


def find_ambxst_pid():
    """Find a generation shell without matching arbitrary command lines."""
    result = subprocess.run(
        ["qs", "list", "-a", "-j"],
        capture_output=True,
        text=True,
        check=False,
        timeout=5,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or "qs list failed"
        raise RuntimeError(detail)

    try:
        entries = json.loads(result.stdout or "[]")
    except json.JSONDecodeError as error:
        raise RuntimeError("qs list returned invalid JSON") from error

    candidates = [entry for entry in entries if is_ambxst_shell(entry)]
    if not candidates:
        raise RuntimeError("Ambxst is not running")
    candidates.sort(key=lambda entry: str(entry.get("launch_time") or ""), reverse=True)
    return str(candidates[0]["pid"])


def notify_error(message):
    executable = shutil.which("notify-send")
    if not executable:
        return
    try:
        subprocess.run(
            [executable, "--app-name=Ambxst YTD", "Download not started", message],
            check=False,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        pass


def main(argv=None):
    args = sys.argv if argv is None else argv
    if len(args) < 2:
        print("Usage: ytd.py ytd:URL", file=sys.stderr)
        return 2

    clean_url, media_format, scope, error = parse_request(args[1])
    if error:
        print("YTD bridge:", error, file=sys.stderr)
        notify_error(error)
        return 3

    try:
        pid = find_ambxst_pid()
        result = subprocess.run(
            ["qs", "ipc", "--pid", pid, "call", "ytd", "download",
             clean_url, media_format, scope],
            check=False,
            timeout=10,
        )
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print("YTD bridge:", error, file=sys.stderr)
        notify_error(str(error))
        return 1

    if result.returncode != 0:
        notify_error("Ambxst rejected the download request (IPC exit %s)" % result.returncode)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())