<div align="center">

# Rubber Band Selection Overlay

**A selection rectangle for your Ambxst desktop.**

Wayland overlay · Per-screen surfaces · Custom colors · Rounded corners

[Install](#install) · [Usage](#usage) · [Appearance](#appearance)

</div>

---

Display a customizable rectangle while selecting an area of your desktop.
Use it with a script or compositor binding for workflows such as choosing where
to open a terminal.

> This mod draws the selection. Your external script or binding must track the
> pointer, send selection updates, and launch or position the window.

## Install

Requires **Ambxst 1.3.x or later, below 2.0**, running on Wayland with QuickShell.

Paste these commands into your terminal:

```bash
ambxst mods install https://github.com/mnojz/ambxstMod/tree/main/rubberBandSelectionOverlay
ambxst mods enable mnojz.dragoverlay
ambxst reload
```

<details>
<summary><strong>Prefer installing through Settings?</strong></summary>

Open **Settings → Mods** and install from this URL:

```text
https://github.com/mnojz/ambxstMod/tree/main/rubberBandSelectionOverlay
```

Enable **Rubber Band Selection Overlay**, then reload Ambxst.

</details>

## Usage

The overlay stays hidden until your script sends commands to QuickShell's
`dragOverlay` IPC target:

| Command | What it does |
| :--- | :--- |
| `start(x, y)` | Sets the starting point and shows the overlay |
| `update(x, y)` | Resizes the rectangle toward the current pointer position |
| `stop()` | Hides the overlay |

Send `start` when selection begins, repeated `update` calls as the pointer moves,
and `stop` when selection ends. Dragging in any direction is supported.

<details>
<summary><strong>Try a selection manually</strong></summary>

Replace `12345` with the process ID of your running Ambxst QuickShell instance.
Run these commands in the same terminal:

```bash
AMBXST_PID=12345
qs ipc --pid "$AMBXST_PID" call dragOverlay start 100 100
qs ipc --pid "$AMBXST_PID" call dragOverlay update 500 350
```

Hide the rectangle when finished:

```bash
qs ipc --pid "$AMBXST_PID" call dragOverlay stop
```

Coordinates are in the overlay's screen space. The current implementation draws
40 pixels above the supplied vertical coordinates and has no screen argument
for routing commands to an individual monitor.

</details>

## Appearance

Open the mod's settings in **Settings → Mods**. Changes apply immediately.

| Setting | Default | Options |
| :--- | :--- | :--- |
| **Selection fill color** | `#445b93d3` | ARGB hex color |
| **Selection border color** | `#adaac7fc` | ARGB hex color |
| **Selection border width** | `2` px | `0–20` px |
| **Selection corner radius** | `8` px | `0–100` px |

Colors use `#AARRGGBB`: the first two digits control opacity. Use `00` for fully
transparent or `FF` for fully opaque.

## Troubleshooting

- **Nothing appears after installation:** The overlay needs an external script or IPC commands to activate it. Installing it does not add a mouse binding.
- **Commands do not reach Ambxst:** Check that the mod is enabled, Ambxst has been reloaded, and the process ID points to the correct QuickShell instance.
- **Rectangle stays visible:** Send the `stop` command. Your selection script should also send it when cancelled.
