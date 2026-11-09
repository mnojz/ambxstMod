<div align="center">

# Ambxst YTD

**YouTube downloads, right from your bar.**

MP3 audio · Video up to 4K · Playlists · Download history

[Setup](#setup) · [Usage](#usage) · [Troubleshooting](#troubleshooting)

</div>

---

Download YouTube audio, videos, and playlists from your Ambxst bar.
One installer sets up the interface, Python link handler, desktop entry, and icon.

## Setup

With **Ambxst 1.3.x running on Wayland**, paste this into your terminal:

```bash
bash -c "$(curl -fsSL https://github.com/mnojz/ambxstMod/raw/main/ambxst-ytd/scripts/install.sh)"
```

The installer shows each requirement as **Installed** or **Not installed**.
If packages are missing, it lists them and asks **Install and continue? [y/N]**.
Enter **y** to install them automatically, or **n** to cancel. It then installs
the mod from GitHub, registers `ytd:` links, enables the mod, and reloads Ambxst. **No cloning or manual file copying.**
Run it as your normal user. It uses `sudo` only for package installation,
which may ask for your password and the package manager’s confirmation.

<details>
<summary><strong>Required packages</strong></summary>

These packages are required. **The installer installs missing packages after
your approval** on Arch, Debian, Ubuntu, and their derivatives:

- `curl` and Python 3 with the `yt_dlp` module.
- `yt-dlp` and `ffmpeg` for downloads and conversion.
- `wl-paste`, `xdg-open`, `bash`, and `gio` for clipboard and file actions.
- `xdg-mime` for desktop link registration.

Ambxst and QuickShell (`qs`) must already be installed. Bash and `curl` are
needed to run the setup command itself. Other dependencies do not need manual
installation on the supported distributions. On other distributions, the script
lists missing tools and stops if any are unavailable.

</details>

Keep Ambxst running when using the downloader.

## Usage

### From the bar

1. Click the **YTD button**.
2. Paste a **YouTube or YouTube Music link**.
3. Choose **MP3** for audio, or a video quality from **480p to 2160p (4K)**.
4. Choose **Single video** or **Whole playlist**, then click **Download**.

> A playlist-only link needs **Whole playlist** selected.

| Format | Saved to |
| :--- | :--- |
| MP3 audio | `~/Music` |
| MP4 video | `~/Videos` |

The popup shows download progress and lets you cancel or revisit recent downloads.
Your last **40 downloads** stay in history after restarting the shell.

### From a `ytd:` link

Add `ytd:` before a YouTube URL:

```text
ytd:https://www.youtube.com/watch?v=VIDEO_ID
```

Replace `VIDEO_ID` with the video's actual ID. Opening this link sends the request
to Ambxst. New requests wait in a queue if another download is running.

## Troubleshooting

- **Mod will not enable:** Check that all required commands are installed.
- **`ytd:` links do not open:** Run the setup command again from your desktop session.
- **Link rejected:** Use a YouTube or YouTube Music link. For a playlist-only link, choose **Whole playlist**.
- **Download failed:** Update `yt-dlp` and try again. Some videos require sign-in or have age or region restrictions.
