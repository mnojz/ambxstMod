<div align="center">

# Parcel

**Find, install, and manage Arch packages in one compact window.**

Official repositories · AUR · Built-in authentication · Live activity

</div>

---

## Install

Requires Ambxst **1.3.x**, Python 3, pacman, and sudo.

```bash
ambxst mods install https://github.com/mnojz/ambxstMod/tree/main/parcel
ambxst mods enable mnojz.parcel
ambxst reload
```

Open it with:

```bash
ambxst run parcel
```

Assign that command to your preferred desktop shortcut.

## Use

- Type to search repositories and the AUR. An empty search shows explicitly installed packages.
- Filter with **All**, **Updates**, or **AUR**. Select a package and use the action hints in the footer.
- Press **Enter** to install or reinstall, **Ctrl+D** to remove, and **Ctrl+I** for details.
- Repository labels and installed-package metadata load with the list; details use the cache while refreshing.
- Use the refresh and upgrade icons, or **Ctrl+R** and **Ctrl+U**.
- Actions start immediately. Enter your password in the main activity area when requested. Package tools use `--noconfirm` to accept their default options.

No external terminal opens. The activity area shows progress and an expandable log.
The footer follows preparation, downloads, package changes, builds, and cleanup.
It shows completed/total package counts when available; unmeasured stages use a
moving loading indicator. Per-file download percentages stay in the log. **Stop** asks for confirmation in the main window. During package changes, cancellation waits for a safe point.

Closing the window hides the UI while an active transaction continues. Reopen
Parcel to answer a pending prompt or check progress. Passwords are not saved or
included in the activity log. If authentication is needed while Parcel is hidden
or unfocused, an Ambxst notification lets you reopen it. Alerts follow your normal
notification settings.

## AUR helpers

Parcel detects **paru** and **yay** automatically. If both are installed, choose
one in the header; your choice is remembered. You can also select **Automatic**
in **Settings → Mods → Parcel → AUR helper**.

If neither is installed, choose the **paru** or **yay** helper chip in the launcher.
Parcel installs the required build tools, downloads the helper's AUR build files,
automatically accepts build review, and builds and installs the helper as your normal user.
Authentication stays inside the main launcher layout.

Official repository packages remain available without an AUR helper.

The compact window uses 40px package rows and Inter, Noto Sans, or system sans.
Its log drawer starts collapsed. Open it with **Ctrl+L** or **Log**.
Log lines keep their original layout in a wide, horizontally scrollable area.
Use a trackpad or **Shift + mouse wheel** to scroll sideways.

## Keyboard shortcuts

| Key | Action |
| :--- | :--- |
| ↑ / ↓ | Select a package |
| Enter | Install selected package |
| Ctrl+D | Remove selected package |
| Ctrl+U | Upgrade all packages |
| Ctrl+R | Refresh packages |
| Ctrl+I | Toggle selected package details |
| Ctrl+L | Toggle log drawer |
| Escape | Close the log drawer first, then hide Parcel |

## Troubleshooting

- **An operation is waiting:** Enter your password or answer its response prompt. For numbered choices, enter the requested numbers. A blank response accepts the tool's default.
- **AUR build fails:** Open **Log** for the build error. Package-specific build failures still need to be resolved.
- **Another package manager is running:** Let its transaction finish, then retry. Parcel does not remove pacman's lock file.
- **Authentication fails:** Check your password and your account's sudo permissions.
