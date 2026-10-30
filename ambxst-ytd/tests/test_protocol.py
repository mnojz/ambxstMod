import importlib.util
import json
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load_module(name, relative_path):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


bridge = load_module("ytd_protocol", "payload/scripts/ytd_protocol.py")


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


if __name__ == "__main__":
    unittest.main()
