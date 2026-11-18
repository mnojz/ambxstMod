pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.services
import qs.modules.components
import qs.modules.theme
import qs.config

Item {
    id: root

    required property var bar

    property bool vertical: bar.orientation === "vertical"
    property bool isHovered: false
    property bool layerEnabled: true

    property real radius: 0
    property real startRadius: radius
    property real endRadius: radius

    readonly property bool panelOpen: bluetoothPopup.isOpen

    Layout.preferredWidth: 36
    Layout.preferredHeight: 36
    Layout.fillWidth: vertical
    Layout.fillHeight: !vertical

    Component.onCompleted: BluetoothService.initialize()

    HoverHandler {
        onHoveredChanged: root.isHovered = hovered
    }

    onVisibleChanged: {
        if (!visible && panelOpen)
            bluetoothPopup.close();
    }

    StyledRect {
        id: buttonBg
        variant: root.panelOpen ? "primary" : "bg"
        anchors.fill: parent
        enableShadow: root.layerEnabled

        topLeftRadius: root.startRadius
        topRightRadius: root.vertical ? root.startRadius : root.endRadius
        bottomLeftRadius: root.vertical ? root.endRadius : root.startRadius
        bottomRightRadius: root.endRadius

        Rectangle {
            anchors.fill: parent
            color: Styling.srItem("overprimary")
            opacity: root.panelOpen ? 0 : (root.isHovered ? 0.25 : 0)
            radius: parent.radius ?? 0

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration / 2
                }
            }
        }

        Text {
            anchors.centerIn: parent
            text: {
                if (!BluetoothService.enabled)
                    return Icons.bluetoothOff;
                return BluetoothService.connected ? Icons.bluetoothConnected : Icons.bluetooth;
            }
            font.family: Icons.font
            font.pixelSize: 18
            // Matugen accent rather than the near-white foreground the other bar
            // widgets default to, and muted when the adapter is off.
            color: {
                if (root.panelOpen)
                    return buttonBg.item;
                return BluetoothService.enabled ? Colors.primary : Colors.overSurfaceVariant;
            }

            Behavior on color {
                enabled: Config.animDuration > 0
                ColorAnimation {
                    duration: Config.animDuration / 2
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor

            onClicked: event => {
                if (event.button === Qt.RightButton) {
                    // Full manager for the things the flyout deliberately doesn't
                    // do — pairing wizards, adapter settings, file transfer.
                    // Close ours first so it isn't left hanging behind the window.
                    bluetoothPopup.close();
                    Quickshell.execDetached(["blueman-manager"]);
                    return;
                }
                bluetoothPopup.toggle();
            }
        }

        StyledToolTip {
            show: root.isHovered && !root.panelOpen
            tooltipText: {
                if (!BluetoothService.enabled)
                    return "Bluetooth: off";
                if (BluetoothService.connectedDevices > 0)
                    return `Bluetooth: ${BluetoothService.connectedDevices} connected`;
                return "Bluetooth: on";
            }
        }
    }

    BarPopout {
        id: bluetoothPopup
        separatePanel: true
        anchorItem: buttonBg
        bar: root.bar
        popupPadding: 8

        onIsOpenChanged: BluetoothControl.setPanelOpen(isOpen)

        BluetoothFlyout {
            maxContentHeight: Math.max(120, (root.bar.screen?.height ?? 600) - 96)
        }
    }

    Component.onDestruction: {
        if (root.panelOpen)
            bluetoothPopup.close();
    }
}
