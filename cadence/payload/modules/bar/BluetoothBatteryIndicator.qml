pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.services
import qs.modules.components
import qs.modules.theme
import qs.config

// Battery level of the connected Bluetooth devices.
//
// The bar shows one device — whichever has least charge left, since that is the
// only one you need to act on. Clicking opens the full list. With nothing
// connected, or nothing connected that reports a level, the widget removes
// itself from the layout entirely rather than sitting there empty.
Item {
    id: root

    required property var bar

    property bool vertical: bar.orientation === "vertical"
    property bool isHovered: false
    property bool layerEnabled: true

    property real radius: 0
    property real startRadius: radius
    property real endRadius: radius

    readonly property var lowest: BluetoothBattery.lowest
    readonly property int level: lowest?.battery ?? 0

    property bool popupOpen: devicesPopup.isOpen

    visible: BluetoothBattery.available

    Layout.preferredWidth: 36
    Layout.preferredHeight: 36
    Layout.fillWidth: vertical
    Layout.fillHeight: !vertical

    // Same ramp as BatteryIndicator's, so the two indicators sitting next to each
    // other never disagree about what "low" looks like.
    function levelColor(percent: int): color {
        if (percent <= 15)
            return Colors.red;
        if (percent >= 85)
            return Colors.green;
        const ratio = (percent - 15) / (85 - 15);
        return Qt.rgba(Colors.red.r + (Colors.green.r - Colors.red.r) * ratio, Colors.red.g + (Colors.green.g - Colors.red.g) * ratio, Colors.red.b + (Colors.green.b - Colors.red.b) * ratio, 1);
    }

    HoverHandler {
        onHoveredChanged: root.isHovered = hovered
    }

    // The widget can vanish under an open popout — the last device disconnects,
    // or the bar hides — and the popout is drawn by another window, so it would
    // be left behind with nothing to point at.
    onVisibleChanged: {
        if (!visible)
            devicesPopup.close();
    }

    StyledRect {
        id: buttonBg
        variant: root.popupOpen ? "primary" : "bg"
        anchors.fill: parent
        enableShadow: root.layerEnabled

        topLeftRadius: root.startRadius
        topRightRadius: root.vertical ? root.startRadius : root.endRadius
        bottomLeftRadius: root.vertical ? root.endRadius : root.startRadius
        bottomRightRadius: root.endRadius

        Rectangle {
            anchors.fill: parent
            color: Styling.srItem("overprimary")
            opacity: root.popupOpen ? 0 : (root.isHovered ? 0.25 : 0)
            radius: parent.radius ?? 0

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration / 2
                }
            }
        }

        // Same 270-degree gauge and stroke geometry as the KDE Connect widget.
        Canvas {
            id: gauge
            anchors.centerIn: parent
            width: 32
            height: 32
            antialiasing: true

            property real angle: Math.max(0, Math.min(100, root.level)) * 2.7
            readonly property color trackColor: Colors.outlineVariant
            readonly property color fillColor: root.levelColor(root.level)

            onAngleChanged: requestPaint()
            onTrackColorChanged: requestPaint()
            onFillColorChanged: requestPaint()
            onAvailableChanged: {
                if (available)
                    requestPaint();
            }

            Behavior on angle {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: 400
                    easing.type: Easing.OutCubic
                }
            }

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.lineWidth = 3;
                ctx.lineCap = "round";
                const start = 3 * Math.PI / 4;
                const end = start + 3 * Math.PI / 2;
                const split = start + angle * Math.PI / 180;

                if (split < end) {
                    ctx.strokeStyle = trackColor;
                    ctx.beginPath();
                    ctx.arc(width / 2, height / 2, 12, split, end);
                    ctx.stroke();
                }
                if (split > start) {
                    ctx.strokeStyle = fillColor;
                    ctx.beginPath();
                    ctx.arc(width / 2, height / 2, 12, start, split);
                    ctx.stroke();
                }
            }
        }

        Text {
            anchors.centerIn: parent
            text: Icons.bluetoothDeviceIcon(root.lowest?.icon ?? "")
            font.family: Icons.font
            font.pixelSize: 16
            color: root.popupOpen ? buttonBg.item : Colors.primary
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: devicesPopup.toggle()
        }

        StyledToolTip {
            show: root.isHovered && !root.popupOpen
            tooltipText: root.lowest ? `${root.lowest.name}: ${root.level}%` : ""
        }
    }

    // Device list — a floating pill next to the bar, or grown out of the frame
    // when the bar is contained by it. See BarPopout.
    BarPopout {
        id: devicesPopup
        separatePanel: true
        anchorItem: buttonBg
        bar: root.bar
        popupPadding: 8

        Item {
            implicitWidth: 236
            // Fixed per row rather than derived from the column, so the panel
            // doesn't expand into place on first open.
            implicitHeight: Math.max(1, BluetoothBattery.devices.length) * 44 + Math.max(0, BluetoothBattery.devices.length - 1) * 4

            ColumnLayout {
                anchors.fill: parent
                spacing: 4

                Repeater {
                    model: BluetoothBattery.devices

                    delegate: StyledRect {
                        id: deviceRow
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.preferredHeight: 44

                        // The one the bar is showing gets the accent, so it's
                        // obvious which device the gauge outside represents.
                        readonly property bool isLowest: modelData.address === (BluetoothBattery.lowest?.address ?? "")

                        variant: isLowest ? "primary" : "common"
                        enableShadow: false
                        // Nests inside the popout's own corners; see BarPopout.contentRadius.
                        radius: devicesPopup.contentRadius

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            Text {
                                text: Icons.bluetoothDeviceIcon(deviceRow.modelData.icon)
                                font.family: Icons.font
                                font.pixelSize: 18
                                color: deviceRow.item
                            }

                            Text {
                                Layout.fillWidth: true
                                text: deviceRow.modelData.name
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(-1)
                                font.weight: Font.Medium
                                color: deviceRow.item
                                elide: Text.ElideRight
                            }

                            Text {
                                visible: deviceRow.modelData.batteryAvailable
                                text: Icons.batteryLevelIcon(deviceRow.modelData.battery)
                                font.family: Icons.font
                                font.pixelSize: 16
                                color: deviceRow.item
                            }

                            Text {
                                // A connected device that reports no level still
                                // belongs in the list; it just has nothing to say.
                                text: deviceRow.modelData.batteryAvailable ? deviceRow.modelData.battery + "%" : "—"
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(-1)
                                font.bold: true
                                color: deviceRow.item
                                opacity: deviceRow.modelData.batteryAvailable ? 1 : 0.6
                            }
                        }
                    }
                }
            }
        }
    }
}
