pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.components
import qs.modules.services
import qs.modules.theme
import qs.config

// Content shared by the attached and floating BarPopout hosts.
Flickable {
    id: root

    required property real maxContentHeight
    implicitWidth: 284
    implicitHeight: Math.min(contentColumn.implicitHeight, maxContentHeight)
    clip: true
    contentWidth: width
    contentHeight: contentColumn.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    ColumnLayout {
        id: contentColumn
        width: parent.width
        spacing: 6

        BarRadioHeader {
            title: "Bluetooth"
            glyph: BluetoothService.enabled ? Icons.bluetooth : Icons.bluetoothOff
            checked: BluetoothService.enabled
            subtitle: {
                if (!checked)
                    return "Off";
                if (BluetoothService.connectedDevices > 0)
                    return `${BluetoothService.connectedDevices} connected`;
                return BluetoothService.discovering ? "Scanning…" : "On";
            }
            onToggled: enabled => BluetoothControl.setEnabled(enabled)
        }

        // ---- Paired / connected ----
        Text {
            Layout.fillWidth: true
            Layout.topMargin: 2
            visible: BluetoothService.enabled && BluetoothControl.knownDevices.length > 0
            text: "My devices"
            font.family: Styling.defaultFont
            font.pixelSize: Styling.fontSize(-3)
            font.bold: true
            color: Colors.overSurfaceVariant
        }

        Repeater {
            model: BluetoothService.enabled ? BluetoothControl.knownDevices : []

            delegate: BluetoothDeviceRow {
                required property var modelData

                Layout.fillWidth: true
                device: modelData
                onActionTaken: BluetoothControl.refreshSoon()
            }
        }

        // ---- Discovered ----
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            visible: BluetoothService.enabled && (BluetoothControl.newDevices.length > 0 || BluetoothService.discovering)
            Layout.leftMargin: BluetoothControl.newDevices.length === 0 ? 4 : 0
            Layout.bottomMargin: BluetoothControl.newDevices.length === 0 ? 6 : 0
            spacing: 6

            Text {
                text: "Available"
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(-3)
                font.bold: true
                color: Colors.overSurfaceVariant
            }

            Text {
                id: scanSpinner
                visible: BluetoothService.discovering
                text: Icons.circleNotch
                font.family: Icons.font
                font.pixelSize: 11
                color: Colors.overSurfaceVariant

                RotationAnimator on rotation {
                    running: scanSpinner.visible
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 900
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }

        Repeater {
            model: BluetoothService.enabled ? BluetoothControl.newDevices : []

            delegate: BluetoothDeviceRow {
                required property var modelData

                Layout.fillWidth: true
                device: modelData
                onActionTaken: BluetoothControl.refreshSoon()
            }
        }

        // ---- Empty states ----
        Text {
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.bottomMargin: 6
            horizontalAlignment: Text.AlignHCenter
            visible: !BluetoothService.enabled || (BluetoothControl.knownDevices.length === 0 && BluetoothControl.newDevices.length === 0)
            text: BluetoothService.enabled ? "Searching for devices…" : "Bluetooth is off"
            font.family: Styling.defaultFont
            font.pixelSize: Styling.fontSize(-2)
            color: Colors.overSurfaceVariant
        }
    }
}
