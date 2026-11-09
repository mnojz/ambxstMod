import contextlib
import importlib.util
import json
from types import SimpleNamespace
from unittest.mock import patch
import io
import os
import signal
import subprocess
import sys
import time
import unittest
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "ytd_helper", ROOT / "payload/scripts/ytd_helper.py"
)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class HelperOptionTests(unittest.TestCase):
    def test_format_query_is_removed_only_for_youtube(self):
        self.assertEqual(
            helper.normalize_url(" https://youtu.be/abc123?format=720p&t=4 "),
            "https://youtu.be/abc123?t=4",
        )
        self.assertEqual(
            helper.normalize_url("https://example.com/video?format=720p"),
            "https://example.com/video?format=720p",
        )

    def test_list_is_dropped_for_single_scope(self):
        self.assertEqual(
            helper.normalize_url("https://www.youtube.com/watch?v=abc123&list=PLxyz"),
            "https://www.youtube.com/watch?v=abc123",
        )
        self.assertEqual(
            helper.normalize_url(
                "https://www.youtube.com/watch?v=abc123&list=PLxyz", "single"
            ),
            "https://www.youtube.com/watch?v=abc123",
        )

    def test_list_is_kept_for_playlist_scope(self):
        self.assertEqual(
            helper.normalize_url(
                "https://www.youtube.com/watch?v=abc123&list=PLxyz", "playlist"
            ),
            "https://www.youtube.com/watch?v=abc123&list=PLxyz",
        )

    def test_mod_only_parameters_are_always_removed(self):
        self.assertEqual(
            helper.normalize_url(
                "https://www.youtube.com/watch?v=abc123&scope=playlist&playlist=1&list=PL",
                "playlist",
            ),
            "https://www.youtube.com/watch?v=abc123&list=PL",
        )

    def test_is_youtube_url_accepts_only_youtube_links(self):
        for good in (
            "https://www.youtube.com/watch?v=abc123",
            "https://youtu.be/abc123",
            "https://music.youtube.com/watch?v=abc123",
            "https://m.youtube.com/watch?v=abc123",
            "https://www.youtube.com/shorts/abc123",
            "https://www.youtube.com/live/abc123",
            "https://www.youtube.com/embed/abc123",
            "https://www.youtube.com/playlist?list=PLxyz",
            "http://youtu.be/abc123",
        ):
            with self.subTest(url=good):
                self.assertTrue(helper.is_youtube_url(good))

        for bad in (
            "https://example.invalid/video",
            "https://vimeo.com/12345",
            "https://soundcloud.com/track/1",
            "ftp://www.youtube.com/watch?v=abc123",
            "https://www.youtube.com/",
            "https://www.youtube.com/watch",
            "https://www.youtube.com/feed/subscriptions",
            "https://youtube.com.evil.test/watch?v=abc123",
            "https://notyoutube.com/watch?v=abc123",
            "www.youtube.com/watch?v=abc123",
            "",
        ):
            with self.subTest(url=bad):
                self.assertFalse(helper.is_youtube_url(bad))

    def test_media_options(self):
        video = helper.media_options("/tmp", "720p")
        self.assertEqual(video["format"], helper.FORMATS["720p"])
        self.assertEqual(video["outtmpl"], "/tmp/Videos/%(title)s.%(ext)s")
        self.assertTrue(video["merge_output_format"] == "mp4")

        audio = helper.media_options("/tmp", "mp3")
        self.assertEqual(audio["format"], "bestaudio/best")
        self.assertEqual(audio["outtmpl"], "/tmp/Music/%(title)s.%(ext)s")
        self.assertEqual(audio["postprocessors"][0]["key"], "FFmpegExtractAudio")

    def test_final_path_prefers_final_filepath(self):
        self.assertEqual(helper.final_path({"filepath": "/tmp/final.mp4"}), "/tmp/final.mp4")
        self.assertEqual(
            helper.final_path({"requested_downloads": [{"filepath": "/tmp/merged.mp4"}]}),
            "/tmp/merged.mp4",
        )
        self.assertEqual(helper.final_path(None), "")


class EventTests(unittest.TestCase):
    def setUp(self):
        self.tracker = helper.FinishedTracker()
        self.output = io.StringIO()

    def test_progress_payload_contains_playlist_identity(self):
        payload = helper.progress_payload({
            "status": "downloading",
            "filename": "/tmp/video.f137.mp4",
            "downloaded_bytes": 25,
            "total_bytes": 100,
            "speed": 5,
            "eta": 15,
            "info_dict": {
                "id": "video-id",
                "title": "Video title",
                "webpage_url": "https://youtu.be/video-id",
                "playlist_index": 2,
                "playlist_count": 3,
            },
        })
        self.assertEqual(payload["item_id"], "video-id")
        self.assertEqual(payload["index"], 2)
        self.assertEqual(payload["count"], 3)
        self.assertEqual(payload["percent"], 25)

    def test_tracker_deduplicates_streams_and_uses_postprocessed_path(self):
        base = {
            "status": "finished",
            "filename": "/tmp/video.f137.mp4",
            "info_dict": {"id": "video-id", "title": "Video title"},
        }
        with contextlib.redirect_stdout(self.output):
            self.tracker.report(base)
            self.tracker.report({**base, "filename": "/tmp/video.f140.m4a"})
            self.tracker.postprocess({
                "status": "finished",
                "filename": "/tmp/video.mp3",
                "info_dict": {"id": "video-id", "title": "Video title"},
            })

        self.assertEqual(len(self.tracker.items), 1)
        self.assertEqual(self.tracker.items[0]["filename"], "/tmp/video.mp3")
        self.assertEqual(self.output.getvalue().count('"event": "finished"'), 1)

    def test_tracker_monotonic_progress_across_multi_streams(self):
        tracker = helper.FinishedTracker()
        req_formats = [{"format_id": "137"}, {"format_id": "140"}]

        # Video stream 50%
        p1 = tracker.calculate_percent(
            {"percent": 50, "event": "downloading"},
            {"info_dict": {"format_id": "137", "requested_formats": req_formats}},
        )
        self.assertEqual(p1, 44.0)

        # Video stream 100%
        p2 = tracker.calculate_percent(
            {"percent": 100, "event": "downloading"},
            {"info_dict": {"format_id": "137", "requested_formats": req_formats}},
        )
        self.assertEqual(p2, 88.0)

        # Audio stream starts at 0% - must NOT decrease back to 0!
        p3 = tracker.calculate_percent(
            {"percent": 0, "event": "downloading"},
            {"info_dict": {"format_id": "140", "requested_formats": req_formats}},
        )
        self.assertGreaterEqual(p3, p2)

        # Audio stream at 50%
        p4 = tracker.calculate_percent(
            {"percent": 50, "event": "downloading"},
            {"info_dict": {"format_id": "140", "requested_formats": req_formats}},
        )
        self.assertEqual(p4, 93.0)

        # Audio finished
        p5 = tracker.calculate_percent(
            {"percent": 100, "event": "finished"},
            {"info_dict": {"format_id": "140", "requested_formats": req_formats}},
        )
        self.assertEqual(p5, 98.0)

    def test_tracker_never_decreases_on_jitter(self):
        tracker = helper.FinishedTracker()
        p1 = tracker.calculate_percent({"percent": 52.5, "event": "downloading"}, {})
        p2 = tracker.calculate_percent({"percent": 51.0, "event": "downloading"}, {})
        self.assertGreaterEqual(p2, p1)
        self.assertEqual(p2, p1)

    def test_complete_payload_contains_final_items(self):
        complete = helper.complete_payload(
            {"title": "Playlist"},
            [{"item_id": "a", "filename": "/tmp/a.mp4"}],
        )
        self.assertEqual(complete["count"], 1)
        self.assertEqual(complete["filename"], "/tmp/a.mp4")
        self.assertEqual(complete["items"][0]["item_id"], "a")
    def test_complete_payload_reconciles_final_media_paths(self):
        merged = helper.complete_payload(
            {"title": "Video", "filepath": "/tmp/video.mp4"},
            [{"item_id": "video-id", "filename": "/tmp/video.f137.mp4"}],
        )
        self.assertEqual(merged["items"][0]["filename"], "/tmp/video.mp4")
        self.assertEqual(merged["filename"], "/tmp/video.mp4")

        playlist = helper.complete_payload(
            {
                "_type": "playlist",
                "title": "Playlist",
                "entries": [
                    {"id": "a", "filepath": "/tmp/a.mp4"},
                    {"id": "b", "filepath": "/tmp/b.mp4"},
                ],
            },
            [
                {"item_id": "a", "filename": "/tmp/a.f137.mp4"},
                {"item_id": "b", "filename": "/tmp/b.f251.webm"},
            ],
        )
        self.assertEqual(
            [item["filename"] for item in playlist["items"]],
            ["/tmp/a.mp4", "/tmp/b.mp4"],
        )


class ProcessGroupTests(unittest.TestCase):
    def test_sigterm_kills_child_process(self):
        script = """
import importlib.util
import json
from types import SimpleNamespace
from unittest.mock import patch
import subprocess
import sys
import time
spec = importlib.util.spec_from_file_location("helper", sys.argv[1])
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
helper.isolate_process_group()
child = subprocess.Popen(["/usr/bin/sleep", "30"])
print(child.pid, flush=True)
helper.install_signal_handlers()
print("ready", flush=True)
while True:
    time.sleep(1)
"""
        process = subprocess.Popen(
            [sys.executable, "-c", script, str(ROOT / "payload/scripts/ytd_helper.py")],
            stdout=subprocess.PIPE,
            text=True,
        )
        child_pid = int(process.stdout.readline().strip())
        self.assertEqual(process.stdout.readline().strip(), "ready")
        try:
            process.send_signal(signal.SIGTERM)
            self.assertEqual(process.wait(timeout=5), helper.EXIT_CANCELLED)
            process.stdout.close()
            deadline = time.monotonic() + 2
            while time.monotonic() < deadline:
                try:
                    with open(f"/proc/{child_pid}/stat", "rb") as handle:
                        state = handle.read().rsplit(b")", 1)[1].split()[0]
                    if state == b"Z":
                        break
                except FileNotFoundError:
                    break
                time.sleep(0.05)
            else:
                self.fail("FFmpeg placeholder child was not terminated")
        finally:
            if process.poll() is None:
                process.kill()
            with contextlib.suppress(ProcessLookupError):
                os.kill(child_pid, signal.SIGKILL)



spec = importlib.util.spec_from_file_location(
    "ytd_protocol", ROOT / "payload/scripts/ytd_protocol.py"
)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class ProtocolParsingTests(unittest.TestCase):
    def test_legacy_format_alias_and_stripping(self):
        url, media_format, scope, error = bridge.parse_request(
            "ytd:https://youtu.be/abc123?format=HD&t=2&format=mp3"
        )
        self.assertIsNone(error)
        self.assertEqual(url, "https://youtu.be/abc123?t=2")
        self.assertEqual(media_format, "720p")
        self.assertEqual(scope, "single")

    def test_unknown_and_missing_formats_use_default(self):
        self.assertEqual(
            bridge.parse_request("ytd:https://youtu.be/abc123?format=unknown")[:2],
            ("https://youtu.be/abc123", "1080p"),
        )
        self.assertEqual(
            bridge.parse_request("ytd://https://youtu.be/abc123")[:2],
            ("https://youtu.be/abc123", "1080p"),
        )

    def test_list_is_removed_for_single_scope(self):
        url, _, scope, error = bridge.parse_request(
            "ytd:https://www.youtube.com/watch?v=abc123&list=PLxyz"
        )
        self.assertIsNone(error)
        self.assertEqual(scope, "single")
        self.assertEqual(url, "https://www.youtube.com/watch?v=abc123")

    def test_playlist_parameter_keeps_list(self):
        url, _, scope, error = bridge.parse_request(
            "ytd:https://www.youtube.com/watch?v=abc123&list=PLxyz&playlist=1"
        )
        self.assertIsNone(error)
        self.assertEqual(scope, "playlist")
        self.assertEqual(url, "https://www.youtube.com/watch?v=abc123&list=PLxyz")

    def test_scope_parameter_keeps_list(self):
        _, _, scope, _ = bridge.parse_request(
            "ytd:https://www.youtube.com/watch?v=abc123&list=PLxyz&scope=playlist"
        )
        self.assertEqual(scope, "playlist")

    def test_music_youtube_is_valid(self):
        url, _, _, error = bridge.parse_request(
            "ytd:https://music.youtube.com/watch?v=abc123&list=OLAK5"
        )
        self.assertIsNone(error)
        self.assertEqual(url, "https://music.youtube.com/watch?v=abc123")

    def test_playlist_only_url_needs_playlist_scope(self):
        url, _, scope, error = bridge.parse_request(
            "ytd:https://www.youtube.com/playlist?list=PLxyz"
        )
        self.assertEqual(scope, "single")
        # A playlist link has no single video, so it is reported instead of
        # being rewritten into a link that names no media at all.
        self.assertEqual(error, bridge.PLAYLIST_REQUIRED_MESSAGE)
        self.assertEqual(url, "")

        url, _, scope, error = bridge.parse_request(
            "ytd:https://www.youtube.com/playlist?list=PLxyz&playlist=1"
        )
        self.assertIsNone(error)
        self.assertEqual(scope, "playlist")
        self.assertEqual(url, "https://www.youtube.com/playlist?list=PLxyz")

    def test_invalid_urls_are_rejected(self):
        for bad in (
            "ytd:https://example.invalid/video?format=1080p",
            "ytd:https://vimeo.com/12345",
            "ytd:ftp://www.youtube.com/watch?v=abc123",
            "ytd:https://www.youtube.com/",
            "ytd:https://www.youtube.com/watch",
            "ytd:not a url",
            "ytd:",
        ):
            with self.subTest(url=bad):
                url, _, _, error = bridge.parse_request(bad)
                self.assertIsNotNone(error)
                self.assertEqual(url, "")

    def test_lookalike_hosts_are_rejected(self):
        for bad in (
            "https://www.youtube.com.evil.test/watch?v=abc123",
            "https://notyoutube.com/watch?v=abc123",
            "https://youtube.com.attacker.net/watch?v=abc123",
        ):
            with self.subTest(url=bad):
                self.assertFalse(bridge.is_youtube_url(bad))


class ProcessDiscoveryTests(unittest.TestCase):
    def test_only_ambxst_generation_shells_match(self):
        self.assertTrue(bridge.is_ambxst_shell({
            "shell_id": "ambxst",
            "config_path": "/home/u/.local/share/ambxst/mods/generations/x/shell.qml",
        }))
        self.assertFalse(bridge.is_ambxst_shell({
            "shell_id": "ambxst-veil",
            "config_path": "/tmp/veil.qml",
        }))
        self.assertFalse(bridge.is_ambxst_shell({
            "shell_id": "ambxst",
            "config_path": "/tmp/shell.qml",
        }))

    @patch.object(bridge.subprocess, "run")
    def test_latest_running_shell_wins(self, run):
        payload = json.dumps([
            {
                "config_path": "/home/u/.local/share/ambxst/mods/generations/old/shell.qml",
                "launch_time": "2026-01-01T00:00:00",
                "pid": 10,
                "shell_id": "ambxst",
            },
            {
                "config_path": "/home/u/.local/share/ambxst/mods/generations/new/shell.qml",
                "launch_time": "2026-01-02T00:00:00",
                "pid": 20,
                "shell_id": "ambxst",
            },
        ])
        run.return_value = SimpleNamespace(returncode=0, stdout=payload, stderr="")
        self.assertEqual(bridge.find_ambxst_pid(), "20")
        run.assert_called_once_with(
            ["qs", "list", "-a", "-j"],
            capture_output=True,
            text=True,
            check=False,
            timeout=5,
        )

    @patch.object(bridge.subprocess, "run")
    def test_no_shell_is_an_error(self, run):
        run.return_value = SimpleNamespace(returncode=0, stdout="[]", stderr="")
        with self.assertRaisesRegex(RuntimeError, "not running"):
            bridge.find_ambxst_pid()


class InstallerRequirementTests(unittest.TestCase):
    def run_check(self, missing="", answer="", distro="arch", fail=False):
        # Run the real preflight/prompt logic with simulated tools. Never sudo
        # or touch the real package manager, home directory, or desktop session.
        script = (ROOT / "scripts/install.sh").read_text().split("setup_dir=$(mktemp -d)")[0]
        script = script.replace("if ((EUID == 0)); then", "if false; then")
        stubs = r"""
source() { ID="$TEST_DISTRO"; ID_LIKE=; }
command() {
    if [[ "$1" == -v ]]; then
        if [[ ! -f "$MARKER" && " $MISSING " == *" $2 "* ]]; then
            return 1
        fi
        return 0
    fi
    builtin command "$@"
}
python3() {
    [[ -f "$MARKER" || " $MISSING " != *" yt_dlp "* ]]
}
sudo() {
    printf '%s\n' "$*" >> "$CALLS"
    [[ "$FAIL_INSTALL" == 0 ]] || return 1
    touch "$MARKER"
}
"""
        with tempfile.TemporaryDirectory() as temp:
            env = dict(os.environ, MISSING=missing, TEST_DISTRO=distro,
                       MARKER=temp + "/installed", CALLS=temp + "/calls",
                       FAIL_INSTALL=str(int(fail)))
            result = subprocess.run(["bash", "-c", stubs + script], input=answer,
                                    capture_output=True, text=True, env=env)
            calls = Path(temp + "/calls")
            return result, calls.read_text() if calls.exists() else ""

    def test_installed_dependencies_skip_prompt(self):
        result, calls = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Installed", result.stdout)
        self.assertNotIn("[y/N]", result.stdout)
        self.assertEqual(calls, "")

    def test_no_or_eof_cancels_without_package_installation(self):
        for answer in ("n\n", "", "\n"):
            result, calls = self.run_check("ffmpeg", answer)
            self.assertEqual(result.returncode, 0)
            self.assertIn("Cancelled", result.stdout)
            self.assertEqual(calls, "")

    def test_arch_installs_only_missing_packages_and_deduplicates(self):
        result, calls = self.run_check("ffmpeg xdg-open xdg-mime yt_dlp yt-dlp", "y\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, "pacman -S --needed yt-dlp ffmpeg xdg-utils\n")
        self.assertIn("Not installed", result.stdout)
        self.assertIn("Checking requirements again", result.stdout)

    def test_ubuntu_uses_correct_package_names(self):
        result, calls = self.run_check("python3 gio wl-paste", "y\n", "ubuntu")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, "apt-get install python3 yt-dlp wl-clipboard libglib2.0-bin\n")

    def test_failed_installation_stops(self):
        result, calls = self.run_check("ffmpeg", "y\n", fail=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(calls)
        self.assertNotIn("Checking requirements again", result.stdout)

    def test_unsupported_distribution_and_missing_ambxst_stop(self):
        for missing, distro in (("ffmpeg", "nixos"), ("ambxst", "arch")):
            result, calls = self.run_check(missing, "y\n", distro)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(calls, "")


if __name__ == "__main__":
    unittest.main()
