pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Battery levels of the currently connected Bluetooth devices.
//
// Separate from BluetoothService on purpose. That one drives the Bluetooth panel
// and only polls while the panel is open — fine for a panel, useless for a bar
// indicator, which has to be right whenever the bar is on screen. So this keeps
// its own small always-on poll rather than widening BluetoothService's, which
// would make the panel's own refresh rate a compromise between two jobs.
//
// One shell-out per tick, not one per device: the whole listing and every
// device's info come back from a single bash invocation as tab-separated lines,
// so the cost does not grow with how many devices are connected.
Singleton {
    id: root

    // Connected devices as plain JS objects, lowest battery first. Devices that
    // report no level sort last and carry battery -1.
    property var devices: []

    // The subset that actually reports a level — what the bar can summarise.
    readonly property var withBattery: devices.filter(d => d.batteryAvailable)

    // The device the bar shows: whichever connected one has least charge left.
    readonly property var lowest: withBattery.length > 0 ? withBattery[0] : null

    // The indicator's whole content is a battery reading, so it has nothing to
    // say about connected devices that don't report one.
    readonly property bool available: withBattery.length > 0

    // Battery percentages move slowly, so this is deliberately unhurried; a
    // connect or disconnect made from the shell refreshes immediately below, and
    // this is the backstop for devices that come and go on their own.
    readonly property int pollInterval: 20000

    property Timer pollTimer: Timer {
        interval: root.pollInterval
        running: !SuspendManager.isSuspending
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // A device connecting or disconnecting through the panel moves this, so the
    // readout follows the action instead of waiting out the poll.
    property var serviceConnections: Connections {
        target: BluetoothService
        function onConnectedDevicesChanged() {
            root.refresh();
        }
    }

    property var suspendConnections: Connections {
        target: SuspendManager
        function onPreparingForSleep() {
            if (pollProcess.running)
                pollProcess.running = false;
        }
        function onWakingUp() {
            wakeTimer.restart();
        }
    }

    property Timer wakeTimer: Timer {
        interval: 4000
        repeat: false
        onTriggered: root.refresh()
    }

    function refresh(): void {
        if (SuspendManager.isSuspending || pollProcess.running)
            return;
        pollProcess.running = true;
    }

    // Emits, per connected device, a "===DEV <address>" marker followed by that
    // device's raw `bluetoothctl info` block. Kept to a single line on purpose:
    // this string is a QML string literal, and a shell line-continuation inside
    // one is consumed by the JS parser rather than the shell, which silently
    // welds `done` onto the previous command.
    //
    // `bluetoothctl devices` colours paired and connected entries, so the SGR
    // escapes have to come off before the address can be read; `info` is not
    // coloured. Connected is re-read from `info` rather than trusted from the
    // listing, so a device that drops between the two calls is not reported.
    readonly property string pollCommand: 'for addr in $(bluetoothctl devices Connected 2>/dev/null | sed \'s/\x1b\\[[0-9;]*[A-Za-z]//g\' | awk \'/^Device /{print $2}\'); do echo "===DEV $addr"; bluetoothctl info "$addr" 2>/dev/null; done'

    property Process pollProcess: Process {
        command: ["bash", "-c", root.pollCommand]
        running: false
        // bluetoothctl localises its field names; the parse keys off the English ones.
        environment: ({
            LANG: "C.UTF-8",
            LC_ALL: "C.UTF-8"
        })

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const out = [];
                let current = null;

                const flush = () => {
                    // Only devices `info` still reports as connected, and only
                    // once they have an address to be keyed on.
                    if (current && current.connected && current.address.length > 0) {
                        delete current.connected;
                        out.push(current);
                    }
                };

                const lines = text.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i].trim();

                    if (line.startsWith("===DEV ")) {
                        flush();
                        current = {
                            address: line.slice(7).trim(),
                            name: "",
                            icon: "bluetooth",
                            batteryAvailable: false,
                            battery: -1,
                            connected: false
                        };
                        continue;
                    }
                    if (!current)
                        continue;

                    if (line.startsWith("Name:")) {
                        current.name = line.slice(5).trim();
                    } else if (line.startsWith("Icon:")) {
                        current.icon = line.slice(5).trim() || "bluetooth";
                    } else if (line.startsWith("Connected:")) {
                        current.connected = line.includes("yes");
                    } else if (line.startsWith("Battery Percentage:")) {
                        // "Battery Percentage: 0x3f (63)" — the decimal in
                        // brackets is the percentage.
                        const match = line.match(/\((\d+)\)/);
                        if (match) {
                            current.battery = parseInt(match[1]);
                            current.batteryAvailable = current.battery >= 0;
                        }
                    }
                }
                flush();

                for (let i = 0; i < out.length; i++) {
                    if (out[i].name.length === 0)
                        out[i].name = out[i].address;
                }

                out.sort((a, b) => {
                    if (a.batteryAvailable !== b.batteryAvailable)
                        return a.batteryAvailable ? -1 : 1;
                    if (a.batteryAvailable && a.battery !== b.battery)
                        return a.battery - b.battery;
                    return a.name.localeCompare(b.name);
                });

                // Assigned unconditionally, empty included: that is how the
                // indicator learns the last device went away and hides itself.
                root.devices = out;
            }
        }
    }
}
