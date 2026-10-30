#!/usr/bin/env python3
"""yt-dlp helper for the Ambxst YTD mod.

Emits one JSON object per line on stdout so the QuickShell side can render
progress. yt-dlp runs inside this process, so cancellation (SIGTERM) tears down
the child FFmpeg jobs as well instead of leaving them behind.
"""
import json
import os
import re
import signal
import sys
from urllib.parse import parse_qs, urlencode, urlparse, urlunparse

import yt_dlp

FORMATS = {
    "480p": "bv*[height<=480]+ba/bv*+ba/b",
    "720p": "bv*[height<=720]+ba/bv*+ba/b",
    "1080p": "bv*[height<=1080]+ba/bv*+ba/b",
    "1440p": "bv*[height<=1440]+ba/bv*+ba/b",
    "2160p": "bv*[height<=2160]+ba/bv*+ba/b",
}

YOUTUBE_HOSTS = (
    "youtube.com",
    "www.youtube.com",
    "m.youtube.com",
    "music.youtube.com",
    "youtu.be",
    "www.youtu.be",
)

SCOPES = ("single", "playlist")
VIDEO_PATH_PREFIXES = ("/shorts/", "/embed/", "/live/", "/v/")
ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{6,}$")

EXIT_CANCELLED = 130
EXIT_INVALID = 3
EXIT_PLAYLIST_REQUIRED = 4


def emit(payload):
    print(json.dumps(payload), flush=True)


def parse_video_id(parsed):
    """Video id of a YouTube watch/short link, or an empty string."""
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
    """True for a YouTube or YouTube Music link that points at a video or playlist."""
    parsed = urlparse(str(url or "").strip())
    if parsed.scheme not in ("http", "https"):
        return False
    if parsed.netloc.lower() not in YOUTUBE_HOSTS:
        return False
    if parse_video_id(parsed):
        return True
    return bool(parse_qs(parsed.query).get("list", [""])[0])


def normalize_url(url, scope="single"):
    """Drop mod-only query keys, and the playlist id unless the whole playlist is wanted."""
    text = str(url or "").strip()
    parsed = urlparse(text)
    if parsed.scheme not in ("http", "https") or parsed.netloc.lower() not in YOUTUBE_HOSTS:
        return text
    query = parse_qs(parsed.query, keep_blank_values=True)
    query.pop("format", None)
    query.pop("scope", None)
    query.pop("playlist", None)
    if scope != "playlist":
        query.pop("list", None)
    return urlunparse(parsed._replace(query=urlencode(query, doseq=True)))


def media_options(home, media_format):
    """yt-dlp options for a format. Pure, so it can be unit tested."""
    common = {
        "quiet": True,
        "no_warnings": True,
        "noprogress": True,
        "http_headers": {
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/131 Safari/537.36",
        },
    }
    if media_format == "mp3":
        options = {
            "outtmpl": os.path.join(home, "Music", "%(title)s.%(ext)s"),
            "format": "bestaudio/best",
            "restrictfilenames": True,
            "postprocessors": [{
                "key": "FFmpegExtractAudio",
                "preferredcodec": "mp3",
                "preferredquality": "0",
            }],
        }
    else:
        options = {
            "outtmpl": os.path.join(home, "Videos", "%(title)s.%(ext)s"),
            "format": FORMATS[media_format],
            "merge_output_format": "mp4",
            "restrictfilenames": True,
        }
    options.update(common)
    return options


def final_path(info):
    """Path of the finished file described by an info dict, or an empty string."""
    if not isinstance(info, dict):
        return ""
    path = info.get("filepath") or info.get("_filename") or ""
    if path:
        return path
    for download in info.get("requested_downloads") or []:
        if isinstance(download, dict) and download.get("filepath"):
            return download["filepath"]
    return ""


def progress_payload(data):
    """Map a yt-dlp progress hook payload onto the JSON event we emit."""
    info = data.get("info_dict") or {}
    total = data.get("total_bytes") or data.get("total_bytes_estimate") or 0
    downloaded = data.get("downloaded_bytes") or 0
    return {
        "event": data.get("status", ""),
        "item_id": str(info.get("id") or data.get("filename") or ""),
        "title": info.get("title") or os.path.basename(data.get("filename") or ""),
        "filename": data.get("filename") or final_path(info),
        "thumbnail": info.get("thumbnail") or "",
        "url": info.get("webpage_url") or info.get("original_url") or "",
        "index": int(info.get("playlist_index") or 0),
        "count": int(info.get("playlist_count") or info.get("n_entries") or 0),
        "downloaded": downloaded,
        "total": total,
        "speed": data.get("speed") or 0,
        "eta": data.get("eta") or 0,
        "percent": downloaded / total * 100 if total else 0,
    }


class FinishedTracker:
    """Deduplicate stream hooks and retain final per-item output paths."""

    def __init__(self):
        self.items = []
        self._indexes = {}

    @staticmethod
    def _key(payload):
        return payload.get("item_id") or payload.get("filename") or ""

    def _record(self, payload):
        key = self._key(payload)
        if not key:
            return
        item = {
            "item_id": str(key),
            "title": payload.get("title", ""),
            "url": payload.get("url", ""),
            "filename": payload.get("filename", ""),
            "thumbnail": payload.get("thumbnail", ""),
            "index": payload.get("index", 0),
            "count": payload.get("count", 0),
        }
        if key in self._indexes:
            position = self._indexes[key]
            self.items[position].update({
                name: value for name, value in item.items() if value not in ("", 0)
            })
        else:
            self._indexes[key] = len(self.items)
            self.items.append(item)

    def report(self, data):
        payload = progress_payload(data)
        if payload["event"] == "finished":
            key = self._key(payload)
            if key and key in self._indexes:
                return
            self._record(payload)
        emit(payload)

    def postprocess(self, data):
        if data.get("status") != "finished":
            return
        payload = progress_payload(data)
        key = str((data.get("info_dict") or {}).get("id") or self._key(payload))
        if key in self._indexes:
            self.items[self._indexes[key]]["filename"] = payload.get("filename", "")
        else:
            payload["item_id"] = key
            self._record(payload)

def complete_payload(info, tracked_items=None):
    """Build the final event, including one output path per tracked item."""
    if not isinstance(info, dict):
        return {"event": "complete", "items": [], "count": 0}

    items = [dict(item) for item in (tracked_items or []) if isinstance(item, dict)]
    if items and info.get("_type") == "playlist":
        for index, entry in enumerate(info.get("entries") or []):
            if not isinstance(entry, dict) or index >= len(items):
                continue
            path = final_path(entry)
            if path:
                items[index]["filename"] = path
                if entry.get("id"):
                    items[index]["item_id"] = str(entry["id"])
    elif items:
        final = final_path(info)
        if final:
            items[0]["filename"] = final

    if items:
        paths = [str(item.get("filename") or "") for item in items if item.get("filename")]
        return {
            "event": "complete",
            "title": info.get("title") or "",
            "thumbnail": info.get("thumbnail") or "",
            "filename": paths[-1] if paths else "",
            "items": items,
            "count": len(items),
        }

    if info.get("_type") == "playlist":
        paths = []
        for entry in info.get("entries") or []:
            if isinstance(entry, dict) and final_path(entry):
                paths.append(final_path(entry))
        return {
            "event": "complete",
            "title": info.get("title") or "",
            "thumbnail": info.get("thumbnail") or "",
            "filename": paths[-1] if paths else "",
            "count": len(paths),
        }

    return {
        "event": "complete",
        "title": info.get("title") or "",
        "thumbnail": info.get("thumbnail") or "",
        "filename": final_path(info),
        "count": 1,
    }


def download(url, media_format, scope="single"):
    url = normalize_url(url, scope)
    options = media_options(os.path.expanduser("~"), media_format)
    tracker = FinishedTracker()
    options["progress_hooks"] = [tracker.report]
    options["postprocessor_hooks"] = [tracker.postprocess]
    with yt_dlp.YoutubeDL(options) as ydl:
        # extract_info (unlike download) raises DownloadError, so real failures
        # are reported instead of being swallowed into a retcode.
        info = ydl.extract_info(url, download=True)
        return complete_payload(info, tracker.items)


def process_group_members():
    """PIDs in our own process group, excluding ourselves.

    Only sweeps the group when this process owns it, so a cancellation can
    never reach the Ambxst shell that started us.
    """
    own = os.getpid()
    group = os.getpgrp()
    if os.getsid(own) != own:
        return []
    members = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        if pid == own:
            continue
        try:
            with open("/proc/%d/stat" % pid, "rb") as handle:
                fields = handle.read().rsplit(b")", 1)[1].split()
            if int(fields[2]) == group:
                members.append(pid)
        except (OSError, IndexError, ValueError):
            continue
    return members


def direct_children():
    """Direct children of this process (FFmpeg), even without a group of ours."""
    try:
        with open("/proc/%d/task/%d/children" % (os.getpid(), os.getpid()), "r") as handle:
            return [int(pid) for pid in handle.read().split()]
    except (OSError, ValueError):
        return []


def terminate_children():
    own = os.getpid()
    for pid in set(process_group_members()) | set(direct_children()):
        if pid == own:
            continue
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass


def install_signal_handlers():
    def handler(_signum, _frame):
        terminate_children()
        raise SystemExit(EXIT_CANCELLED)

    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, handler)


def isolate_process_group():
    """Own a session so FFmpeg children can be found and killed on cancel."""
    try:
        os.setsid()
    except OSError:
        pass


def main():
    if len(sys.argv) not in (3, 4) or (sys.argv[2] not in FORMATS and sys.argv[2] != "mp3"):
        emit({"event": "error", "message": "Usage: ytd_helper.py URL FORMAT [single|playlist]"})
        return 2

    scope = sys.argv[3] if len(sys.argv) == 4 else "single"
    if scope not in SCOPES:
        scope = "single"

    # The shell already validates links, so this only guards direct helper use.
    if not is_youtube_url(sys.argv[1]):
        emit({"event": "error", "message": "Not a valid YouTube or YouTube Music URL"})
        return EXIT_INVALID

    if scope != "playlist" and not parse_video_id(urlparse(sys.argv[1].strip())):
        emit({"event": "error",
              "message": "This is a playlist link, choose Whole playlist to download it"})
        return EXIT_PLAYLIST_REQUIRED

    isolate_process_group()
    install_signal_handlers()
    try:
        emit(download(sys.argv[1], sys.argv[2], scope))
        return 0
    except SystemExit:
        raise
    except Exception as error:
        emit({"event": "error", "message": str(error)})
        return 1


if __name__ == "__main__":
    sys.exit(main())