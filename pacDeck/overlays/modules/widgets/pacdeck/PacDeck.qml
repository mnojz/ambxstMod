pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.modules.theme
import qs.modules.services

PanelWindow {
    id: root
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ambxst:pacdeck"
    WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    readonly property var screenVisibilities: Visibilities.getForScreen(screen.name)
    readonly property bool open: screenVisibilities?.pacDeck ?? false
    readonly property var service: PacDeckService
    visible: open
    property bool showDetails: false
    property bool showLogs: false
    property var pendingAction: null
    readonly property bool dialogOpen: !!pendingAction || !!service.challenge

    function alpha(color, opacity) {
        return Qt.rgba(color.r, color.g, color.b, opacity);
    }
    function closeDeck() {
        pendingAction = null;
        Visibilities.setActiveModule("");
    }
    function select(offset) {
        if (service.results.length)
            service.selected = (service.selected + offset + service.results.length) % service.results.length;
        resultsList.positionViewAtIndex(service.selected, ListView.Contain);
    }
    function requestAction(operation, helper) {
        if (service.busy || dialogOpen)
            return;
        const pkg = service.selectedPackage;
        if ((operation === "install" || operation === "remove") && !pkg)
            return;
        if (operation === "remove" && !pkg.installed)
            return;
        pendingAction = {
            operation: operation,
            name: pkg?.name ?? "",
            repo: pkg?.repo ?? "",
            helper: helper ?? service.preferredHelper
        };
    }
    function acceptDialog() {
        if (service.challenge) {
            const value = service.challenge.kind === "password" ? passwordField.text : true;
            passwordField.clear();
            service.respond(value);
        } else if (pendingAction) {
            const action = pendingAction;
            pendingAction = null;
            if (action.operation === "stop")
                service.cancel();
            else
                service.begin(action);
        }
    }
    function cancelDialog() {
        passwordField.clear();
        if (service.challenge)
            service.respond(null);
        pendingAction = null;
    }
    onOpenChanged: {
        if (open) {
            service.refresh();
            Qt.callLater(() => {
                if (service.challenge?.kind === "password")
                    passwordField.forceActiveFocus();
                else if (service.prompt)
                    replyField.forceActiveFocus();
                else
                    searchField.forceActiveFocus();
            });
        } else {
            passwordField.clear();
            pendingAction = null;
        }
    }

    component DeckField: TextField {
        id: field
        implicitHeight: 38
        leftPadding: 12
        rightPadding: 12
        topPadding: 8
        bottomPadding: 8
        color: Colors.overBackground
        placeholderTextColor: root.alpha(Colors.overBackground, 0.5)
        font.family: Styling.defaultFont
        font.pixelSize: Styling.fontSize(-1)
        selectByMouse: true
        background: Rectangle {
            radius: 8
            color: root.alpha(Colors.overBackground, 0.05)
            border.width: field.activeFocus ? 1 : 0
            border.color: Colors.primary
        }
    }

    component DeckButton: Button {
        id: control
        implicitWidth: Math.max(36, implicitContentWidth + leftPadding + rightPadding)
        implicitHeight: Math.max(34, implicitContentHeight + topPadding + bottomPadding)
        leftPadding: 12
        rightPadding: 12
        topPadding: 7
        bottomPadding: 7
        font.family: Styling.defaultFont
        font.pixelSize: Styling.fontSize(-1)
        hoverEnabled: true
        background: Rectangle {
            radius: 7
            color: control.down ? Colors.primary : root.alpha(Colors.overBackground, control.hovered || control.visualFocus ? 0.13 : 0.06)
            border.width: 1
            border.color: control.visualFocus ? Colors.primary : root.alpha(Colors.outline, control.hovered ? 0.5 : 0.22)
            opacity: control.enabled ? 1 : 0.4
        }
        contentItem: Text {
            text: control.text
            color: control.down ? Colors.background : Colors.overBackground
            font: control.font
            opacity: control.enabled ? 1 : 0.45
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }
    component DeckLabel: Text {
        color: Colors.overBackground
        font.family: Styling.defaultFont
        font.pixelSize: Styling.fontSize(-1)
        textFormat: Text.PlainText
    }

    component DeckProgress: ProgressBar {
        id: bar
        readonly property bool unknown: indeterminate || value <= 0
        implicitHeight: 8
        padding: 0
        background: Rectangle {
            radius: 4
            color: root.alpha(Colors.primary, 0.12)
        }
        contentItem: Item {
            Rectangle {
                width: parent.width * (bar.unknown ? 1 : bar.visualPosition)
                height: parent.height
                radius: 4
                color: root.alpha(Colors.primary, bar.unknown ? 0.12 : 0.6)
                clip: true
                Behavior on width {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                }
                Item {
                    anchors.fill: parent
                    property real dashOffset: 0
                    Row {
                        x: parent.dashOffset - 24
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        Repeater {
                            model: Math.ceil(bar.availableWidth / 24) + 2
                            Rectangle {
                                width: 14
                                height: 4
                                radius: 2
                                color: Colors.primary
                            }
                        }
                    }
                    NumberAnimation on dashOffset {
                        from: 0
                        to: 24
                        duration: 700
                        loops: Animation.Infinite
                        running: bar.visible && root.open
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.alpha(Colors.scrim, 0.45)
        MouseArea {
            anchors.fill: parent
            onClicked: root.closeDeck()
        }
    }
    Rectangle {
        id: card
        readonly property int expandedPanels: (root.showDetails ? 1 : 0) + (root.showLogs && (service.busy || service.outcome) ? 1 : 0)
        readonly property real expandedPanelHeight: Math.max(60, Math.min(180, (height - (service.busy || service.outcome ? 390 : 330) - (service.prompt ? 75 : 0)) / Math.max(1, expandedPanels)))
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 660)
        height: Math.min(parent.height - 48, root.dialogOpen && service.challenge?.kind !== "review" ? 245 : 480 + (service.busy || service.outcome ? 130 : 0))
        radius: 16
        color: Colors.background
        border.width: 1
        border.color: root.alpha(Colors.outline, 0.5)
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10
            visible: !root.dialogOpen
            enabled: !root.dialogOpen
            RowLayout {
                Layout.fillWidth: true
                DeckLabel {
                    text: "pacDeck"
                    font.bold: true
                    font.pixelSize: Styling.fontSize(2)
                }
                Item {
                    Layout.fillWidth: true
                }
                DeckLabel {
                    text: service.helper ? "Using " + service.helper : "Official repositories"
                    opacity: 0.6
                }
                ComboBox {
                    id: helperPicker
                    visible: service.helpers.length > 1
                    model: service.helpers
                    currentIndex: Math.max(0, service.helpers.indexOf(service.helper))
                    implicitWidth: 90
                    implicitHeight: 34
                    leftPadding: 12
                    rightPadding: 30
                    topPadding: 7
                    bottomPadding: 7
                    font.family: Styling.defaultFont
                    font.pixelSize: Styling.fontSize(-1)
                    popup.width: helperPicker.width
                    popup.x: 0
                    delegate: ItemDelegate {
                        required property string modelData
                        required property int index
                        width: helperPicker.popup.availableWidth
                        text: modelData
                        leftPadding: 12
                        rightPadding: 12
                        topPadding: 8
                        bottomPadding: 8
                        font: helperPicker.font
                        highlighted: helperPicker.highlightedIndex === index
                    }
                    enabled: !service.busy
                    onActivated: index => service.setHelper(service.helpers[index])
                }
                DeckButton {
                    text: "Upgrade all"
                    enabled: !service.busy
                    onClicked: root.requestAction("upgrade")
                }
            }
            DeckField {
                id: searchField
                Layout.fillWidth: true
                implicitHeight: 40
                placeholderText: "Search packages…"
                text: service.query
                onTextEdited: service.query = text
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(1)
                color: Colors.overBackground
                placeholderTextColor: root.alpha(Colors.overBackground, 0.5)
                selectByMouse: true
                background: Rectangle {
                    radius: 9
                    color: root.alpha(Colors.overBackground, 0.05)
                    border.width: searchField.activeFocus ? 1 : 0
                    border.color: Colors.primary
                }
                Keys.onUpPressed: root.select(-1)
                Keys.onDownPressed: root.select(1)
                Keys.onReturnPressed: root.requestAction("install")
                Keys.onEnterPressed: root.requestAction("install")
                Keys.onEscapePressed: root.closeDeck()
                Keys.onPressed: event => {
                    if (event.modifiers & Qt.ControlModifier) {
                        if (event.key === Qt.Key_D) {
                            root.requestAction("remove");
                            event.accepted = true;
                        } else if (event.key === Qt.Key_U) {
                            root.requestAction("upgrade");
                            event.accepted = true;
                        }
                    }
                }
            }
            RowLayout {
                visible: !service.scanning && service.helpers.length === 0
                Layout.fillWidth: true
                DeckLabel {
                    Layout.fillWidth: true
                    text: "Add an AUR helper to search and build AUR packages."
                    wrapMode: Text.WordWrap
                }
                DeckButton {
                    text: "Install paru"
                    enabled: !service.busy
                    onClicked: root.requestAction("bootstrap", "paru")
                }
                DeckButton {
                    text: "Install yay"
                    enabled: !service.busy
                    onClicked: root.requestAction("bootstrap", "yay")
                }
            }
            RowLayout {
                Layout.fillWidth: true
                DeckLabel {
                    Layout.fillWidth: true
                    text: service.searching ? "Searching…" : service.status
                    opacity: 0.6
                    elide: Text.ElideRight
                }
                DeckButton {
                    text: "Refresh"
                    enabled: !service.busy && !service.scanning
                    onClicked: service.refresh()
                }
            }
            DeckProgress {
                Layout.fillWidth: true
                visible: service.searching || service.scanning
                indeterminate: true
            }
            ListView {
                id: resultsList
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 70
                clip: true
                spacing: 3
                model: service.results
                currentIndex: service.selected
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AlwaysOff
                }
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool selected: service.selected === index
                    width: resultsList.width
                    height: 48
                    radius: 8
                    color: row.selected ? root.alpha(Colors.primary, 0.13) : (rowMouse.containsMouse ? root.alpha(Colors.overBackground, 0.04) : "transparent")
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            DeckLabel {
                                Layout.fillWidth: true
                                text: row.modelData.name
                                font.bold: row.selected
                                elide: Text.ElideRight
                            }
                            DeckLabel {
                                Layout.fillWidth: true
                                text: row.modelData.description || (row.modelData.repo + " · " + row.modelData.version)
                                opacity: 0.55
                                font.pixelSize: Styling.fontSize(-2)
                                elide: Text.ElideRight
                            }
                        }
                        DeckLabel {
                            text: service.updates[row.modelData.name] ? "↑ " + service.updates[row.modelData.name].to : row.modelData.installed ? "Installed" : row.modelData.repo
                            color: row.modelData.installed ? Colors.primary : Colors.overBackground
                            opacity: 0.8
                        }
                    }
                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: service.selected = row.index
                        onDoubleClicked: {
                            service.selected = row.index;
                            root.requestAction("install");
                        }
                    }
                }
                DeckLabel {
                    anchors.centerIn: parent
                    visible: !service.searching && service.results.length === 0
                    text: service.scanning ? "Reading packages…" : "No packages found"
                    opacity: 0.5
                }
            }
            RowLayout {
                Layout.fillWidth: true
                DeckButton {
                    text: root.showDetails ? "Hide details" : "Details"
                    enabled: !!service.selectedPackage
                    onClicked: root.showDetails = !root.showDetails
                }
                Item {
                    Layout.fillWidth: true
                }
                DeckButton {
                    text: "Remove"
                    visible: !!service.selectedPackage?.installed
                    enabled: !service.busy
                    onClicked: root.requestAction("remove")
                }
                DeckButton {
                    text: service.selectedPackage?.installed ? "Reinstall" : "Install"
                    enabled: !!service.selectedPackage && !service.busy
                    onClicked: root.requestAction("install")
                }
            }
            DeckLabel {
                Layout.fillWidth: true
                Layout.topMargin: 2
                text: "↑/↓ select  ·  Enter install  ·  Ctrl+D remove  ·  Ctrl+U upgrade  ·  Esc close"
                font.pixelSize: Styling.fontSize(-2)
                opacity: 0.55
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
            ScrollView {
                ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                visible: root.showDetails
                Layout.fillWidth: true
                Layout.preferredHeight: card.expandedPanelHeight
                clip: true
                contentWidth: availableWidth
                TextArea {
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    color: Colors.overBackground
                    font.family: Styling.defaultFont
                    font.pixelSize: Styling.fontSize(-1)
                    textFormat: TextEdit.PlainText
                    text: Object.keys(service.details).length ? Object.keys(service.details).map(key => key + ": " + service.details[key]).join("\n") : "Loading package details…"
                    background: Rectangle {
                        color: root.alpha(Colors.overBackground, 0.03)
                        radius: 8
                    }
                }
            }
            ColumnLayout {
                visible: service.busy || !!service.outcome
                Layout.fillWidth: true
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    DeckLabel {
                        Layout.fillWidth: true
                        text: service.busy ? service.phase : service.outcome
                        color: service.failed ? Colors.red : Colors.overBackground
                        wrapMode: Text.WordWrap
                    }
                    DeckButton {
                        text: root.showLogs ? "Hide log" : "Activity log"
                        onClicked: root.showLogs = !root.showLogs
                    }
                    DeckButton {
                        visible: service.busy
                        text: service.stopRequested ? "Stop requested" : "Stop"
                        enabled: !service.stopRequested
                        onClicked: root.pendingAction = {
                            operation: "stop"
                        }
                    }
                    DeckButton {
                        visible: !service.busy
                        text: "Dismiss"
                        onClicked: {
                            service.outcome = "";
                            root.showLogs = false;
                        }
                    }
                }
                DeckProgress {
                    Layout.fillWidth: true
                    visible: service.busy
                    indeterminate: service.progress < 0
                    value: Math.max(0, service.progress)
                }
                ScrollView {
                    id: logView
                    ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    visible: root.showLogs
                    Layout.fillWidth: true
                    Layout.preferredHeight: card.expandedPanelHeight
                    clip: true
                    TextArea {
                        text: service.logs
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.Wrap
                        color: Colors.overBackground
                        font.family: "monospace"
                        font.pixelSize: Styling.fontSize(-2)
                        textFormat: TextEdit.PlainText
                        background: Rectangle {
                            color: root.alpha(Colors.overBackground, 0.04)
                            radius: 6
                        }
                        onTextChanged: cursorPosition = length
                    }
                }
                ColumnLayout {
                    visible: !!service.prompt && !service.challenge
                    Layout.fillWidth: true
                    DeckLabel {
                        Layout.fillWidth: true
                        text: service.prompt?.prompt ?? ""
                        wrapMode: Text.WordWrap
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        DeckField {
                            id: replyField
                            Layout.fillWidth: true
                            placeholderText: "Response (leave blank for the default)"
                            onAccepted: {
                                service.respondToPrompt(text);
                                clear();
                            }
                        }
                        DeckButton {
                            text: "Send"
                            onClicked: {
                                service.respondToPrompt(replyField.text);
                                replyField.clear();
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: card.radius
            color: Colors.background
            visible: root.dialogOpen
            z: 5
            MouseArea {
                anchors.fill: parent
            }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 22
                spacing: 12
                DeckLabel {
                    Layout.fillWidth: true
                    font.pixelSize: Styling.fontSize(2)
                    font.bold: true
                    text: service.challenge ? (service.challenge.kind === "password" ? "Authentication" : "Review build files") : root.pendingAction?.operation === "stop" ? "Stop this operation?" : root.pendingAction?.operation === "bootstrap" ? "Install an AUR helper" : "Confirm " + (root.pendingAction?.operation ?? "transaction")
                }
                DeckLabel {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: service.challenge ? service.challenge.prompt : root.pendingAction?.operation === "stop" ? (service.cancellable ? "Stop the current download or build?" : "Package changes are in progress. Stopping will wait until a safe point.") : root.pendingAction?.operation === "bootstrap" ? "Install build tools, review the build files, then build and install " + root.pendingAction.helper + "." : root.pendingAction?.operation === "upgrade" ? "Upgrade repository and available AUR packages?" : (root.pendingAction?.operation ?? "") + " " + (root.pendingAction?.name ?? "") + "? Package tools will use their default options."
                }
                DeckField {
                    id: passwordField
                    visible: service.challenge?.kind === "password"
                    Layout.fillWidth: true
                    echoMode: TextInput.Password
                    placeholderText: "Password"
                    onAccepted: root.acceptDialog()
                }
                ScrollView {
                    ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    visible: service.challenge?.kind === "review"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    TextArea {
                        text: service.challenge?.content ?? ""
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.Wrap
                        color: Colors.overBackground
                        font.family: "monospace"
                        textFormat: TextEdit.PlainText
                    }
                }
                Item {
                    Layout.fillHeight: true
                    visible: service.challenge?.kind !== "review"
                }
                RowLayout {
                    Layout.fillWidth: true
                    Item {
                        Layout.fillWidth: true
                    }
                    DeckButton {
                        text: root.pendingAction?.operation === "stop" ? "Keep running" : "Cancel"
                        onClicked: root.cancelDialog()
                    }
                    DeckButton {
                        text: service.challenge?.kind === "password" ? "Authenticate" : root.pendingAction?.operation === "stop" ? "Stop" : "Continue"
                        onClicked: root.acceptDialog()
                    }
                }
            }
        }
    }
    Connections {
        target: service
        function onBusyChanged() {
            if (!service.busy && root.pendingAction?.operation === "stop")
                root.pendingAction = null;
        }
        function onChallengeChanged() {
            passwordField.clear();
            if (service.challenge?.kind === "password")
                Qt.callLater(() => {
                    if (root.open)
                        passwordField.forceActiveFocus();
                });
        }
        function onPromptChanged() {
            replyField.clear();
            if (service.prompt && !service.challenge) {
                root.showLogs = true;
                Qt.callLater(() => {
                    if (root.open)
                        replyField.forceActiveFocus();
                });
            }
        }
    }
    Shortcut {
        sequence: "Escape"
        enabled: root.open
        onActivated: {
            if (root.dialogOpen)
                root.cancelDialog();
            else
                root.closeDeck();
        }
    }
}
