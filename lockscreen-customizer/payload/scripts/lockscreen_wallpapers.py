"""Maintain the lock screen's local wallpaper library."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
from tempfile import NamedTemporaryFile
from urllib.parse import unquote, urlsplit

IMAGES = {".jpg", ".jpeg", ".png", ".webp", ".tif", ".tiff", ".bmp", ".avif", ".heif"}
VIDEOS = {".gif", ".mp4", ".webm", ".mov", ".avi", ".mkv", ".m4v"}


def import_file(source, library):
    if source.suffix.lower() not in IMAGES | VIDEOS or not source.is_file():
        return None

    target = library / source.name
    if source.resolve() == target.resolve():
        return target.as_uri()

    with NamedTemporaryFile(dir=library, prefix=".import-") as temporary:
        shutil.copyfile(source, temporary.name)
        for index in range(10000):
            name = source.name if index == 0 else f"{source.stem}-{index}{source.suffix}"
            target = library / name
            try:
                target.hardlink_to(temporary.name)
                return target.as_uri()
            except FileExistsError:
                if target.samefile(source):
                    return target.as_uri()
    raise OSError(f"Could not find an available name for {source.name}")


def wallpaper_paths(root):
    visited = set()
    for folder, directories, files in os.walk(root, followlinks=True):
        directory = Path(folder)
        try:
            stat = directory.stat()
        except OSError:
            directories.clear()
            continue

        identity = (stat.st_dev, stat.st_ino)
        if identity in visited:
            directories.clear()
            continue

        visited.add(identity)
        directories[:] = sorted(name for name in directories if not name.startswith("."))
        for name in sorted(files, key=str.casefold):
            path = directory / name
            if not name.startswith(".") and path.suffix.lower() in IMAGES | VIDEOS and path.is_file():
                yield path


def video_thumbnail(path, library, relative, generate, width=360):
    revision = f"{relative}:{path.stat().st_mtime_ns}"
    if width != 360:
        revision = f"{width}:{revision}"
    key = hashlib.sha256(revision.encode()).hexdigest()
    frame = library / ".thumbnails" / f"{key}.jpg"
    if not frame.is_file() and generate and shutil.which("ffmpeg"):
        frame.parent.mkdir(exist_ok=True)
        with NamedTemporaryFile(dir=frame.parent, suffix=".jpg") as temporary:
            try:
                result = subprocess.run(
                    ["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(path),
                     "-frames:v", "1", "-vf", f"scale={width}:-2", temporary.name],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    timeout=5, check=False,
                )
                if result.returncode == 0 and Path(temporary.name).stat().st_size:
                    try:
                        frame.hardlink_to(temporary.name)
                    except FileExistsError:
                        pass
            except subprocess.TimeoutExpired:
                pass
    return frame.as_uri() if frame.is_file() else ""


def list_wallpapers(library, desktop, desktop_thumbnails, imported):
    entries = []
    seen = set()
    sources = [(library, None)]
    if desktop is not None:
        sources.append((desktop.absolute(), desktop_thumbnails))
    for root, thumbnails in sources:
        if root in seen:
            continue
        for path in wallpaper_paths(root):
            try:
                resolved = path.resolve(strict=True)
                if resolved in seen:
                    continue
                seen.add(resolved)
                relative = path.relative_to(root)
                url = path.as_uri()
                suffix = path.suffix.lower()
                video = suffix in VIDEOS
                thumbnail = url if not video or suffix == ".gif" else ""
                cached = thumbnails / (str(relative) + ".jpg") if thumbnails else None
                if cached is not None and cached.is_file():
                    thumbnail = cached.as_uri()
                elif not thumbnail and root == library:
                    thumbnail = video_thumbnail(path, library, relative, url in imported)
                entries.append({"name": path.name, "url": url, "thumbnail": thumbnail, "video": video})
            except (OSError, RuntimeError):
                continue
    return entries


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("library", type=Path)
    parser.add_argument("samples", type=Path)
    parser.add_argument("--preview-url")
    parser.add_argument("--desktop", type=Path)
    parser.add_argument("--desktop-thumbnails", type=Path)
    parser.add_argument("files", nargs="*")
    args = parser.parse_args()

    library = args.library.absolute()
    library.mkdir(parents=True, exist_ok=True)
    if args.preview_url:
        thumbnail = ""
        parts = urlsplit(args.preview_url)
        if parts.scheme == "file" and not parts.netloc:
            source = Path(unquote(parts.path))
            if source.is_file() and source.suffix.lower() in VIDEOS:
                thumbnail = video_thumbnail(source, library, source.resolve(), True, width=1280)
        print(json.dumps({"url": args.preview_url, "thumbnail": thumbnail}))
        return

    seed_marker = library / ".samples-installed"
    if not seed_marker.exists():
        for sample in sorted(args.samples.glob("ambxst-0[123].png")):
            destination = library / sample.name
            try:
                with destination.open("xb") as output, sample.open("rb") as source:
                    shutil.copyfileobj(source, output)
            except FileExistsError:
                pass
        seed_marker.touch()

    imported = []
    errors = []
    for url in args.files:
        try:
            parts = urlsplit(url)
            result = import_file(Path(unquote(parts.path)), library) if parts.scheme == "file" and not parts.netloc else None
            if result:
                imported.append(result)
            else:
                errors.append("Unsupported or unavailable wallpaper.")
        except (OSError, ValueError) as error:
            errors.append(str(error))
    entries = list_wallpapers(library, args.desktop, args.desktop_thumbnails, set(imported))
    print(json.dumps({"entries": entries, "imported": imported, "errors": errors}))


if __name__ == "__main__":
    main()
