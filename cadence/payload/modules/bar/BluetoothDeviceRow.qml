pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

// A single device line in the bar's Bluetooth flyout.
// One click is the whole interaction: connect if it isn't connected, disconnect if it is.
Item {
    id: root

    required property BluetoothDevice device

    // Raised after an action is issued so the popup can refresh sooner than its poll.
    signal actionTaken

    // BluetoothService destroys device objects as they drop out of `bluetoothctl
    // devices`, which during a scan happens constantly. A delegate can therefore
    // outlive its device by a frame; collapse rather than render a blank row.
    readonly property bool valid: device !== null

    readonly property bool connected: device?.connected ?? false
    readonly property bool busy: device?.connecting ?? false

    // Only a paired device has anything to forget; a discovered one is already
    // gone the moment BlueZ drops it.
    readonly property bool canForget: device?.paired ?? false
    // Revealed by right-click, so forgetting always takes a deliberate second
    // click and can never be a mis-aimed connect.
    property bool forgetArmed: false

    onCanForgetChanged: {
        if (!canForget)
            forgetArmed = false;
    }

    // Single driver for the forget button's reveal: width, fade and pop all come
    // off this, so they can't drift apart. Overshoots on the way out and settles
    // on the way back, matching the panel's own easing.
    property real forgetReveal: forgetArmed ? 1 : 0

    Behavior on forgetReveal {
        enabled: Config.animDuration > 0
        NumberAnimation {
            duration: Config.animDuration / 2
            easing.type: root.forgetArmed ? Easing.OutBack : Easing.OutQuart
            easing.overshoot: root.forgetArmed ? 1.6 : 1.0
        }
    }

    visible: valid
    implicitHeight: valid ? 44 : 0

    // Passive hover for the whole row. A child MouseArea (the forget button)
    // takes hover away from a MouseArea, which would disarm and hide the button
    // the instant the pointer reached it; a HoverHandler keeps reporting.
    HoverHandler {
        id: rowHover

        onHoveredChanged: {
            if (!hovered)
                root.forgetArmed = false;
        }
    }

    StyledRect {
        id: rowBg
        anchors.fill: parent
        variant: root.connected ? "primary" : (rowHover.hovered ? "focus" : "common")
        enableShadow: false
        radius: Styling.radius(0)
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        onClicked: event => {
            if (event.button === Qt.RightButton) {
                if (root.canForget)
                    root.forgetArmed = !root.forgetArmed;
                return;
            }
            if (root.busy)
                return;
            if (root.connected)
                root.device.disconnect();
            else
                root.device.connect();
            root.actionTaken();
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 10

        Text {
            text: Icons.bluetoothDeviceIcon(root.device?.icon ?? "")
            font.family: Icons.font
            font.pixelSize: 18
            color: root.connected ? rowBg.item : Colors.overBackground
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
                Layout.fillWidth: true
                text: root.device?.name ?? "Unknown device"
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(-1)
                font.weight: Font.Medium
                color: root.connected ? rowBg.item : Colors.overBackground
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: {
                    if (root.busy)
                        return "Connecting…";
                    if (root.connected)
                        return root.device?.batteryAvailable ? `Connected · ${root.device.battery}%` : "Connected";
                    if (root.device?.paired)
                        return "Paired";
                    return root.device?.address ?? "";
                }
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(-3)
                color: root.connected ? rowBg.item : Colors.overSurfaceVariant
                opacity: 0.8
                elide: Text.ElideRight
            }
        }

        // Battery pip for connected devices that report one
        Text {
            visible: root.connected && (root.device?.batteryAvailable ?? false)
            text: Icons.batteryLevelIcon(root.device?.battery ?? 0)
            font.family: Icons.font
            font.pixelSize: 16
            color: rowBg.item
        }

        // Forget button, revealed by right-clicking a paired device. Sits ahead of
        // the affordance below so it replaces it rather than crowding it.
        StyledRect {
            id: forgetButton
            // Width tracks the reveal so the row reflows with it; the pop is left
            // to scale alone, otherwise both overshoot and it reads as a wobble.
            Layout.preferredWidth: 26 * Math.min(1, Math.max(0, root.forgetReveal))
            Layout.preferredHeight: 26
            visible: root.forgetReveal > 0.01
            opacity: Math.min(1, root.forgetReveal)
            scale: 0.5 + 0.5 * root.forgetReveal
            variant: "error"
            enableShadow: false
            radius: height / 2

            // Deepens to a saturated red under the pointer — a destructive action
            // should read hotter as you commit to it. srErrorFocus is no use here:
            // its gradient is overBackground, so it washes out rather than reddens.
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Colors.errorContainer
                opacity: forgetMouse.containsMouse ? 1 : 0

                Behavior on opacity {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration / 2
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                text: Icons.cancel
                font.family: Icons.font
                font.pixelSize: 14
                color: forgetMouse.containsMouse ? Colors.overErrorContainer : Styling.srItem("error")

                Behavior on color {
                    enabled: Config.animDuration > 0
                    ColorAnimation {
                        duration: Config.animDuration / 2
                    }
                }
            }

            MouseArea {
                id: forgetMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.forgetArmed = false;
                    root.device.forget();
                    root.actionTaken();
                }
            }

            StyledToolTip {
                show: forgetMouse.containsMouse
                tooltipText: `Forget ${root.device?.name ?? "device"}`
            }
        }

        // Trailing affordance: spinner while connecting, otherwise the action hint on hover
        Item {
            Layout.preferredWidth: 16
            Layout.preferredHeight: 16
            // Hands over partway through the reveal rather than snapping out.
            visible: root.forgetReveal < 0.5

            Text {
                id: spinner
                anchors.centerIn: parent
                visible: root.busy
                text: Icons.circleNotch
                font.family: Icons.font
                font.pixelSize: 14
                color: root.connected ? rowBg.item : Colors.overSurfaceVariant

                RotationAnimator on rotation {
                    running: spinner.visible
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 900
                }
            }

            Text {
                anchors.centerIn: parent
                visible: !root.busy && rowHover.hovered
                text: root.connected ? Icons.bluetoothX : Icons.bluetoothConnected
                font.family: Icons.font
                font.pixelSize: 14
                color: root.connected ? rowBg.item : Colors.overSurfaceVariant
            }
        }
    }
}
