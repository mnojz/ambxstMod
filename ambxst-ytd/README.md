# Ambxst YTD

An Ambxst bar mod that downloads YouTube audio or video with `yt-dlp` and
`ffmpeg`. It provides a popup, live progress, cancellation, a bounded
request queue, persistent history, and browser `ytd:` links.

## Requirements

- Ambxst `>=1.3.0 <1.4.0`
- Python 3 with the `yt_dlp` module
- `yt-dlp`, `ffmpeg`, `wl-paste`, `xdg-open`, and QuickShell (`qs`)
- A Wayland Ambxst session

The mod manifest is the authoritative dependency declaration. Ambxst refuses
composition when a declared command is unavailable.

### No mod dependencies

The mod depends on no other mod and works on a stock Ambxst tree.

The bar glyph used to be colourised through the shell's shared `Tinted`
component in its `monochrome` mode, which is not part of Ambxst itself: it only
existed in `drpezzer.tinted-icons`. That mod has been archived into
`drpezzer.roadie`, which declares a conflict with the old id, so it can no
longer be installed alongside this one. Since `monochrome` mode is a colourising
pass over the icon's own luminance, the mod now carries that pass itself in
`YtdIcon` and applies it to this one glyph. Icons elsewhere on the shell are
untouched, and enabling or disabling this mod no longer depends on anyone else.

## Install the mod

```bash
ambxst mods install https://github.com/mnojz/ambxst-ytd
ambxst mods enable mnojz.ambxstytd
ambxst reload
```

New installs are disabled by default, so keep the explicit `enable` step.
Removing an already-disabled mod may report that it was removed; the subsequent
install and enable are still required for a clean refresh.

## Browser integration

Install or refresh the desktop protocol handler from the repository root:

```bash
./scripts/install-desktop.sh
```

The script installs:

- `~/.local/bin/ytd.py`
- `~/.local/share/applications/ytd-handler.desktop`
- `~/.local/share/icons/ytd.svg`

It refreshes the desktop database and registers `ytd-handler.desktop` for
`x-scheme-handler/ytd` when `xdg-mime` is available.

Invalid or non-YouTube links are refused by the bridge before Ambxst is
contacted, and the desktop reports the reason.

## Downloads

- Only YouTube and YouTube Music links are accepted. `watch`, `youtu.be`,
  `/shorts/`, `/live/`, `/embed/`, and `/playlist` URLs are supported; anything
  else is reported as an invalid URL before any download starts.
- The **Single video** / **Whole playlist** selector sits next to the format
  selector. Single drops the `list` parameter so a shared link downloads just
  the current video; Whole playlist keeps it.
- A playlist-only link (`/playlist?list=...`) is rejected in Single mode
  because it names no single video; switch to Whole playlist to download it.
- Audio is saved as MP3 under `~/Music`.
- Video is saved as MP4 under `~/Videos`.
- Playlist items are recorded separately after their final output path exists.
- History is persisted by Ambxst under `community.ambxstytd.history`, capped at
  40 entries, and restored on shell startup.
- Browser requests open the popup and are queued behind an active download.
- Cancelling terminates the helper and its FFmpeg process group.

YouTube extraction can still fail because of authentication, age/location
restrictions, client throttling, or upstream site changes.

## Validate

Run the repository checks:

```bash
./scripts/validate.sh
```

The validator checks Python syntax and unit tests, the Ambxst patch against the
local source checkout, manifest structure, and—when an installed active
generation is available—the generated QuickShell shell. A healthy foreground
smoke test reaches `Configuration Loaded` and is stopped by `timeout`, so exit
status `124` is expected in that mode.
