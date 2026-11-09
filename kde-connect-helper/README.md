<div align="center">

# KDE Connect Helper

**Your phone, a click away from your Ambxst bar.**

Device status · Battery level · Quick actions · File sharing

[Install](#install) · [Connect your device](#connect-your-device) · [Quick actions](#quick-actions)

</div>

---

Check your paired devices, see their battery level, and send files without leaving
your desktop. Works with horizontal and vertical Ambxst bars.

## Install

Requires **Ambxst 1.3.8–1.3.x** and **Python 3**.

Paste these commands into your terminal:

```bash
ambxst mods install https://github.com/mnojz/ambxstMod/tree/main/kde-connect-helper
ambxst mods enable mnojz.kde-connect-helper
ambxst reload
```

The helper button will appear in your bar.

<details>
<summary><strong>Prefer installing through Settings?</strong></summary>

Open **Settings → Mods** and install from this URL:

```text
https://github.com/mnojz/ambxstMod/tree/main/kde-connect-helper
```

Enable **KDE Connect helper**, then reload Ambxst.

</details>

### Set up KDE Connect

The mod is an interface for KDE Connect, so KDE Connect must also be installed
on your computer and phone.

If it is missing on your computer, click the helper button for installation options:

- **Arch / Fedora and derivatives:** Guided installation is available when the
  package manager and administrator authentication tool (`pkexec`) are detected.
  Review and confirm before installation starts.
- **NixOS:** Follow the configuration instructions shown in the popup.
- **Other distributions:** Install KDE Connect using your distribution's package manager.

> Installing the mod does not automatically install KDE Connect. The popup guides
> you through the next step.

## Connect your device

1. Open **KDE Connect** on your phone and computer.
2. Connect both devices to the **same network**.
3. Request pairing and accept it on the other device.
4. Click the helper button in Ambxst to see your paired devices.

If the desktop service is stopped, use **Start KDE Connect** in the popup.
Select a device from the list when you have more than one paired.

## Quick actions

| Action | What it does |
| :--- | :--- |
| **Ping** | Sends a notification to your device |
| **Ring** | Makes your device ring so you can find it |
| **Send files** | Opens a file picker, then asks you to confirm before sending |
| **Browse files** | Opens remote files in your file manager when supported |

Battery and connection details appear when available. Actions are enabled only
when the selected device is connected and supports them.

## Settings

Open the mod's settings in **Settings → Mods**:

| Setting | Description |
| :--- | :--- |
| **Preferred device** | Choose a device in the popup to remember it, or use `auto` |
| **Polling interval** | Time between status checks: **5–300 seconds**, default **15** |

The interface follows Ambxst's language, with English, Russian, and Spanish translations.

## Troubleshooting

- **No paired devices:** Open KDE Connect and finish pairing first.
- **Device offline:** Check that both devices are on the same network and KDE Connect is running.
- **Status not loading:** Make sure `qdbus6` or `qdbus` is installed on your computer.
- **File picker unavailable:** Check that your desktop portal is running and Python's D-Bus and GLib bindings are installed.
- **Action disabled:** The device may be offline or its KDE Connect plugin may be disabled.
