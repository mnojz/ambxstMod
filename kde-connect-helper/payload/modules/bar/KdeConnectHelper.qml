pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

Item {
    id: root

    required property var bar
    property bool vertical: bar.orientation === "vertical"
    property bool layerEnabled: true
    property real startRadius: Styling.radius(0)
    property real endRadius: Styling.radius(0)
    property var pendingFiles: []
    property string confirmAction: ""
    property int installStep: 0
    property bool isHovered: false
    readonly property bool popupOpen: helperPopup.isOpen

    HoverHandler {
        onHoveredChanged: root.isHovered = hovered
    }

    readonly property var device: KdeConnectService.selectedDevice
    readonly property bool hasBattery: !!device?.hasBattery
    readonly property string statusKey: {
        if (!KdeConnectService.installed)
            return "not_installed";
        if (!KdeConnectService.daemonRunning)
            return "daemon_stopped";
        if (KdeConnectService.pairedDevices.length === 0)
            return "no_paired_devices";
        if (KdeConnectService.connectedDevices.length === 0)
            return "offline";
        if (KdeConnectService.connectedDevices.length > 1)
            return "connected_count";
        return "connected";
    }
    readonly property string statusText: statusKey === "connected_count"
        ? I18n.t("kde_connect_helper.status.connected_count", KdeConnectService.connectedDevices.length)
        : I18n.t("kde_connect_helper.status." + statusKey)
    readonly property string batteryPercentage: hasBattery
        ? Math.round(device.battery) + "%" : ""
    readonly property bool deviceCharging: hasBattery && !!device?.reachable && !!device?.charging
    readonly property string mainGlyph: Icons.deviceMobile
    readonly property string tooltipTitle: device?.name ?? I18n.t("kde_connect_helper.title")
    readonly property string tooltipDescription: {
        const details = [statusText];
        if (device) {
            details.push(hasBattery
                ? I18n.t("kde_connect_helper.battery_value", Math.round(device.battery),
                    deviceCharging ? I18n.t("kde_connect_helper.charging") : "")
                : I18n.t("kde_connect_helper.battery_unavailable"));
        }
        return details.join(" · ");
    }

    function getBatteryColor() {
        if (!root.hasBattery)
            return Colors.overBackground;

        const pct = root.device?.battery ?? 0;
        if (pct <= 15)
            return Colors.red;
        if (pct >= 85)
            return Colors.green;

        // Linear interpolation between red (15%) and green (85%) matching BatteryIndicator
        const ratio = (pct - 15) / (85 - 15);
        return Qt.rgba(
            Colors.red.r + (Colors.green.r - Colors.red.r) * ratio,
            Colors.red.g + (Colors.green.g - Colors.red.g) * ratio,
            Colors.red.b + (Colors.green.b - Colors.red.b) * ratio,
            1
        );
    }

    implicitWidth: 36
    implicitHeight: 36
    Layout.preferredWidth: 36
    Layout.preferredHeight: 36
    Layout.fillWidth: vertical
    Layout.fillHeight: !vertical
    visible: KdeConnectService.shouldShowButton

    // Largest popup content height that fits between the bar and the far screen
    // edge. Measured on open because the button's place on the bar can change.
    property real popupSpace: 480
    readonly property int popupEdgeGap: 8
    readonly property int scrollGutter: 14

    function updatePopupSpace() {
        const screenHeight = root.bar?.screen?.height ?? 0;
        if (screenHeight <= 0)
            return;
        let reserved = popupEdgeGap * 2;
        if (!helperPopup.barVertical) {
            const origin = buttonBackground.mapToItem(null, 0, 0);
            const windowHeight = buttonBackground.Window.window?.height ?? screenHeight;
            const barExtent = helperPopup.barAtTop
                ? origin.y + buttonBackground.height
                : windowHeight - origin.y;
            reserved = barExtent + helperPopup.visualMargin + helperPopup.effectiveFrameOffset + popupEdgeGap;
        }
        popupSpace = Math.max(160, screenHeight - reserved - helperPopup.popupPadding * 2);
    }

    function openPrimary() {
        if (!helperPopup.isOpen)
            root.updatePopupSpace();
        helperPopup.toggle();
        if (!KdeConnectService.installed) {
            root.installStep = 0;
            KdeConnectService.loadInstallPlan();
            installModal.visible = true;
        }
    }

    function planValue(value) {
        const text = String(value ?? "");
        return text.length > 0 && text !== "unknown" ? text : I18n.t("kde_connect_helper.unknown");
    }

    function installMethodText() {
        const method = String(KdeConnectService.installPlan.method ?? "manual");
        return I18n.t("kde_connect_helper.install_method." + method);
    }

    function unsupportedActions() {
        if (!device || !device.reachable)
            return "";
        const actions = [];
        if (!device.supportsPing)
            actions.push(I18n.t("kde_connect_helper.ping"));
        if (!device.supportsRing)
            actions.push(I18n.t("kde_connect_helper.ring"));
        if (!device.supportsShare)
            actions.push(I18n.t("kde_connect_helper.send_file"));
        if (!device.supportsBrowse)
            actions.push(I18n.t("kde_connect_helper.browse_files"));
        return actions.join(", ");
    }

    component HelperButton: Button {
        id: control
        property string iconText: ""
        property string labelText: ""
        property string tooltipText: ""
        property bool danger: false
        implicitHeight: 36
        leftPadding: control.labelText.length > 0 ? 8 : 0
        rightPadding: control.labelText.length > 0 ? 8 : 0
        activeFocusOnTab: true
        Accessible.name: control.labelText.length > 0 ? control.labelText : (control.tooltipText.length > 0 ? control.tooltipText : control.iconText)
        background: StyledRect {
            id: helperButtonBackground
            variant: control.down || control.checked ? "primary" : (control.hovered || control.activeFocus ? "focus" : "common")
            radius: Styling.radius(-4)
            enableShadow: false
        }
        contentItem: RowLayout {
            spacing: control.iconText.length > 0 && control.labelText.length > 0 ? 6 : 0
            Text {
                visible: control.iconText.length > 0
                Layout.alignment: control.labelText.length === 0 ? Qt.AlignCenter : Qt.AlignVCenter
                text: control.iconText
                font.family: Icons.font
                font.pixelSize: control.labelText.length === 0 ? 18 : 16
                color: helperButtonBackground.item
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            Text {
                visible: control.labelText.length > 0
                Layout.fillWidth: true
                text: control.labelText
                color: control.danger ? Colors.red : helperButtonBackground.item
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(-1)
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
        StyledToolTip {
            show: control.hovered && control.tooltipText.length > 0
            tooltipText: control.tooltipText
        }
    }

    StyledRect {
        id: buttonBackground
        variant: root.popupOpen ? "primary" : "bg"
        anchors.fill: parent
        enableShadow: root.layerEnabled
        topLeftRadius: root.vertical ? root.startRadius : root.startRadius
        topRightRadius: root.vertical ? root.startRadius : root.endRadius
        bottomLeftRadius: root.vertical ? root.endRadius : root.startRadius
        bottomRightRadius: root.vertical ? root.endRadius : root.endRadius

        // Background highlight on hover
        Rectangle {
            anchors.fill: parent
            color: Styling.srItem("overprimary")
            opacity: root.popupOpen ? 0 : (root.isHovered ? 0.25 : 0)
            radius: parent.radius ?? 0

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation { duration: Config.animDuration / 2 }
            }
        }

        // Circular progress indicator (matching BatteryIndicator style)
        Item {
            id: progressCanvas
            anchors.centerIn: parent
            width: 32
            height: 32
            visible: root.hasBattery && !!root.device?.reachable

            readonly property real batteryPct: Math.max(0, Math.min(100, root.device?.battery ?? 0))
            property real angle: (batteryPct / 100) * (360 - 2 * gapAngle)
            property real radius: 12
            property real lineWidth: 3
            property real gapAngle: 45

            Canvas {
                id: canvas
                anchors.fill: parent
                antialiasing: true

                onPaint: {
                    let ctx = getContext("2d");
                    ctx.reset();

                    let centerX = width / 2;
                    let centerY = height / 2;
                    let radius = progressCanvas.radius;
                    let lineWidth = progressCanvas.lineWidth;

                    ctx.lineCap = "round";

                    // Base start angle (matching CircularControl & BatteryIndicator: bottom + gap)
                    let baseStartAngle = (Math.PI / 2) + (progressCanvas.gapAngle * Math.PI / 180);
                    let progressAngleRad = progressCanvas.angle * Math.PI / 180;

                    // Draw background track (remaining part)
                    let totalAngleRad = (360 - 2 * progressCanvas.gapAngle) * Math.PI / 180;

                    ctx.strokeStyle = Colors.outlineVariant;
                    ctx.lineWidth = lineWidth;
                    ctx.beginPath();
                    ctx.arc(centerX, centerY, radius, baseStartAngle + progressAngleRad, baseStartAngle + totalAngleRad, false);
                    ctx.stroke();

                    // Draw progress
                    if (progressCanvas.angle > 0) {
                        ctx.strokeStyle = root.getBatteryColor();
                        ctx.lineWidth = lineWidth;
                        ctx.beginPath();
                        ctx.arc(centerX, centerY, radius, baseStartAngle, baseStartAngle + progressAngleRad, false);
                        ctx.stroke();
                    }
                }

                Connections {
                    target: progressCanvas
                    function onAngleChanged() { canvas.requestPaint(); }
                }

                Connections {
                    target: KdeConnectService
                    function onSelectedDeviceChanged() { canvas.requestPaint(); }
                    function onDevicesChanged() { canvas.requestPaint(); }
                }

                Connections {
                    target: root
                    function onDeviceChanged() { canvas.requestPaint(); }
                }
            }

            Behavior on angle {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: 400
                    easing.type: Easing.OutCubic
                }
            }
        }

        // Central icon (centered mobile device glyph)
        Text {
            id: centralIcon
            anchors.centerIn: parent
            anchors.verticalCenterOffset: root.deviceCharging ? -1 : 0
            text: root.mainGlyph
            font.family: Icons.font
            font.pixelSize: (root.hasBattery && !!root.device?.reachable) ? 14 : 17
            color: root.popupOpen ? buttonBackground.item : Styling.srItem("overprimary")

            Behavior on color {
                enabled: Config.animDuration > 0
                ColorAnimation { duration: Config.animDuration / 2 }
            }
        }

        // Charging badge centered at bottom between the two ends of the circular charge gauge
        Text {
            id: chargingBadge
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            visible: root.deviceCharging
            text: Icons.lightning
            font.family: Icons.font
            font.pixelSize: 9
            color: root.popupOpen ? buttonBackground.item : Colors.green

            Behavior on color {
                enabled: Config.animDuration > 0
                ColorAnimation { duration: Config.animDuration / 2 }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: false
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openPrimary()
        }
    }

    StyledToolTip {
        show: root.isHovered && !root.popupOpen
        tooltipText: root.tooltipTitle
        desciription: root.tooltipDescription
    }

    BarPopup {
        id: helperPopup
        anchorItem: buttonBackground
        bar: root.bar
        popupPadding: 14
        // The scroll gutter widens the popup instead of narrowing its content
        readonly property real baseWidth: Math.max(280, Math.min(336, (root.bar?.screen?.width ?? 384) - 48 - root.scrollGutter))
        readonly property real neededHeight: Math.max(scrollArea.contentHeight,
            installModal.visible ? installColumn.implicitHeight + 40 : 0,
            confirmModal.visible ? confirmColumn.implicitHeight + 40 : 0)
        contentWidth: baseWidth + (scrollArea.overflowing ? root.scrollGutter : 0)
        contentHeight: Math.ceil(Math.min(neededHeight, root.popupSpace)) + popupPadding * 2
        closeOnFocusLost: KdeConnectService.operation !== "choose_files"
        onIsOpenChanged: {
            if (isOpen)
                Qt.callLater(() => refreshButton.forceActiveFocus());
        }

        Flickable {
            id: scrollArea
            anchors.fill: parent
            readonly property bool overflowing: contentHeight > height + 1
            contentWidth: width
            contentHeight: popupColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: overflowing
            enabled: !installModal.visible && !confirmModal.visible
            visible: enabled
            // Shown only when the content really overflows; it sits in its own
            // gutter to the right of the content instead of over it
            ScrollBar.vertical: ScrollBar {
                policy: scrollArea.overflowing ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                implicitWidth: root.scrollGutter - 6
            }

            ColumnLayout {
                id: popupColumn
                width: scrollArea.width - (scrollArea.overflowing ? root.scrollGutter : 0)
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: Icons.deviceMobile
                        font.family: Icons.font
                        font.pixelSize: 20
                        color: Colors.overBackground
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: I18n.t("kde_connect_helper.title")
                            color: Colors.overBackground
                            font.family: Styling.defaultFont
                            font.pixelSize: Styling.fontSize(1)
                            font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.statusText
                            color: Colors.overBackground
                            opacity: 0.72
                            font.family: Styling.defaultFont
                            font.pixelSize: Styling.fontSize(-1)
                            wrapMode: Text.Wrap
                        }
                    }

                    BusyIndicator {
                        running: KdeConnectService.scanning || KdeConnectService.busy
                        visible: running
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                    }

                    HelperButton {
                        id: refreshButton
                        implicitWidth: 32
                        implicitHeight: 32
                        iconText: Icons.sync
                        enabled: !KdeConnectService.activeRequest
                        onClicked: KdeConnectService.refresh()
                    }

                    HelperButton {
                        implicitWidth: 32
                        implicitHeight: 32
                        iconText: Icons.arrowSquareOut
                        enabled: KdeConnectService.launcherExecutable.length > 0 && !KdeConnectService.activeRequest
                        onClicked: KdeConnectService.openInterface()
                    }
                }

                // Problem states (only shown if something needs attention)
                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: statusColumn.implicitHeight + 20
                    visible: !KdeConnectService.installed || !KdeConnectService.daemonRunning
                    variant: "common"
                    radius: Styling.radius(0)
                    enableShadow: false
                    ColumnLayout {
                        id: statusColumn
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 5
                        Text {
                            Layout.fillWidth: true
                            text: I18n.t("kde_connect_helper.installed_status", KdeConnectService.installed
                                ? I18n.t("kde_connect_helper.yes") : I18n.t("kde_connect_helper.no"))
                            color: Colors.overBackground
                            font.family: Styling.defaultFont
                            font.pixelSize: Styling.fontSize(-1)
                        }
                        Text {
                            Layout.fillWidth: true
                            text: I18n.t("kde_connect_helper.daemon_status", KdeConnectService.daemonRunning
                                ? I18n.t("kde_connect_helper.running") : I18n.t("kde_connect_helper.stopped"))
                            color: Colors.overBackground
                            font.family: Styling.defaultFont
                            font.pixelSize: Styling.fontSize(-1)
                        }
                    }
                }

                HelperButton {
                    Layout.fillWidth: true
                    visible: KdeConnectService.installed && !KdeConnectService.daemonRunning
                    iconText: Icons.play
                    labelText: I18n.t("kde_connect_helper.start_daemon")
                    enabled: KdeConnectService.daemonExecutable.length > 0 && !KdeConnectService.activeRequest
                    onClicked: KdeConnectService.startDaemon()
                }

                Text {
                    Layout.fillWidth: true
                    visible: KdeConnectService.installed && !KdeConnectService.daemonRunning
                        && KdeConnectService.daemonExecutable.length === 0
                    text: I18n.t("kde_connect_helper.message.daemon_executable_missing")
                    color: Colors.overBackground
                    opacity: 0.65
                    font.family: Styling.defaultFont
                    font.pixelSize: Styling.fontSize(-2)
                    wrapMode: Text.Wrap
                }

                HelperButton {
                    Layout.fillWidth: true
                    visible: !KdeConnectService.installed
                    iconText: Icons.arrowFatLinesDown
                    labelText: I18n.t("kde_connect_helper.installation_options")
                    enabled: !KdeConnectService.activeRequest
                    onClicked: {
                        root.installStep = 0;
                        KdeConnectService.loadInstallPlan();
                        installModal.visible = true;
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: KdeConnectService.installed && KdeConnectService.daemonRunning && KdeConnectService.pairedDevices.length === 0
                    text: I18n.t("kde_connect_helper.pairing_hint")
                    color: Colors.overBackground
                    opacity: 0.76
                    font.family: Styling.defaultFont
                    font.pixelSize: Styling.fontSize(-1)
                    wrapMode: Text.Wrap
                }

                // Device selector (if more than 1 paired device)
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: KdeConnectService.pairedDevices.length > 1
                    spacing: 5
                    Text {
                        text: I18n.t("kde_connect_helper.devices")
                        color: Colors.overBackground
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-1)
                        font.bold: true
                    }
                    Repeater {
                        model: KdeConnectService.pairedDevices
                        delegate: HelperButton {
                            required property var modelData
                            Layout.fillWidth: true
                            iconText: modelData.reachable ? Icons.deviceMobile : Icons.alert
                            labelText: modelData.name + "  " + I18n.t("kde_connect_helper.device."
                                + (modelData.reachable ? "connected" : "offline"))
                            checked: KdeConnectService.selectedDevice?.id === modelData.id
                            onClicked: KdeConnectService.setPreferredDevice(modelData.id)
                        }
                    }
                    HelperButton {
                        Layout.fillWidth: true
                        labelText: I18n.t("kde_connect_helper.automatic_device")
                        visible: KdeConnectService.preferredDevice !== "auto"
                        onClicked: KdeConnectService.setPreferredDevice("auto")
                    }
                }

                // Active / Selected Device Card
                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: deviceRow.implicitHeight + 20
                    visible: !!root.device
                    variant: "common"
                    radius: Styling.radius(0)
                    enableShadow: false

                    RowLayout {
                        id: deviceRow
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        Text {
                            text: Icons.deviceMobile
                            font.family: Icons.font
                            font.pixelSize: 22
                            color: root.device?.reachable ? Colors.primary : Colors.overBackground
                            opacity: root.device?.reachable ? 1 : 0.5
                            verticalAlignment: Text.AlignVCenter
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                                Layout.fillWidth: true
                                text: root.device?.name ?? ""
                                color: Colors.overBackground
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(0)
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            RowLayout {
                                spacing: 6
                                visible: root.hasBattery && !!root.device?.reachable

                                Text {
                                    text: root.deviceCharging ? Icons.lightning : Icons.batteryCharging
                                    font.family: Icons.font
                                    font.pixelSize: 13
                                    color: root.getBatteryColor()
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Text {
                                    text: root.hasBattery
                                        ? I18n.t("kde_connect_helper.battery_value", Math.round(root.device.battery),
                                            root.device.charging ? I18n.t("kde_connect_helper.charging") : "")
                                        : ""
                                    color: Colors.overBackground
                                    opacity: 0.72
                                    font.family: Styling.defaultFont
                                    font.pixelSize: Styling.fontSize(-1)
                                }
                            }

                            Text {
                                visible: !root.device?.reachable
                                text: I18n.t("kde_connect_helper.device.offline")
                                color: Colors.overBackground
                                opacity: 0.6
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(-1)
                            }

                            Text {
                                visible: root.device?.reachable && !root.hasBattery
                                text: I18n.t("kde_connect_helper.battery_unavailable")
                                color: Colors.overBackground
                                opacity: 0.6
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(-1)
                            }
                        }
                    }
                }

                // Quick Actions (Single Row, Equal Size, Icon Only)
                Text {
                    visible: !!root.device
                    text: I18n.t("kde_connect_helper.quick_actions")
                    color: Colors.overBackground
                    font.family: Styling.defaultFont
                    font.pixelSize: Styling.fontSize(-1)
                    font.bold: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: !!root.device
                    spacing: 6

                    HelperButton {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: 38
                        iconText: Icons.paperPlane
                        tooltipText: I18n.t("kde_connect_helper.ping")
                        enabled: !!root.device?.reachable && !!root.device?.supportsPing && !KdeConnectService.activeRequest
                        onClicked: KdeConnectService.runAction("ping")
                    }

                    HelperButton {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: 38
                        iconText: Icons.bellRinging
                        tooltipText: I18n.t("kde_connect_helper.ring")
                        enabled: !!root.device?.reachable && !!root.device?.supportsRing && !KdeConnectService.activeRequest
                        onClicked: KdeConnectService.runAction("ring")
                    }

                    HelperButton {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: 38
                        iconText: Icons.file
                        tooltipText: I18n.t("kde_connect_helper.send_file")
                        enabled: !!root.device?.reachable && !!root.device?.supportsShare && !KdeConnectService.activeRequest
                        onClicked: KdeConnectService.chooseFiles(I18n.t("kde_connect_helper.choose_file"))
                    }

                    HelperButton {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: 38
                        iconText: Icons.folder
                        tooltipText: I18n.t("kde_connect_helper.browse_files")
                        enabled: !!root.device?.reachable && !!root.device?.supportsBrowse && !KdeConnectService.activeRequest
                        onClicked: KdeConnectService.runAction("browse_files")
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: !!root.device && (!root.device.reachable || root.unsupportedActions().length > 0)
                    text: !root.device?.reachable ? I18n.t("kde_connect_helper.actions_offline_reason")
                        : I18n.t("kde_connect_helper.unsupported_actions", root.unsupportedActions())
                    color: Colors.overBackground
                    opacity: 0.65
                    font.family: Styling.defaultFont
                    font.pixelSize: Styling.fontSize(-2)
                    wrapMode: Text.Wrap
                }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: messageLabel.implicitHeight + 16
                    visible: KdeConnectService.messageCode.length > 0
                    variant: "common"
                    radius: Styling.radius(-4)
                    enableShadow: false
                    Text {
                        id: messageLabel
                        anchors.fill: parent
                        anchors.margins: 8
                        text: I18n.t("kde_connect_helper.message." + KdeConnectService.messageCode)
                        color: KdeConnectService.messageError ? Colors.red : Colors.overBackground
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-1)
                        wrapMode: Text.Wrap
                    }
                }
            }
        }

        Item {
            id: installModal
            anchors.fill: parent
            z: 20
            visible: false
            focus: visible
            onVisibleChanged: {
                if (visible)
                    Qt.callLater(() => installCancel.forceActiveFocus());
                else if (helperPopup.isOpen)
                    Qt.callLater(() => refreshButton.forceActiveFocus());
            }
            Keys.onEscapePressed: visible = false
            Rectangle { anchors.fill: parent; color: Colors.scrim; opacity: 0.55 }
            StyledRect {
                id: installCard
                anchors.centerIn: parent
                width: Math.min(parent.width - 20, 310)
                height: Math.min(parent.height - 16, installColumn.implicitHeight + 24)
                variant: "popup"
                radius: Styling.radius(4)
                Flickable {
                    id: installScroll
                    readonly property bool overflowing: contentHeight > height + 1
                    anchors.fill: parent
                    anchors.margins: 12
                    contentWidth: width
                    contentHeight: installColumn.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: overflowing
                    ScrollBar.vertical: ScrollBar {
                        policy: installScroll.overflowing ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                        implicitWidth: root.scrollGutter - 6
                    }
                    ColumnLayout {
                        id: installColumn
                        width: parent.width - (installScroll.overflowing ? root.scrollGutter : 0)
                        spacing: 7
                    Text {
                        Layout.fillWidth: true
                        text: I18n.t("kde_connect_helper.install_title")
                        color: Colors.overBackground
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(1)
                        font.bold: true
                        wrapMode: Text.Wrap
                    }
                    BusyIndicator {
                        Layout.alignment: Qt.AlignHCenter
                        visible: KdeConnectService.installPlanBusy || KdeConnectService.operation === "install"
                        running: visible
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !KdeConnectService.installPlanBusy
                        text: I18n.t("kde_connect_helper.install_summary",
                            root.planValue(KdeConnectService.installPlan.distribution),
                            root.planValue(KdeConnectService.installPlan.manager),
                            root.planValue(KdeConnectService.installPlan.package),
                            root.installMethodText())
                        color: Colors.overBackground
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-1)
                        wrapMode: Text.Wrap
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !KdeConnectService.installPlanBusy
                        text: KdeConnectService.installPlan.pkexec
                            ? I18n.t("kde_connect_helper.pkexec_detected")
                            : I18n.t("kde_connect_helper.pkexec_not_detected")
                        color: Colors.overBackground
                        opacity: 0.76
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-1)
                        wrapMode: Text.Wrap
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !KdeConnectService.installPlanBusy
                        text: KdeConnectService.installPlan.automatic
                            ? I18n.t("kde_connect_helper.pkexec_available")
                            : I18n.t("kde_connect_helper.automatic_unavailable")
                        color: Colors.overBackground
                        opacity: 0.76
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-1)
                        wrapMode: Text.Wrap
                    }
                    TextArea {
                        id: manualInstallCommand
                        Layout.fillWidth: true
                        Layout.preferredHeight: 62
                        visible: !KdeConnectService.installPlan.automatic && (KdeConnectService.installPlan.command ?? "").length > 0
                        readOnly: true
                        selectByMouse: true
                        text: KdeConnectService.installPlan.command ?? ""
                        wrapMode: TextEdit.WrapAnywhere
                        Accessible.name: I18n.t("kde_connect_helper.manual_instruction")
                        background: StyledRect {
                            variant: manualInstallCommand.activeFocus ? "focus" : "internalbg"
                            radius: Styling.radius(-4)
                            enableShadow: false
                        }
                        color: Colors.overBackground
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: KdeConnectService.installPlan.family === "nixos"
                        text: I18n.t("kde_connect_helper.nixos_note")
                        color: Colors.overBackground
                        opacity: 0.76
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-1)
                        wrapMode: Text.Wrap
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: root.installStep === 1
                        text: I18n.t("kde_connect_helper.install_confirmation")
                        color: Colors.overBackground
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-1)
                        font.bold: true
                        wrapMode: Text.Wrap
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        HelperButton {
                            id: installCancel
                            Layout.fillWidth: true
                            labelText: I18n.t("kde_connect_helper.cancel")
                            onClicked: installModal.visible = false
                        }
                        HelperButton {
                            Layout.fillWidth: true
                            visible: !!KdeConnectService.installPlan.automatic
                            labelText: root.installStep === 0 ? I18n.t("kde_connect_helper.continue")
                                : I18n.t("kde_connect_helper.install_now")
                            enabled: !KdeConnectService.activeRequest
                            onClicked: {
                                if (root.installStep === 0)
                                    root.installStep = 1;
                                else
                                    KdeConnectService.install();
                            }
                        }
                    }
                    }
                }
            }
        }

        Item {
            id: confirmModal
            anchors.fill: parent
            z: 21
            visible: false
            focus: visible
            onVisibleChanged: {
                if (visible)
                    Qt.callLater(() => confirmCancel.forceActiveFocus());
                else if (helperPopup.isOpen)
                    Qt.callLater(() => refreshButton.forceActiveFocus());
            }
            Keys.onEscapePressed: visible = false
            Rectangle { anchors.fill: parent; color: Colors.scrim; opacity: 0.55 }
            StyledRect {
                anchors.centerIn: parent
                width: Math.min(parent.width - 20, 300)
                implicitHeight: confirmColumn.implicitHeight + 24
                variant: "popup"
                radius: Styling.radius(4)
                ColumnLayout {
                    id: confirmColumn
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10
                    Text {
                        Layout.fillWidth: true
                        text: I18n.t("kde_connect_helper.confirm_file")
                        color: Colors.overBackground
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(0)
                        font.bold: true
                        wrapMode: Text.Wrap
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        HelperButton {
                            id: confirmCancel
                            Layout.fillWidth: true
                            labelText: I18n.t("kde_connect_helper.cancel")
                            onClicked: confirmModal.visible = false
                        }
                        HelperButton {
                            Layout.fillWidth: true
                            labelText: I18n.t("kde_connect_helper.send")
                            enabled: !KdeConnectService.activeRequest
                            onClicked: {
                                KdeConnectService.runAction("share_files", root.pendingFiles);
                                confirmModal.visible = false;
                            }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: KdeConnectService
        function onFilesChosen(paths) {
            root.pendingFiles = paths;
            root.confirmAction = "file";
            if (!helperPopup.isOpen) {
                root.updatePopupSpace();
                helperPopup.open();
            }
            confirmModal.visible = true;
        }
    }

    Connections {
        target: KdeConnectService
        function onInstalledChanged() {
            if (KdeConnectService.installed)
                installModal.visible = false;
        }
    }
}
