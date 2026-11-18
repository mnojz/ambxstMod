pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Singleton {
    id: root

    // BlueZ names a device it has no name for after its own address, so a scan
    // fills up with beacons and randomised-MAC phones. Blueman hides these by
    // default (org.blueman.general hide-unnamed) and the list is unusable without
    // it — but only ever hide them from the discovered half, never from devices
    // already paired.
    function isUnnamed(device): bool {
        if (!device)
            return true;
        const name = (device.name ?? "").replace(/-/g, ":").toUpperCase();
        const address = (device.address ?? "").toUpperCase();
        return name === "" || name === "UNKNOWN" || name === address;
    }

    readonly property var knownDevices: BluetoothService.friendlyDeviceList.filter(d => d && (d.paired || d.connected))
    readonly property var newDevices: BluetoothService.friendlyDeviceList.filter(d => d && !d.paired && !d.connected && !root.isUnnamed(d))

    property bool panelOpen: false

    function setPanelOpen(open: bool): void {
        root.panelOpen = open;
        if (!open) {
            BluetoothService.stopDiscovery();
            return;
        }

        BluetoothService.initialize();
        if (BluetoothService.enabled) {
            BluetoothService.updateDevices();
            BluetoothService.startDiscovery();
        }
    }

    function setEnabled(value: bool): void {
        BluetoothService.setEnabled(value);
        if (value)
            powerOnKick.restart();
        else
            BluetoothService.stopDiscovery();
    }

    // bluetoothctl takes a moment to reflect a connect/disconnect.
    function refreshSoon(): void {
        refreshSoonTimer.restart();
    }

    // The adapter needs a moment after `power on` before it will accept a scan.
    Timer {
        id: powerOnKick
        interval: 700
        onTriggered: {
            if (BluetoothService.enabled && root.panelOpen) {
                BluetoothService.updateDevices();
                BluetoothService.startDiscovery();
            }
        }
    }

    Timer {
        id: refreshSoonTimer
        interval: 800
        onTriggered: BluetoothService.updateDevices()
    }

    // A scan window is time-boxed, so reopen one as soon as it lapses rather than
    // polling on a fixed interval, which would leave the adapter idle for the
    // remainder of each tick. setPanelOpen() clears the open flag before it stops
    // discovery, so a deliberate close can't retrigger this.
    Connections {
        target: BluetoothService

        function onDiscoveringChanged(): void {
            if (!BluetoothService.discovering && root.panelOpen && BluetoothService.enabled)
                rescanDelay.restart();
        }
    }

    Timer {
        id: rescanDelay
        interval: 400
        onTriggered: {
            if (root.panelOpen && BluetoothService.enabled)
                BluetoothService.startDiscovery();
        }
    }

    // Safety net. openPanel() can land before the adapter's powered state has been
    // read back, and startDiscovery() silently no-ops while `enabled` is still
    // false — after which nothing retries, because the restart above only fires
    // when a scan *stops*, and none ever started. Opening the panel shortly after
    // login therefore left it scanning forever with an empty list. `running` is
    // bound to `enabled`, so this arms itself the moment the adapter is known.
    Timer {
        id: ensureScanning
        interval: 2000
        repeat: true
        running: root.panelOpen && BluetoothService.enabled
        onTriggered: {
            if (!BluetoothService.discovering)
                BluetoothService.startDiscovery();
        }
    }

    // The service only polls the device list for the dashboard/launcher/overview,
    // so the panel drives its own refresh while open.
    Timer {
        id: refreshTimer
        interval: 3000
        repeat: true
        running: root.panelOpen && BluetoothService.enabled
        onTriggered: BluetoothService.updateDevices()
    }
}
