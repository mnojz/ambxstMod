<div align="center">

# pacDeck

**Find, install, and manage Arch packages in one compact window.**

Official repositories · AUR · Built-in authentication · Live activity

</div>

---

## Install

Requires Ambxst **1.3.x**, Python 3, pacman, and sudo.

```bash
ambxst mods install https://github.com/mnojz/ambxstMod/tree/main/pacDeck
ambxst mods enable mnojz.pacdeck
ambxst reload
```

Open it with:

```bash
ambxst run pacDeck
```

Assign that command to your preferred desktop shortcut.

## Use

- Type to search repositories and the AUR. An empty search shows explicitly installed packages.
- Select a package and choose **Install**, **Reinstall**, or **Remove**.
- Open **Details** for package metadata, or choose **Upgrade all** for a system upgrade.
- Review the transaction confirmation, then enter your password inside pacDeck when requested. Package tools use `--noconfirm` to accept their default options.

No external terminal opens. The activity area shows progress and an expandable log.
Downloads show reported percentages; builds and other unmeasured stages use an
activity indicator. The dashed progress indicator keeps moving while work is active. **Stop** asks
for confirmation; during package changes, the stop request waits for a safe point.

Closing the window hides the UI while an active transaction continues. Reopen
pacDeck to answer a pending prompt or check progress. Passwords are not saved or
included in the activity log.

## AUR helpers

pacDeck detects **paru** and **yay** automatically. If both are installed, choose
one in the header; your choice is remembered. You can also select **Automatic**
in **Settings → Mods → pacDeck → AUR helper**.

If neither is installed, choose **Install paru** or **Install yay** in the launcher.
pacDeck installs the required build tools, downloads the helper's AUR build files,
asks you to review them, and builds and installs the helper as your normal user.
Authentication and confirmations stay inside the launcher.

Official repository packages remain available without an AUR helper.

Details and activity logs use space from the package list instead of expanding
the window.

## Keyboard shortcuts

| Key | Action |
| :--- | :--- |
| ↑ / ↓ | Select a package |
| Enter | Review installation |
| Ctrl+D | Review removal |
| Ctrl+U | Review system upgrade |
| Escape | Dismiss the current dialog or hide pacDeck |

## Troubleshooting

- **An operation is waiting:** Check its confirmation or response prompt. For numbered choices, enter the requested numbers. A blank response accepts the tool's default.
- **AUR build fails:** Open **Activity log** for the build error. Package-specific build failures still need to be resolved.
- **Another package manager is running:** Let its transaction finish, then retry. pacDeck does not remove pacman's lock file.
- **Authentication fails:** Check your password and your account's sudo permissions.
