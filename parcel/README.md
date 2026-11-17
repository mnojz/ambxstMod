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
- Colored repository badges mark installed packages; gray badges mark packages you have not installed.
- Filter with **All**, **Updates**, or **AUR**, then use the icon actions at the bottom right. Hover an icon for its action and keyboard shortcut.
- Press **Enter** to install or reinstall, **Ctrl+D** to remove, and **Ctrl+I** for details.
- Repository labels and installed-package metadata load with the list; details use the cache while refreshing.
- Choose **Sync all** to synchronize repositories and upgrade repository/AUR packages (**Ctrl+U**). The package list refreshes automatically.
- Actions start immediately. Enter your password in the main activity area when requested. Package tools use `--noconfirm` to accept their default options.

No external terminal opens. The activity area shows progress and an expandable log.
The footer shows four steps: retrieving info, downloading dependencies, installing,
and finalizing. A single package uses a percentage; multiple packages use completed/total
counts for the current download or installation batch. Retrieving info, finalizing, and
unmeasured AUR builds use a loading animation. **Stop** asks for confirmation in the
main window. During package changes, cancellation waits for a safe point.

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
Opening logs or details reduces the package list to two rows, giving the drawer more room.
Package details show a readable facts grid, expandable dependencies, and the project website.
The activity drawer groups package operations into readable steps, combines repeated
progress updates, and highlights warnings and errors with your shell palette.
Repository downloads update one progress bar per repository. Dependencies use a
single completed/total bar for each download or installation batch. Already installed
dependencies show a full bar. Each operation starts with its package name and ends
with **Installed** (green), **Removed** (red), or **Updated** (blue) after confirmed
success. Each operation uses matching messages and icons; routine confirmation chatter is hidden.
Build output stays in one updating entry, including source preparation, compilation,
and packaging. Warnings and errors remain visible. Choose **Raw** for the original output; long raw lines
scroll horizontally with a trackpad or **Shift + mouse wheel**.
The trash icon clears both log views without stopping an active operation.
Automatic following pauses when you scroll back. Logs prefer JetBrains Mono Nerd Font,
then another installed Nerd Font. Log icons use glyphs from that same font.

## Keyboard shortcuts

| Key | Action |
| :--- | :--- |
| ↑ / ↓ | Select a package |
| Enter | Install selected package |
| Ctrl+D | Remove selected package |
| Ctrl+U | Sync all packages |
| Ctrl+I | Toggle selected package details |
| Ctrl+L | Toggle log drawer |
| Escape | Close the log drawer first, then hide Parcel |

## Troubleshooting

- **An operation is waiting:** Enter your password or answer its response prompt. For numbered choices, enter the requested numbers. A blank response accepts the tool's default.
- **AUR build fails:** Open **Log** for the build error. Package-specific build failures still need to be resolved.
- **Another package manager is running:** Let its transaction finish, then retry. Parcel does not remove pacman's lock file.
- **Authentication fails:** Check your password and your account's sudo permissions.
