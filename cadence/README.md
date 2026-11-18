<div align="center">

# Ambxst Cadence

**Smoother shell transitions and everyday controls on the bar.**

[Install](#install) · [Usage](#usage) · [Settings](#settings)

</div>

Cadence stages Ambxst’s startup, reload, and fullscreen transitions. It adds
Wi-Fi and Bluetooth controls to the bar, themed farewells for power off and
reboot, and desktop notifications for mod updates.

## Install

Requires **Ambxst 1.3.15 or later in the 1.x series**. From the root of this
repository, run:

```bash
ambxst mods install ./cadence
ambxst mods enable mnojz.cadence
ambxst reload
```

If you’re upgrading from Roadie, disable `drpezzer.roadie` before enabling
Cadence. Cadence carries over your saved Settings window dimensions.

## Usage

- **Reload.** Run `ambxst run reload` to animate out before Ambxst restarts.
  A separate helper covers the gap during abrupt restarts.
- **Wi-Fi.** Click the network icon to scan, connect, view connection details,
  or manage saved profiles and VPNs. Right-click to open Network Connections.
- **Bluetooth.** Click the Bluetooth icon to manage devices. Click the battery
  gauge to see charge levels for connected devices.
- **Power.** Choose Power Off or Reboot from the notch. The farewell plays as
  the system starts shutting down or restarting.
- **Mod updates.** Enable **Scheduled checks** in **Settings → Mods** to get
  desktop notifications when Ambxst finds updates in the background.

To preview a farewell without running a power command:

```bash
qs ipc --pid "$(cat "$XDG_RUNTIME_DIR/ambxst-qs.pid")" call cadence farewellPreview shutdown
```

Use `reboot` in place of `shutdown` for the restart preview.

## Settings

Open **Settings → Mods → Ambxst Cadence → Settings** to adjust the floating
Settings window’s width and height as percentages of the display. Changes
apply the next time the window opens.

## Credits

Maintained by [mnojz](https://github.com/mnojz). Based on the MIT-licensed
[Ambxst Roadie](https://github.com/drpezzer/ambxst-mods) by drpezzer.
