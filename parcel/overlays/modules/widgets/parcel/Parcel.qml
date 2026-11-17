pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.modules.services
import "."

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
    WlrLayershell.namespace: "ambxst:parcel"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    readonly property var screenVisibilities: Visibilities.getForScreen(screen.name)
    readonly property bool open: screenVisibilities?.parcel ?? false
    readonly property var service: ParcelService
    readonly property bool attentive: open && card.Window.active
    onAttentiveChanged: service.setViewAttention(screen.name, attentive)
    Component.onCompleted: service.setViewAttention(screen.name, attentive)
    Component.onDestruction: service.removeViewAttention(screen.name)
    visible: open
    property string filter: "all"
    property int selectedIndex: 0
    property string selectedName: ""
    property bool stopConfirmation: false
    readonly property var currentPackage: filteredRows[selectedIndex] ?? filteredRows[0] ?? null
    property bool showLogs: false
    property bool showDetails: false
    property string detailsPackageName: ""
    property var activeAction: null
    readonly property var metadata: service.packageMetadata
    readonly property var updateRows: service.results.filter(pkg => !!service.updates[pkg.name])
    readonly property var aurRows: service.results.filter(pkg => pkg.repo === "aur")
    readonly property var filteredRows: filter === "updates" ? updateRows : filter === "aur" ? aurRows : service.results
    readonly property var activity: parseActivity(service.phase, service.progress)

    function closeDeck() {
        Visibilities.setActiveModule("");
    }
    function handleEscape() {
        if (helperPopup.opened) {
            helperPopup.close();
            searchField.forceActiveFocus();
        } else if (stopConfirmation)
            stopConfirmation = false;
        else if (showLogs)
            showLogs = false;
        else
            closeDeck();
    }
    function toggleLogs() {
        showLogs = !showLogs;
        if (showLogs)
            showDetails = false;
    }
    function choose(pkg) {
        if (!pkg)
            return;
        selectedName = pkg.name;
        const index = service.results.findIndex(row => row.name === pkg.name);
        if (index >= 0)
            service.selected = index;
    }
    function select(offset) {
        if (!filteredRows.length)
            return;
        root.selectedIndex = (root.selectedIndex + offset + filteredRows.length) % filteredRows.length;
        choose(filteredRows[root.selectedIndex]);
        resultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
    }
    function requestAction(operation, helper, pkg) {
        if (service.busy)
            return;
        helperPopup.close();
        pkg = pkg ?? currentPackage;
        if ((operation === "install" || operation === "remove") && !pkg)
            return;
        if (operation === "remove" && !pkg.installed)
            return;
        activeAction = {
            operation: operation,
            name: operation === "install" || operation === "remove" ? pkg.name : "",
            repo: operation === "install" || operation === "remove" ? pkg.repo : "",
            helper: helper ?? service.preferredHelper
        };
        showLogs = false;
        showDetails = false;
        service.begin(activeAction);
    }
    function enter() {
        if (helperPopup.opened)
            return;
        if (stopConfirmation) {
            confirmStop();
            return;
        }
        if (service.busy)
            return;
        if (filteredRows.length)
            requestAction("install");
        else if (service.query.trim()) {
            filter = "aur";
            service.search();
        }
    }
    function authenticate() {
        const value = passwordField.text;
        passwordField.clear();
        service.respond(value);
    }
    function details(pkg) {
        if (!pkg)
            return;
        const samePackage = detailsPackageName === pkg.name;
        choose(pkg);
        detailsPackageName = pkg.name;
        showDetails = samePackage ? !showDetails : true;
        if (showDetails) {
            showLogs = false;
            service.loadDetails();
        }
    }
    function confirmStop() {
        if (!stopConfirmation || !service.busy)
            return;
        stopConfirmation = false;
        service.cancel();
    }
    function escapeHtml(value) {
        return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
    }
    function highlighted(name) {
        const query = service.query.trim().toLowerCase();
        if (!query)
            return escapeHtml(name);
        const index = name.toLowerCase().indexOf(query);
        if (index < 0)
            return escapeHtml(name);
        return escapeHtml(name.slice(0, index)) + '<b>' + escapeHtml(name.slice(index, index + query.length)) + '</b>' + escapeHtml(name.slice(index + query.length));
    }
    function parseActivity(phase, progress) {
        const waiting = !!service.challenge || !!service.prompt || service.stopRequested;
        return {
            label: service.challenge?.kind === "password" ? "Authentication required" : service.prompt ? "Waiting for your response" : service.stopRequested ? "Stopping at the next safe point…" : phase || "Preparing…",
            progress: waiting ? -1 : progress,
            completed: service.completedPackages,
            total: waiting ? 0 : service.totalPackages,
            mode: waiting ? "loading" : service.progressMode,
            step: waiting ? 0 : service.progressStep
        };
    }
    function source(pkg) {
        const repo = metadata[pkg.name]?.Repository;
        return pkg.repo === "installed" ? (repo || "repo") : pkg.repo;
    }
    onOpenChanged: {
        if (open) {
            showLogs = false;
            showDetails = false;
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
            stopConfirmation = false;
        }
    }
    onFilteredRowsChanged: {
        selectedIndex = Math.max(0, filteredRows.findIndex(pkg => pkg.name === selectedName));
        choose(currentPackage);
    }
    onSelectedIndexChanged: choose(currentPackage)

    component Label: Text {
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: Theme.metaSize
        textFormat: Text.PlainText
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    component Icon: Text {
        property string name
        text: Theme.icon(name)
        font.family: Theme.iconFont
        font.pixelSize: Math.min(width, height)
        color: Theme.muted
        width: 16
        height: 16
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
    }
    component SmallButton: Button {
        id: button
        property string iconName: ""
        property string tip: ""
        property bool trailingIcon: false
        focusPolicy: Qt.NoFocus
        implicitWidth: Math.max(32, contentItem.implicitWidth + 16)
        implicitHeight: 32
        leftPadding: 8
        rightPadding: 8
        topPadding: 4
        bottomPadding: 4
        hoverEnabled: true
        opacity: enabled ? 1 : 0.35
        Accessible.name: tip || text
        ToolTip.visible: hovered && !!tip
        ToolTip.text: tip
        ToolTip.delay: 500
        background: Rectangle {
            radius: button.text ? Theme.chipRadius : width / 2
            color: button.down || button.visualFocus ? Theme.selected : button.hovered ? Theme.hover : "transparent"
            Behavior on color {
                ColorAnimation {
                    duration: Theme.duration
                }
            }
        }
        contentItem: Item {
            implicitWidth: buttonContents.implicitWidth
            implicitHeight: 16
            Row {
                id: buttonContents
                anchors.centerIn: parent
                spacing: 4
                layoutDirection: button.trailingIcon ? Qt.RightToLeft : Qt.LeftToRight
                Icon {
                    visible: !!button.iconName
                    name: button.iconName
                    anchors.verticalCenter: parent.verticalCenter
                }
                Label {
                    visible: !!button.text
                    text: button.text
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
    component ActionButton: Button {
        id: action
        property string iconName
        property string tip
        property string variant: "ghost"
        property bool active: false
        implicitWidth: 36
        implicitHeight: 36
        padding: 8
        focusPolicy: Qt.NoFocus
        hoverEnabled: true
        opacity: enabled ? 1 : 0.35
        Accessible.name: tip
        ToolTip.visible: hovered
        ToolTip.text: tip
        ToolTip.delay: 400
        background: Rectangle {
            radius: Theme.chipRadius
            color: {
                if (action.variant === "primary")
                    return action.down ? Qt.darker(Theme.actionPrimary, 1.12) : action.hovered ? Qt.tint(Theme.actionPrimary, Theme.alpha(Theme.text, 0.12)) : Theme.actionPrimary;
                if (action.variant === "danger")
                    return Theme.alpha(Theme.danger, action.down ? 0.26 : action.hovered ? 0.2 : 0.12);
                if (action.variant === "secondary")
                    return action.down ? Theme.alpha(Theme.text, 0.18) : action.hovered ? Theme.alpha(Theme.text, 0.12) : Theme.secondaryAction;
                return action.down || action.visualFocus ? Theme.selected : action.hovered ? Theme.hover : "transparent";
            }
            Behavior on color {
                ColorAnimation {
                    duration: Theme.duration
                }
            }
        }
        contentItem: Item {
            Icon {
                anchors.centerIn: parent
                width: 18
                height: 18
                name: action.iconName
                color: action.variant === "primary" ? Theme.onActionPrimary : action.variant === "danger" ? Theme.danger : action.active || action.hovered ? Theme.text : Theme.muted
            }
        }
    }
    component Input: TextField {
        implicitHeight: 32
        leftPadding: 8
        rightPadding: 8
        color: Theme.text
        placeholderTextColor: Theme.muted
        font.family: Theme.font
        font.pixelSize: Theme.metaSize
        selectByMouse: true
        background: Rectangle {
            radius: Theme.chipRadius
            color: Theme.subtle
            border.width: 1
            border.color: Theme.border
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        MouseArea {
            anchors.fill: parent
            onClicked: root.closeDeck()
        }
    }
    Rectangle {
        anchors.fill: card
        radius: card.radius
        color: Theme.background
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowBlur: 0.7
            shadowVerticalOffset: 8
            shadowOpacity: 0.7
        }
    }
    Rectangle {
        id: card
        objectName: "card"
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 620)
        readonly property int visibleRows: root.filteredRows.length ? Math.min(root.showLogs || root.showDetails ? 2 : 6, root.filteredRows.length) : 2
        property real listHeight: visibleRows * 42 - 2
        Behavior on listHeight {
            NumberAnimation {
                duration: Theme.duration
                easing.type: Easing.OutCubic
            }
        }
        readonly property real compactHeight: 165 + listHeight + (!service.scanning && service.helpers.length === 0 ? 36 : 0) + (service.challenge?.kind === "password" ? 104 : 0) + (service.prompt && !service.challenge ? 36 : 0) + (root.stopConfirmation && service.busy ? 36 : 0)
        height: Math.min(parent.height - 32, compactHeight + logDrawer.revealHeight + (logDrawer.revealHeight > 0 ? 4 : 0) + detailDrawer.revealHeight + (detailDrawer.revealHeight > 0 ? 4 : 0))
        radius: Theme.radius
        color: Theme.background
        border.width: 1
        border.color: Theme.border
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.unit * 2
            spacing: 4
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                spacing: 8
                Icon {
                    name: "search"
                    opacity: 0.8
                }
                TextField {
                    id: searchField
                    objectName: "searchField"
                    Layout.fillWidth: true
                    implicitHeight: 40
                    padding: 0
                    font.family: Theme.font
                    font.pixelSize: Theme.searchSize
                    color: Theme.text
                    placeholderTextColor: Theme.muted
                    placeholderText: "Search packages…"
                    selectByMouse: true
                    text: service.query
                    onTextEdited: {
                        root.filter = "all";
                        service.query = text;
                    }
                    background: Item {}
                    Keys.onUpPressed: root.select(-1)
                    Keys.onDownPressed: root.select(1)
                    onAccepted: root.enter()
                }
                SmallButton {
                    id: helperPicker
                    objectName: "helperPicker"
                    text: service.helper || "pacman"
                    iconName: "chevron"
                    trailingIcon: true
                    implicitWidth: 80
                    implicitHeight: 32
                    enabled: !service.busy && service.helpers.length > 0
                    tip: "Choose AUR helper"
                    contentItem: Item {
                        implicitWidth: managerLabel.implicitWidth + 24
                        implicitHeight: 16
                        Label {
                            id: managerLabel
                            anchors.left: parent.left
                            anchors.right: managerArrow.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: helperPicker.text
                        }
                        Icon {
                            id: managerArrow
                            name: "chevron"
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    background: Rectangle {
                        radius: Theme.chipRadius
                        color: helperPicker.hovered || helperPopup.opened ? Theme.hover : "transparent"
                    }
                    onClicked: helperPopup.opened ? helperPopup.close() : helperPopup.open()
                    Popup {
                        id: helperPopup
                        objectName: "helperPopup"
                        focus: true
                        property int highlightedIndex: 0
                        function activate(index) {
                            const helper = service.helpers[index];
                            if (!helper)
                                return;
                            service.setHelper(helper);
                            close();
                            searchField.forceActiveFocus();
                        }
                        onOpened: highlightedIndex = Math.max(0, service.helpers.indexOf(service.helper))
                        onClosed: searchField.forceActiveFocus()
                        x: 0
                        y: helperPicker.height + 4
                        width: helperPicker.width
                        padding: 4
                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                        background: Rectangle {
                            color: Theme.background
                            radius: Theme.chipRadius
                            border.width: 1
                            border.color: Theme.border
                        }
                        contentItem: Column {
                            focus: true
                            Keys.onUpPressed: helperPopup.highlightedIndex = (helperPopup.highlightedIndex + service.helpers.length - 1) % service.helpers.length
                            Keys.onDownPressed: helperPopup.highlightedIndex = (helperPopup.highlightedIndex + 1) % service.helpers.length
                            Keys.onReturnPressed: helperPopup.activate(helperPopup.highlightedIndex)
                            Keys.onEnterPressed: helperPopup.activate(helperPopup.highlightedIndex)
                            Repeater {
                                model: service.helpers
                                delegate: SmallButton {
                                    id: helperOption
                                    required property string modelData
                                    required property int index
                                    width: helperPopup.availableWidth
                                    text: modelData
                                    background: Rectangle {
                                        radius: Theme.keyRadius
                                        color: helperOption.hovered || helperPopup.highlightedIndex === helperOption.index ? Theme.selected : "transparent"
                                    }
                                    onClicked: helperPopup.activate(index)
                                }
                            }
                        }
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.border
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: [
                        {
                            key: "all",
                            label: "All",
                            count: service.results.length
                        },
                        {
                            key: "updates",
                            label: "Updates",
                            count: root.updateRows.length
                        },
                        {
                            key: "aur",
                            label: "AUR",
                            count: root.aurRows.length
                        }
                    ]
                    delegate: Button {
                        id: chip
                        required property var modelData
                        readonly property bool active: root.filter === modelData.key
                        implicitWidth: contentItem.implicitWidth + 20
                        implicitHeight: 32
                        focusPolicy: Qt.NoFocus
                        leftPadding: 10
                        rightPadding: 10
                        topPadding: 6
                        bottomPadding: 6
                        hoverEnabled: true
                        onClicked: root.filter = modelData.key
                        background: Rectangle {
                            radius: Theme.chipRadius
                            color: chip.active ? Theme.accentFill : chip.hovered ? Theme.hover : "transparent"
                            Behavior on color {
                                ColorAnimation {
                                    duration: Theme.duration
                                }
                            }
                        }
                        contentItem: Item {
                            implicitWidth: chipContents.implicitWidth
                            implicitHeight: 16
                            Row {
                                id: chipContents
                                anchors.centerIn: parent
                                spacing: 6
                                Label {
                                    text: chip.modelData.label
                                    font.weight: Font.Medium
                                    color: chip.active ? Theme.accent : Theme.muted
                                    Behavior on color {
                                        ColorAnimation {
                                            duration: Theme.duration
                                        }
                                    }
                                }
                                Label {
                                    text: chip.modelData.count
                                    font.weight: Font.Normal
                                    color: chip.active ? Theme.alpha(Theme.accent, 0.8) : Theme.alpha(Theme.muted, 0.8)
                                }
                            }
                        }
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
            }
            RowLayout {
                visible: !service.scanning && service.helpers.length === 0
                Layout.fillWidth: true
                Label {
                    Layout.fillWidth: true
                    text: "Add an AUR helper"
                    color: Theme.muted
                }
                SmallButton {
                    text: "paru"
                    tip: "Install paru"
                    enabled: !service.busy
                    onClicked: root.requestAction("bootstrap", "paru")
                }
                SmallButton {
                    text: "yay"
                    tip: "Install yay"
                    enabled: !service.busy
                    onClicked: root.requestAction("bootstrap", "yay")
                }
            }
            Item {
                id: listArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: -8
                Layout.rightMargin: -8
                Layout.minimumHeight: 40
                Rectangle {
                    id: fadeMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: resultsList.atYBeginning ? "white" : "transparent"
                        }
                        GradientStop {
                            position: Math.min(0.49, 16 / Math.max(1, listArea.height))
                            color: "white"
                        }
                        GradientStop {
                            position: Math.max(0.51, 1 - 16 / Math.max(1, listArea.height))
                            color: "white"
                        }
                        GradientStop {
                            position: 1
                            color: resultsList.atYEnd ? "white" : "transparent"
                        }
                    }
                }
                ListView {
                    id: resultsList
                    objectName: "resultsList"
                    onHeightChanged: Qt.callLater(() => {
                        if (root.selectedIndex >= 0)
                            positionViewAtIndex(root.selectedIndex, ListView.Contain);
                    })
                    anchors.fill: parent
                    clip: true
                    spacing: 2
                    model: root.filteredRows
                    currentIndex: root.selectedIndex
                    boundsBehavior: Flickable.StopAtBounds
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: fadeMask
                        maskThresholdMin: 0
                        maskSpreadAtMin: 1
                    }
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AlwaysOff
                    }
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool selected: root.selectedIndex === index
                        width: resultsList.width
                        height: 40
                        radius: Theme.rowRadius
                        color: selected ? Theme.selected : rowHover.hovered ? Theme.hover : "transparent"
                        Behavior on color {
                            ColorAnimation {
                                duration: 120
                            }
                        }
                        HoverHandler {
                            id: rowHover
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.selectedIndex = row.index;
                                root.choose(row.modelData);
                            }
                            onDoubleClicked: {
                                root.selectedIndex = row.index;
                                root.choose(row.modelData);
                                root.requestAction("install", undefined, row.modelData);
                            }
                        }
                        Rectangle {
                            x: 0
                            y: 8
                            width: 3
                            height: 24
                            radius: 1
                            color: Theme.accent
                            opacity: row.selected ? 1 : 0
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 120
                                }
                            }
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8
                            Label {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 64
                                text: root.highlighted(row.modelData.name)
                                textFormat: Text.RichText
                                font.pixelSize: Theme.nameSize
                                font.weight: Font.Medium
                                ToolTip.visible: rowHover.hovered && truncated && !badgeHover.hovered
                                ToolTip.text: row.modelData.name
                            }
                            Label {
                                Layout.maximumWidth: 88
                                text: row.modelData.version
                                color: Theme.muted
                            }
                            Label {
                                visible: !!service.updates[row.modelData.name]
                                Layout.maximumWidth: 96
                                text: "↑ " + (service.updates[row.modelData.name]?.to ?? "")
                                color: Theme.accent
                                font.pixelSize: Theme.smallSize
                            }
                            Rectangle {
                                id: repositoryBadge
                                objectName: "repoBadge-" + row.index
                                readonly property bool packageInstalled: !!row.modelData.installed
                                readonly property color repositoryTint: Theme.repositoryColor(root.source(row.modelData))
                                implicitWidth: Theme.repositoryBadgeWidth
                                Layout.minimumWidth: implicitWidth
                                Layout.maximumWidth: implicitWidth
                                implicitHeight: 20
                                radius: Theme.keyRadius
                                color: packageInstalled ? Theme.alpha(repositoryTint, 0.14) : Theme.subtle
                                border.width: 0
                                Accessible.name: root.source(row.modelData) + (packageInstalled ? ", installed" : ", not installed")
                                ToolTip.visible: badgeHover.hovered
                                ToolTip.text: (packageInstalled ? "Installed" : "Not installed") + " · " + root.source(row.modelData)
                                ToolTip.delay: 300
                                HoverHandler {
                                    id: badgeHover
                                }
                                Behavior on color {
                                    ColorAnimation {
                                        duration: Theme.duration
                                    }
                                }
                                Label {
                                    id: sourceLabel
                                    anchors.fill: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    text: Theme.repositoryLabel(root.source(row.modelData))
                                    font.pixelSize: Theme.metaSize
                                    font.bold: true
                                    color: repositoryBadge.packageInstalled ? repositoryBadge.repositoryTint : Theme.alpha(Theme.muted, 0.6)
                                }
                            }
                        }
                    }
                }
                Column {
                    anchors.centerIn: parent
                    width: parent.width - 32
                    visible: !root.filteredRows.length
                    spacing: 8
                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: service.searching || service.scanning ? "Searching packages…" : service.query.trim() ? "No packages match '" + service.query + "'" : root.filter === "updates" ? "Everything is up to date" : root.filter === "aur" ? "No AUR packages here" : "No packages found"
                        color: Theme.muted
                    }
                }
            }
            Rectangle {
                id: authenticationPanel
                objectName: "authenticationPanel"
                visible: service.challenge?.kind === "password"
                Layout.fillWidth: true
                Layout.preferredHeight: 100
                radius: Theme.rowRadius
                color: Theme.subtle
                border.width: 1
                border.color: Theme.border
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Icon {
                            name: "key"
                            width: 20
                            height: 20
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Label {
                                Layout.fillWidth: true
                                text: "Authentication required"
                                font.pixelSize: Theme.nameSize
                                font.weight: Font.Medium
                            }
                            Label {
                                Layout.fillWidth: true
                                text: "Package operation paused. Enter your password to continue."
                                color: Theme.muted
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Input {
                            id: passwordField
                            objectName: "passwordField"
                            Layout.fillWidth: true
                            echoMode: TextInput.Password
                            placeholderText: "Enter your password"
                            Accessible.name: service.challenge?.prompt || "Password"
                            onAccepted: root.authenticate()
                        }
                        SmallButton {
                            text: "Authenticate"
                            onClicked: root.authenticate()
                        }
                        SmallButton {
                            iconName: "close"
                            tip: "Cancel authentication"
                            onClicked: {
                                passwordField.clear();
                                service.respond(null);
                            }
                        }
                    }
                }
            }
            RowLayout {
                visible: !!service.prompt && !service.challenge
                Layout.fillWidth: true
                Input {
                    id: replyField
                    objectName: "replyField"
                    Layout.fillWidth: true
                    placeholderText: service.prompt?.prompt || "Response (blank uses default)"
                    onAccepted: {
                        service.respondToPrompt(text);
                        clear();
                    }
                }
                SmallButton {
                    text: "Send"
                    onClicked: {
                        service.respondToPrompt(replyField.text);
                        replyField.clear();
                    }
                }
            }
            Item {
                id: footer
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.border
                }
                Rectangle {
                    id: progressTrack
                    objectName: "progressTrack"
                    width: parent.width
                    height: 5
                    radius: 2.5
                    visible: service.busy || service.searching || service.scanning
                    clip: true
                    color: Theme.subtle
                    readonly property bool unknown: !service.busy || root.activity.progress < 0
                    Rectangle {
                        height: progressTrack.height
                        radius: 2.5
                        width: progressTrack.width * (progressTrack.unknown ? 0.25 : root.activity.progress)
                        color: Theme.accent
                        x: progressTrack.unknown ? -width + sweep * (progressTrack.width + width) : 0
                        property real sweep: 0
                        NumberAnimation on sweep {
                            from: 0
                            to: 1
                            duration: 1000
                            loops: Animation.Infinite
                            running: progressTrack.visible && progressTrack.unknown && root.open && !service.challenge && !service.prompt && !service.stopRequested
                        }
                        Behavior on width {
                            NumberAnimation {
                                duration: Theme.duration
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.topMargin: 8
                    spacing: 8
                    Icon {
                        name: "spinner"
                        visible: service.busy
                        RotationAnimator on rotation {
                            from: 0
                            to: 360
                            duration: 900
                            loops: Animation.Infinite
                            running: service.busy && root.open && !service.challenge && !service.prompt && !service.stopRequested
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        text: service.busy ? (root.activity.step ? root.activity.step + "/4 · " : "") + root.activity.label : service.outcome || (root.filteredRows.length + (root.filteredRows.length === 1 ? " package" : " packages"))
                        color: service.failed ? Theme.error : Theme.muted
                        ToolTip.visible: phaseHover.hovered && (service.busy ? !!service.phaseDetail : !!service.outcome)
                        ToolTip.text: service.busy ? service.phaseDetail : "Dismiss status"
                        HoverHandler {
                            id: phaseHover
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: !service.busy && !!service.outcome
                            onClicked: service.outcome = ""
                        }
                    }
                    Label {
                        objectName: "progressCount"
                        visible: service.busy && root.activity.progress >= 0
                        text: root.activity.mode === "percentage" ? Math.round(root.activity.progress * 100) + "%" : root.activity.completed + "/" + root.activity.total
                        color: Theme.muted
                    }
                    ActionButton {
                        objectName: "detailsButton"
                        iconName: "info"
                        tip: "Package details · Ctrl+I"
                        active: root.showDetails
                        enabled: !!root.currentPackage
                        onClicked: root.details(root.currentPackage)
                    }
                    ActionButton {
                        objectName: "logsButton"
                        iconName: "log"
                        tip: "Activity log · Ctrl+L"
                        active: root.showLogs
                        onClicked: root.toggleLogs()
                    }
                    ActionButton {
                        objectName: "syncAllButton"
                        visible: !service.busy
                        iconName: "sync"
                        variant: "secondary"
                        tip: "Sync all packages · Ctrl+U"
                        onClicked: root.requestAction("upgrade")
                    }
                    ActionButton {
                        objectName: "uninstallButton"
                        visible: !service.busy && !!root.currentPackage?.installed
                        iconName: "uninstall"
                        variant: "danger"
                        tip: "Uninstall " + (root.currentPackage?.name ?? "package") + " · Ctrl+D"
                        onClicked: root.requestAction("remove")
                    }
                    ActionButton {
                        objectName: "installButton"
                        visible: !service.busy
                        iconName: "install"
                        variant: "primary"
                        enabled: !!root.currentPackage
                        tip: (root.currentPackage?.installed ? "Reinstall " : "Install ") + (root.currentPackage?.name ?? "package") + " · Enter"
                        onClicked: root.requestAction("install")
                    }
                    ActionButton {
                        objectName: "stopButton"
                        visible: service.busy
                        iconName: "stop"
                        variant: "secondary"
                        enabled: !service.stopRequested
                        tip: service.stopRequested ? "Waiting for a safe point to stop" : "Stop current operation"
                        onClicked: root.stopConfirmation = true
                    }
                }
            }
            RowLayout {
                visible: root.stopConfirmation && service.busy
                Layout.fillWidth: true
                Label {
                    Layout.fillWidth: true
                    text: service.cancellable ? "Stop the current download or build?" : "Stop after the current package changes finish?"
                }
                SmallButton {
                    text: "Keep running"
                    objectName: "keepRunningButton"
                    onClicked: root.stopConfirmation = false
                }
                SmallButton {
                    text: "Stop"
                    objectName: "confirmStopButton"
                    onClicked: root.confirmStop()
                }
            }
            Item {
                id: logDrawer
                objectName: "logDrawer"
                Layout.fillWidth: true
                Layout.minimumHeight: 0
                property real revealHeight: root.showLogs ? Math.min(340, Math.max(96, root.height - card.compactHeight - 48)) : 0
                Layout.maximumHeight: revealHeight
                Layout.preferredHeight: revealHeight
                visible: root.showLogs || revealHeight > 0
                clip: true
                Behavior on revealHeight {
                    NumberAnimation {
                        duration: Theme.duration
                        easing.type: Easing.OutCubic
                    }
                }
                ActivityLog {
                    id: activityLog
                    objectName: "activityLog"
                    anchors.fill: parent
                    logs: service.logs
                    transaction: service.activityTransaction
                }
            }
            Item {
                id: detailDrawer
                Layout.fillWidth: true
                Layout.minimumHeight: 0
                property real revealHeight: root.showDetails ? Math.min(340, Math.max(120, root.height - card.compactHeight - 48)) : 0
                Layout.maximumHeight: revealHeight
                Layout.preferredHeight: revealHeight
                visible: root.showDetails || revealHeight > 0
                clip: true
                Behavior on revealHeight {
                    NumberAnimation {
                        duration: Theme.duration
                        easing.type: Easing.OutCubic
                    }
                }
                PackageInfo {
                    objectName: "packageInfo"
                    anchors.fill: parent
                    pkg: root.currentPackage
                    details: service.details.Name === root.currentPackage?.name ? service.details : service.packageMetadata[root.currentPackage?.name] ?? ({})
                    error: service.selectedPackage?.name === root.currentPackage?.name ? service.detailsError : ""
                }
            }
        }
    }
    Connections {
        target: service
        function onBusyChanged() {
            root.stopConfirmation = false;
            if (service.busy)
                root.showLogs = false;
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
            if (service.prompt && !service.challenge)
                Qt.callLater(() => {
                    if (root.open)
                        replyField.forceActiveFocus();
                });
        }
    }
    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: root.open && !service.challenge && !service.prompt && !helperPopup.opened
        onActivated: root.enter()
    }
    Shortcut {
        sequence: "Escape"
        enabled: root.open
        onActivated: root.handleEscape()
    }
    Shortcut {
        sequence: "Ctrl+L"
        enabled: root.open
        onActivated: root.toggleLogs()
    }
    Shortcut {
        sequence: "Ctrl+U"
        enabled: root.open && !service.busy
        onActivated: root.requestAction("upgrade")
    }
    Shortcut {
        sequence: "Ctrl+D"
        enabled: root.open && !service.busy && !passwordField.activeFocus && !replyField.activeFocus
        onActivated: root.requestAction("remove")
    }
    Shortcut {
        sequence: "Ctrl+I"
        enabled: root.open && !!root.currentPackage && !passwordField.activeFocus && !replyField.activeFocus
        onActivated: root.details(root.currentPackage)
    }
}
