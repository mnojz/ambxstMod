pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

Flickable {
    id: root

    required property bool opened
    required property real maxContentHeight
    signal settingsRequested

    property string page: "networks"
    property string subpage: "saved"
    property real pageProgress: page === "networks" ? 0 : 1

    Behavior on pageProgress {
        enabled: root.opened && Config.animDuration > 0
        NumberAnimation {
            duration: Config.animDuration
            easing.type: Easing.InOutCubic
        }
    }
    property var profiles: []
    property var passwordNetwork: null
    property string pendingPassword: ""
    property string feedback: ""
    property string failureMessage: ""
    property string forgetUuid: ""
    property var details: []
    readonly property var activeWifi: profiles.find(profile => profile.wifi && profile.device) ?? null
    readonly property var available: NetworkService.friendlyWifiNetworks.filter(network => network && !network.active)
    readonly property bool busy: networkJob.running || NetworkService.isUpdating

    implicitWidth: 284
    implicitHeight: Math.min(contentColumn.implicitHeight, maxContentHeight)
    clip: true
    contentWidth: width
    contentHeight: contentColumn.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    onOpenedChanged: {
        if (opened) {
            refresh();
        } else {
            page = "networks";
            passwordNetwork = null;
            passwordInput.clear();
            forgetUuid = "";
            feedback = "";
        }
    }
    Component.onCompleted: {
        if (opened)
            refresh();
    }
    onPageChanged: {
        contentY = 0;
        if (page !== "networks")
            subpage = page;
        forgetUuid = "";
        if (page === "details" && !detailsJob.running)
            detailsJob.running = true;
    }

    Connections {
        target: NetworkService
        enabled: root.opened

        function onStateSerialChanged() {
            refreshTimer.restart();
        }
    }

    Timer {
        id: refreshTimer
        interval: 250
        onTriggered: {
            if (root.opened) {
                root.refreshNetworks();
                if (root.page === "details" && !detailsJob.running)
                    detailsJob.running = true;
            }
        }
    }

    // `nmcli -t` separates fields with colons and escapes the ones inside a
    // field with a backslash.
    function splitTerse(line: string): var {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length) {
                cur += line[++i];
            } else if (c === ":") {
                out.push(cur);
                cur = "";
            } else {
                cur += c;
            }
        }
        out.push(cur);
        return out;
    }

    function refresh(): void {
        NetworkService.updateStatus();
        root.refreshNetworks();
    }

    function refreshNetworks(): void {
        NetworkService.requestNetworks();
        if (!profilesJob.running)
            profilesJob.running = true;
    }

    function run(args, failure: string, secret: string): void {
        if (root.busy)
            return;
        root.feedback = "";
        root.failureMessage = failure;
        root.pendingPassword = secret;
        networkJob.stdinEnabled = secret !== "";
        networkJob.command = ["nmcli", "--wait", "25"].concat(args);
        networkJob.running = true;
    }

    function connectNetwork(network): void {
        const saved = root.profiles.find(profile => profile.wifi && profile.name === network.ssid);
        if (saved) {
            root.run(["connection", "up", "uuid", saved.uuid], "Could not activate the saved connection.", "");
        } else if (network.isSecure) {
            root.passwordNetwork = network;
            Qt.callLater(() => passwordInput.focusInput());
        } else {
            root.join(network, "");
        }
    }

    function join(network, password: string): void {
        const target = network.bssid || network.ssid;
        const args = ["device", "wifi", "connect", target];
        root.run(password ? ["--ask"].concat(args) : args, "Could not join the network. Check the password or open Network Connections.", password);
    }

    Process {
        id: profilesJob
        command: ["nmcli", "--terse", "--escape", "yes", "--fields", "NAME,UUID,TYPE,DEVICE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.profiles = text.trim().split("\n").map(line => {
                    const [name, uuid, type, device] = root.splitTerse(line);
                    return { name, uuid, wifi: type === "802-11-wireless" || type === "wifi",
                             vpn: type === "vpn" || type === "wireguard", device: device === "--" ? "" : device };
                }).filter(profile => profile.uuid && (profile.wifi || profile.vpn));
            }
        }
    }

    Process {
        id: detailsJob
        command: ["nmcli", "--terse", "--escape", "yes", "--fields",
                  "GENERAL.DEVICE,GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS", "device", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const connections = [];
                let device = "";
                let connection = null;

                for (const line of text.split("\n")) {
                    const [field, ...parts] = root.splitTerse(line);
                    const value = parts.join(":");
                    if (field === "GENERAL.DEVICE") {
                        device = value;
                        connection = null;
                    } else if (field === "GENERAL.CONNECTION") {
                        if (value && value !== "--" && device !== "lo") {
                            connection = { name: value, device, addresses: [] };
                            connections.push(connection);
                        }
                    } else if (connection && value && value !== "--") {
                        const key = field.split("[")[0];
                        const label = ({
                            "IP4.ADDRESS": "IPv4",
                            "IP6.ADDRESS": "IPv6",
                            "IP4.GATEWAY": "Gateway",
                            "IP4.DNS": "DNS"
                        })[key];
                        if (label)
                            connection.addresses.push({ label, value });
                    }
                }
                root.details = connections;
            }
        }
    }

    Process {
        id: networkJob
        onStarted: {
            if (root.pendingPassword !== "") {
                write(root.pendingPassword + "\n");
                root.pendingPassword = "";
            }
        }
        onExited: code => {
            root.pendingPassword = "";
            if (code !== 0 && root.opened)
                root.feedback = root.failureMessage;
            else if (code === 0)
                root.passwordNetwork = null;
            root.refresh();
        }
    }

    ColumnLayout {
        id: contentColumn
        width: parent.width
        spacing: 6

        BarRadioHeader {
            title: "Wi-Fi"
            glyph: NetworkService.wifiEnabled ? NetworkService.wifiIconForStrength(NetworkService.networkStrength) : Icons.wifiOff
            checked: NetworkService.wifiEnabled
            subtitle: {
                if (!checked)
                    return "Off";
                if (NetworkService.wifiStatus === "limited")
                    return "Limited connection";
                return root.busy ? "Updating…" : "On";
            }
            leadingActions: [
                NetAction {
                    visible: root.page !== "networks"
                    glyph: Icons.arrowLeft
                    label: "Back to networks"
                    onClicked: root.page = "networks"
                }
            ]

            onToggled: enabled => {
                if (!root.busy)
                    NetworkService.enableWifi(enabled);
            }
        }

        SectionLabel {
            visible: root.feedback !== ""
            text: root.feedback
        }

        Item {
            id: pages
            Layout.fillWidth: true
            implicitHeight: Math.ceil(networksPage.implicitHeight * (1 - root.pageProgress)
                                      + secondaryPage.implicitHeight * root.pageProgress)
            clip: true

            ColumnLayout {
                id: networksPage
                x: -Math.round(pages.width * root.pageProgress)
                width: pages.width
                spacing: 6
                visible: root.pageProgress < 1
                enabled: root.page === "networks"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    SectionLabel {
                        text: NetworkService.active ? "Connected" : "Networks"
                    }

                    NetAction {
                        visible: NetworkService.wifiStatus === "limited"
                        glyph: Icons.globe
                        label: "Open network sign-in page"
                        onClicked: NetworkService.openPublicWifiPortal()
                    }
                    NetAction {
                        glyph: Icons.list
                        label: "Saved networks and VPN"
                        onClicked: {
                            root.refresh();
                            root.page = "saved";
                        }
                    }
                    NetAction {
                        glyph: Icons.popOpen
                        label: "Open Network Connections"
                        onClicked: root.settingsRequested()
                    }
                }

                NetRow {
                    visible: NetworkService.active !== null
                    glyph: NetworkService.wifiIconForStrength(NetworkService.networkStrength)
                    title: NetworkService.networkName
                    subtitle: `Connected · ${NetworkService.networkStrength}%`
                    selected: true
                    actionable: !root.busy
                    showInfo: true
                    onInfoRequested: root.page = "details"
                    onClicked: {
                        if (root.activeWifi)
                            root.run(["connection", "down", "uuid", root.activeWifi.uuid], "Could not disconnect Wi-Fi.", "");
                        else
                            NetworkService.disconnectWifiNetwork();
                    }
                    onContextClicked: root.page = "details"
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: NetworkService.wifiEnabled

                    SectionLabel { text: "Available" }

                    NetAction {
                        glyph: Icons.sync
                        label: "Rescan Wi-Fi"
                        hoverOnly: true
                        enabled: !root.busy
                        onClicked: root.run(["device", "wifi", "rescan"], "Could not rescan Wi-Fi.", "")
                    }
                }
                Repeater {
                    model: NetworkService.wifiEnabled ? root.available : []
                    delegate: NetRow {
                        required property var modelData
                        glyph: NetworkService.wifiIconForStrength(modelData?.strength ?? 0)
                        title: modelData?.ssid ?? ""
                        subtitle: modelData ? `${modelData.isSecure ? modelData.security : "Open"} · ${modelData.strength}%` : ""
                        trailing: modelData?.isSecure ? Icons.lock : ""
                        enabled: modelData !== null && !root.busy
                        onClicked: root.connectNetwork(modelData)
                    }
                }

                SearchInput {
                    id: passwordInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    visible: root.passwordNetwork !== null
                    placeholderText: root.passwordNetwork ? `Password for ${root.passwordNetwork.ssid}` : ""
                    passwordMode: true
                    enabled: !root.busy
                    onAccepted: {
                        if (!root.passwordNetwork || !text)
                            return;
                        root.join(root.passwordNetwork, text);
                        clear();
                    }
                    onEscapePressed: {
                        root.passwordNetwork = null;
                        clear();
                    }
                    onVisibleChanged: {
                        if (visible)
                            Qt.callLater(() => root.contentY = Math.max(0, root.contentHeight - root.height));
                    }
                }

                SectionLabel {
                    visible: NetworkService.wifiEnabled && root.available.length === 0
                    text: "No nearby Wi-Fi networks"
                }
            }

            ColumnLayout {
                id: secondaryPage
                x: Math.round(pages.width * (1 - root.pageProgress))
                width: pages.width
                spacing: 6
                visible: root.pageProgress > 0
                enabled: root.page !== "networks"

                SectionLabel {
                    visible: root.subpage === "saved"
                    text: root.forgetUuid ? "Click the same network again to forget it" : "Saved networks and VPN"
                }
                Repeater {
                    model: root.subpage === "saved" ? root.profiles : []
                    delegate: NetRow {
                        required property var modelData
                        glyph: modelData.vpn ? Icons.lock : Icons.wifiHigh
                        title: modelData.name
                        subtitle: root.forgetUuid === modelData.uuid ? "Click to forget" :
                            modelData.device ? "Connected" : modelData.vpn ? "VPN" : "Saved · right-click to forget"
                        trailing: root.forgetUuid === modelData.uuid ? Icons.trash : ""
                        selected: !!modelData.device
                        enabled: !root.busy
                        onContextClicked: {
                            if (!modelData.device && modelData.wifi)
                                root.forgetUuid = root.forgetUuid === modelData.uuid ? "" : modelData.uuid;
                        }
                        onClicked: {
                            if (root.forgetUuid === modelData.uuid) {
                                root.forgetUuid = "";
                                root.run(["connection", "delete", "uuid", modelData.uuid], "Could not forget the saved network.", "");
                            } else {
                                root.forgetUuid = "";
                                root.run(["connection", modelData.device ? "down" : "up", "uuid", modelData.uuid], "Could not change the saved connection.", "");
                            }
                        }
                    }
                }
                SectionLabel {
                    visible: root.subpage === "saved" && root.profiles.length === 0
                    text: "No saved connections"
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.leftMargin: 4
                    visible: root.subpage === "details"
                    text: "Connection details"
                    font.family: Styling.defaultFont
                    font.pixelSize: Math.max(18, Styling.fontSize(3))
                    font.weight: Font.DemiBold
                    color: Colors.overBackground
                }

                Repeater {
                    model: root.subpage === "details" ? root.details : []

                    delegate: ColumnLayout {
                        id: connectionDetails
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: Colors.outlineVariant
                        }

                        Text {
                            Layout.fillWidth: true
                            text: connectionDetails.modelData.name
                            textFormat: Text.PlainText
                            font.family: Styling.defaultFont
                            font.pixelSize: Math.max(16, Styling.fontSize(1))
                            font.weight: Font.DemiBold
                            color: Colors.overBackground
                            wrapMode: Text.Wrap
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 7

                            DetailLine {
                                label: "Interface"
                                value: connectionDetails.modelData.device
                            }

                            Repeater {
                                model: connectionDetails.modelData.addresses
                                delegate: DetailLine {
                                    required property var modelData
                                    label: modelData.label
                                    value: modelData.value
                                }
                            }
                        }
                    }
                }
                SectionLabel {
                    visible: root.subpage === "details" && !detailsJob.running && root.details.length === 0
                    text: "No active connections"
                }
            }
        }
    }

    component DetailLine: RowLayout {
        id: line
        required property string label
        required property string value
        Layout.fillWidth: true
        spacing: 12

        Text {
            Layout.preferredWidth: 74
            Layout.alignment: Qt.AlignTop
            text: line.label
            font.family: Styling.defaultFont
            font.pixelSize: Math.max(13, Styling.fontSize(0))
            font.weight: Font.Medium
            color: Colors.overSurfaceVariant
        }

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: line.value
            textFormat: Text.PlainText
            font.family: Config.theme.monoFont
            font.pixelSize: Math.max(14, Styling.monoFontSize(0))
            color: Colors.overBackground
            wrapMode: Text.WrapAnywhere
        }
    }

    component SectionLabel: Text {
        Layout.fillWidth: true
        Layout.topMargin: 2
        font.family: Styling.defaultFont
        font.pixelSize: Styling.fontSize(-3)
        font.bold: true
        color: Colors.overSurfaceVariant
        wrapMode: Text.Wrap
    }

    component NetAction: Item {
        id: action
        required property string glyph
        required property string label
        property bool hoverOnly: false
        property bool lightHover: false
        property int glyphSize: 15
        property color glyphColor: actionBg.item
        signal clicked
        Layout.preferredWidth: 30
        Layout.preferredHeight: 30
        opacity: enabled ? 1 : 0.45

        StyledRect {
            id: actionBg
            anchors.fill: parent
            visible: !action.lightHover && (!action.hoverOnly || mouse.containsMouse)
            variant: mouse.containsMouse ? "focus" : "common"
            radius: Math.min(width, height) / 2
            enableShadow: false
            enableBorder: false
        }

        Rectangle {
            anchors.fill: parent
            visible: action.lightHover && mouse.containsMouse
            radius: Math.min(width, height) / 2
            color: Qt.rgba(1, 1, 1, 0.24)
        }

        Text {
            anchors.centerIn: parent
            text: action.glyph
            font.family: Icons.font
            font.pixelSize: action.glyphSize
            color: action.glyphColor
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: action.clicked()
        }
        StyledToolTip {
            show: mouse.containsMouse
            tooltipText: action.label
        }
    }

    component NetRow: StyledRect {
        id: row
        required property string glyph
        required property string title
        required property string subtitle
        property string trailing: ""
        property bool selected: false
        property bool actionable: true
        property bool showInfo: false
        signal infoRequested
        signal clicked
        signal contextClicked

        Layout.fillWidth: true
        Layout.preferredHeight: 44
        radius: Styling.radius(0)
        variant: selected ? "primary" : (rowMouse.containsMouse ? "focus" : "common")
        enableShadow: false

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            enabled: row.actionable
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: event => {
                if (event.button === Qt.RightButton)
                    row.contextClicked();
                else
                    row.clicked();
            }
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10
            Text {
                visible: row.glyph !== ""
                text: row.glyph
                font.family: Icons.font
                font.pixelSize: 18
                color: row.selected ? row.item : Colors.overBackground
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: row.title
                    font.family: Styling.defaultFont
                    font.pixelSize: Styling.fontSize(-1)
                    font.weight: Font.Medium
                    color: row.selected ? row.item : Colors.overBackground
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: row.subtitle
                    font.family: Styling.defaultFont
                    font.pixelSize: Styling.fontSize(-3)
                    color: row.selected ? row.item : Colors.overSurfaceVariant
                    opacity: 0.8
                    elide: Text.ElideRight
                }
            }
            NetAction {
                visible: row.showInfo
                glyph: Icons.info
                label: "Connection details"
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                glyphSize: 21
                lightHover: true
                glyphColor: row.item
                onClicked: row.infoRequested()
            }
            Text {
                visible: row.trailing !== ""
                text: row.trailing
                font.family: Icons.font
                font.pixelSize: 16
                color: row.item
            }
        }
    }
}
