import contextlib
import importlib.util
import io
import os
import signal
import subprocess
import sys
import time
import unittest
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


if __name__ == "__main__":
    unittest.main()
