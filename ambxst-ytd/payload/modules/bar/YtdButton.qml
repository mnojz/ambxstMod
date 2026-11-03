pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.config

import Quickshell.Widgets
import qs.modules.components
import qs.modules.services
import qs.modules.theme
import "../services/YtdUrl.js" as YtdUrl

Item {
    id: root
    required property var bar
    property bool vertical: bar.orientation === "vertical"
    property bool layerEnabled: true
    property real startRadius: Styling.radius(0)
    property real endRadius: Styling.radius(0)
    // The button only shows its active look while the popup is genuinely on
    // screen. BarPopup can be left with isOpen=true and visible=false, because
    // close() returns early when the surface is already hidden; keying the
    // appearance off isOpen alone would then pin the button to the active
    // styling with no popup visible.
    readonly property bool popupOpen: popup.isOpen && popup.visible
    readonly property bool barActive: popupOpen
    readonly property bool activeCardVisible: YtdService.state === "starting"
        || YtdService.state === "downloading" || YtdService.state === "error"
        || YtdService.state === "cancelled"
    // History is part of the same scrolling page as the active card, so both
    // sections are laid out together instead of nesting a second scroller.
    readonly property bool historyVisible: YtdService.history.length > 0
    // These roles are resolved by the shell theme rather than fixed RGB values.
    // Active: the deepest background role, because the primary button's own "on"
    // role (overPrimary) is a lighter blue-grey and does not read as dark
    // enough against the light surface.
    // Idle: the primary accent, so the glyph matches the other themed icons
    // instead of the near-white overBackground role.
    readonly property color activeContentColor: Colors.background
    readonly property color idleContentColor: Colors.primary
    readonly property color barContentColor: barActive ? activeContentColor : idleContentColor
    readonly property color barTrackColor: Colors.background
    readonly property color barProgressColor: Colors.overBackground

    // Display labels for the values in YtdService.formats.
    readonly property var formatOptions: [
        { label: "MP3", value: "mp3" },
        { label: "480p", value: "480p" },
        { label: "720p", value: "720p" },
        { label: "1080p", value: "1080p" },
        { label: "1440p", value: "1440p" },
        { label: "2160p", value: "2160p" }
    ]

    // Only a real YouTube/YouTube Music link can be downloaded, so the field
    // is checked live and the download button stays disabled otherwise. A
    // playlist link also needs the Whole playlist option in single mode.
    readonly property bool urlFilled: urlField.text.trim() !== ""
    readonly property var urlRequest: YtdUrl.resolve(
        urlField.text, YtdService.playlistScope ? "playlist" : "single")
    readonly property bool urlValid: urlRequest.valid
    readonly property bool urlRejected: urlFilled && !urlValid
    readonly property string urlMessage: urlRequest.reason === "playlist_required"
        ? YtdI18n.t("playlist_required") : YtdI18n.t("invalid_url")

    function formatIndex(value) {
        for (var i = 0; i < formatOptions.length; i++) {
            if (formatOptions[i].value === value)
                return i;
        }
        return formatIndex(YtdService.defaultFormat);
    }

    function startDownload() {
        var inputUrl = urlField.text.trim();
        if (inputUrl === "")
            return;
        YtdService.start(inputUrl, YtdService.mediaFormat,
            YtdService.playlistScope ? "playlist" : "single");
    }

    function queuedSuffix() {
        return YtdService.queueCount > 0
            ? " · " + YtdI18n.t("queue_count").replace("%1", YtdService.queueCount)
            : "";
    }

    function statusText() {
        if (YtdService.running) {
            var current = YtdI18n.t("downloading");
            if (YtdService.itemIndex > 0 && YtdService.itemCount > 0)
                current += " " + YtdService.itemIndex + "/" + YtdService.itemCount;
            return current + " · " + Math.round(YtdService.progress) + "%" + queuedSuffix();
        }
        if (YtdService.state === "error")
            return YtdService.message || YtdI18n.t("download_failed");
        if (YtdService.state === "complete")
            return YtdService.message || YtdI18n.t("download_complete");
        if (YtdService.state === "cancelled")
            return YtdService.message || YtdI18n.t("download_stopped");
        var readyText = YtdService.mediaFormat === "mp3"
            ? YtdI18n.t("audio_mp3")
            : YtdI18n.t("video_format").replace("%1", YtdService.mediaFormat);
        if (YtdService.playlistScope)
            readyText += " · " + YtdI18n.t("scope_playlist");
        else
            readyText += " · " + YtdI18n.t("scope_single");
        return readyText + queuedSuffix();
    }

    function openHistoryFolder(path) {
        var filename = String(path || "");
        if (filename === "")
            return;
        var separator = filename.lastIndexOf("/");
        var directory = separator > 0 ? filename.slice(0, separator) : ".";
        openFolderProcess.command = ["xdg-open", directory];
        openFolderProcess.running = true;
    }

    // IpcHandler functions are registered as void: returning a value makes Qt
    // log "should be coerced to void" on every browser-triggered download.
    property IpcHandler ipc: IpcHandler {
        target: "ytd"

        function download(nextUrl: string, nextFormat: string, nextScope: string) {
            YtdService.requestDownload(nextUrl, nextFormat, nextScope);
        }
    }

    // External download requests (e.g. from browser IPC) show progress on
    // the top bar button without popping up the full window.

    component YtdIcon: Item {
        id: wrapper
        property real iconSize: 16
        // Resolved from the shell theme by the caller. The bar button passes the
        // button's own foreground role so the glyph keeps its contrast when the
        // surface flips to primary; the popup sites keep the light default.
        property color tintColor: Colors.overBackground

        // The raw SVG is white artwork. It stays visible underneath and the
        // colourised pass below is drawn exactly on top of it, so the artwork is
        // both the texture source and the unfiltered fallback.
        Image {
            id: icon
            anchors.centerIn: parent
            width: wrapper.iconSize
            height: wrapper.iconSize
            source: Qt.resolvedUrl("ytd.svg")
            sourceSize: Qt.size(width * 2, height * 2)
            fillMode: Image.PreserveAspectFit
            smooth: true
            visible: true
        }

        // The monochrome tint is done here rather than through the shell's shared
        // `Tinted` component. `monochrome` mode is not part of the base Ambxst
        // tree: it only exists in the `tinted-icons` mod, which its author
        // archived into `roadie`, and `roadie` cannot be installed next to this
        // mod. What that mode actually does is two properties on a
        // colorisation pass, so the mod carries its own copy and stays
        // independent. It is scoped to this one icon; nothing else on the shell
        // is tinted, unlike the mod it replaces.
        //
        // `brightness: 0.0` leaves the artwork's own luminance intact so the
        // glyph keeps its shading; `colorization` then replaces its hue with
        // exactly `tintColor`, landing on a precise theme role that a palette
        // blend cannot target. Do not pass the Image straight to a MultiEffect:
        // it needs a texture source and would render nothing, leaving the raw
        // white SVG showing through.
        ShaderEffectSource {
            id: iconTexture
            sourceItem: icon
            hideSource: true
            // The artwork never changes at runtime, so the texture is uploaded
            // once and refreshed only when the source itself reports a change.
            live: false
        }

        Connections {
            target: icon
            function onSourceChanged() { iconTexture.scheduleUpdate(); }
            function onStatusChanged() { iconTexture.scheduleUpdate(); }
        }

        // `hideSource: true` above means the artwork is not drawn on its own,
        // so this pass is the only thing that paints the glyph. With
        // `live: false` the texture is captured once, and in the popup that
        // capture happens while the PanelWindow is still hidden, leaving an
        // empty texture that nothing ever refreshes -- the header icon simply
        // renders as nothing. Re-capture whenever the wrapper becomes visible
        // or is resized by its layout, which is what the popup's header row
        // does when the window opens.
        Connections {
            target: wrapper
            function onVisibleChanged() { if (wrapper.visible) iconTexture.scheduleUpdate(); }
            function onWidthChanged() { iconTexture.scheduleUpdate(); }
            function onHeightChanged() { iconTexture.scheduleUpdate(); }
        }

        MultiEffect {
            anchors.fill: icon
            source: iconTexture
            brightness: 0.0
            colorization: 1.0
            colorizationColor: wrapper.tintColor
        }
    }

    // Text labels are measured explicitly so every segment can be centered
    // without the uneven left alignment produced by the shared icon switch.
    component FormatSelector: StyledRect {
        id: selector
        property var options: []
        property int currentIndex: 0
        property int padding: 2
        signal selected(int index)

        implicitWidth: optionsRow.childrenRect.width + padding * 2
        implicitHeight: 34
        radius: Styling.radius(-4)
        variant: "internalbg"
        enableShadow: false

        Item {
            anchors.fill: parent
            anchors.margins: selector.padding

            StyledRect {
                id: highlight
                property Item activeItem: optionRepeater.itemAt(selector.currentIndex)
                x: activeItem ? activeItem.x : 0
                width: activeItem ? activeItem.width : 44
                height: parent.height
                radius: Styling.radius(-5)
                variant: "primary"
                enableShadow: false

                Behavior on x {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration / 2
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on width {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration / 2
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Row {
                id: optionsRow
                anchors.fill: parent
                spacing: 2

                Repeater {
                    id: optionRepeater
                    model: selector.options

                    delegate: Button {
                        id: optionButton
                        required property var modelData
                        required property int index

                        width: Math.max(42, optionMetrics.width + 16)
                        height: optionsRow.height
                        focusPolicy: Qt.NoFocus
                        hoverEnabled: true
                        flat: true
                        background: Rectangle { color: "transparent" }

                        TextMetrics {
                            id: optionMetrics
                            text: optionButton.modelData.label
                            font.family: Styling.defaultFont
                            font.pixelSize: 12
                            font.bold: true
                        }

                        contentItem: Item {
                            Text {
                                anchors.centerIn: parent
                                width: parent.width
                                text: optionButton.modelData.label
                                color: selector.currentIndex === optionButton.index
                                    ? Styling.srItem("overprimary") : Colors.overBackground
                                font.family: Styling.defaultFont
                                font.pixelSize: 12
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        onClicked: {
                            selector.currentIndex = optionButton.index;
                            selector.selected(optionButton.index);
                        }
                        Accessible.name: optionButton.modelData.label
                    }
                }
            }
        }
    }

    component HelperButton: Button {
        id: control
        property string iconText: ""
        property string labelText: ""
        property string tooltipText: ""
        property bool danger: false
        property bool primary: false
        implicitHeight: 36
        leftPadding: control.labelText.length > 0 ? 10 : 0
        rightPadding: control.labelText.length > 0 ? 10 : 0
        activeFocusOnTab: true
        Accessible.name: control.labelText.length > 0 ? control.labelText : (control.tooltipText.length > 0 ? control.tooltipText : control.iconText)
        background: StyledRect {
            id: helperButtonBackground
            variant: control.primary
                ? (control.enabled ? "primary" : "common")
                : (control.down || control.checked ? "primary" : (control.hovered || control.visualFocus ? "focus" : "common"))
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
                color: control.danger ? Colors.red : (control.primary && !control.enabled ? Colors.outline : helperButtonBackground.item)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            Text {
                visible: control.labelText.length > 0
                Layout.fillWidth: true
                text: control.labelText
                color: control.danger ? Colors.red : (control.primary && !control.enabled ? Colors.outline : helperButtonBackground.item)
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(-1)
                font.bold: true
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

    Layout.preferredWidth: 36
    Layout.preferredHeight: 36
    Layout.fillWidth: vertical
    Layout.fillHeight: !vertical

    Button {
        id: button
        anchors.fill: parent
        hoverEnabled: true
        focusPolicy: Qt.NoFocus
        onClicked: popup.toggle()
        background: StyledRect {
            id: buttonBackground
            variant: root.popupOpen ? "primary" : "bg"
            enableShadow: root.layerEnabled
            topLeftRadius: root.startRadius
            bottomLeftRadius: root.startRadius
            topRightRadius: root.endRadius
            bottomRightRadius: root.endRadius

            Rectangle {
                anchors.fill: parent
                color: Styling.srItem("overprimary")
                opacity: button.down ? 0.5 : (button.hovered ? 0.25 : 0)
                radius: parent.radius ?? 0

                Behavior on opacity {
                    enabled: Config.animDuration > 0
                    NumberAnimation { duration: Config.animDuration / 2 }
                }
            }

            // Circular progress indicator (matching kde-connect-helper style, slightly outward & complete circle)
            Item {
                id: progressCanvas
                anchors.centerIn: parent
                width: 36
                height: 36
                visible: YtdService.running

                property real targetProgress: YtdService.running ? YtdService.progress : 0
                property real smoothProgress: 0
                property real radius: 13.5
                property real lineWidth: 2.5

                Behavior on smoothProgress {
                    enabled: Config.animDuration > 0 && YtdService.running
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.OutQuad
                    }
                }

                onTargetProgressChanged: {
                    if (!YtdService.running || targetProgress === 0) {
                        smoothProgress = 0;
                    } else if (targetProgress > smoothProgress) {
                        smoothProgress = targetProgress;
                    }
                }

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

                        let startAngle = -Math.PI / 2;
                        let fraction = Math.max(0, Math.min(1, progressCanvas.smoothProgress / 100));
                        let progressAngleRad = fraction * Math.PI * 2;

                        // Draw background track (complete circle, matching kde-connect-helper Colors.outlineVariant)
                        ctx.strokeStyle = Colors.outlineVariant;
                        ctx.lineWidth = lineWidth;
                        ctx.beginPath();
                        ctx.arc(centerX, centerY, radius, 0, Math.PI * 2, false);
                        ctx.stroke();

                        // Draw progress arc
                        if (fraction > 0) {
                            ctx.strokeStyle = root.popupOpen ? Colors.background : Colors.primary;
                            ctx.lineWidth = lineWidth;
                            ctx.beginPath();
                            ctx.arc(centerX, centerY, radius, startAngle, startAngle + progressAngleRad, false);
                            ctx.stroke();
                        }
                    }

                    Connections {
                        target: progressCanvas
                        function onSmoothProgressChanged() { canvas.requestPaint(); }
                    }

                    Connections {
                        target: YtdService
                        function onRunningChanged() {
                            if (!YtdService.running)
                                progressCanvas.smoothProgress = 0;
                            canvas.requestPaint();
                        }
                    }

                    Connections {
                        target: root
                        function onPopupOpenChanged() { canvas.requestPaint(); }
                    }
                }
            }
        }
        contentItem: Item {
            YtdIcon {
                anchors.fill: parent
                tintColor: root.barContentColor
            }
        }
        Accessible.name: YtdI18n.t("downloader")
    }

    StyledToolTip {
        show: button.hovered && !root.popupOpen
        tooltipText: YtdI18n.t("downloader")
        desciription: YtdService.running ? root.statusText() : YtdI18n.t("download_media")
    }

    Process {
        id: openFolderProcess
        running: false
        stderr: SplitParser {
            onRead: function(line) {
                console.warn("YTD: xdg-open:", line);
            }
        }
        onExited: function(code) {
            if (code === 0)
                return;
            YtdService.state = "error";
            YtdService.message = YtdI18n.t("opener_failed");
        }
    }

    // Keyboard input: this popup is a mod-owned PanelWindow rather than a
    // BarPopup. BarPopup is a Quickshell PopupWindow, which is not a
    // WlrLayerShell surface and therefore cannot request keyboard
    // interactivity: WlrLayershell fails to attach to it, and PopupWindow's
    // grabFocus only toggles the Qt::Popup flag for click-outside dismissal.
    // The shell's own input surfaces (UnifiedShellPanel, ContextMenu) are
    // PanelWindows that switch keyboardFocus to Exclusive while open, which is
    // what makes their text fields usable. This mirrors that.
    PanelWindow {
        id: popup
        property int popupPadding: 12
        property int shadowMargin: 16
        property int visualMargin: 8

        // Logical open state. isOpen tracks the user's intent immediately;
        // visible is the surface itself, so popupOpen stays false until the
        // window is actually mapped and the button shows its idle style when
        // closed.
        property bool isOpen: false

        // Position of the popup's top-left corner, in screen coordinates.
        // Assigned by reposition() rather than bound: see the comment there.
        property real popupX: 0
        property real popupY: 0

        readonly property string barPosition: root.bar?.barPosition ?? "top"
        readonly property bool barAtTop: barPosition === "top"
        readonly property bool barAtBottom: barPosition === "bottom"
        readonly property bool barAtLeft: barPosition === "left"
        readonly property bool barAtRight: barPosition === "right"
        readonly property bool barVertical: barAtLeft || barAtRight

        // Declared without a value: the content block below assigns these, and
        // two assignments in the same object scope would be a QML error.
        property int contentWidth
        property int contentHeight
        readonly property int totalWidth: contentWidth + shadowMargin * 2
        readonly property int totalHeight: contentHeight + shadowMargin * 2

        // PanelWindow has no x/y, so the window itself spans the screen and the
        // popup is positioned inside it, which is the same shape the shell uses
        // for ContextMenu: a full-screen transparent layer window whose child
        // carries the real position.
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"
        visible: false
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "ambxst-ytd"
        WlrLayershell.keyboardFocus: root.popupOpen
            ? WlrKeyboardFocus.Exclusive
            : WlrKeyboardFocus.None

        // Screen position of the bar button. mapToItem() is a *function* call,
        // so a binding over it never re-evaluates when the button moves: it is
        // computed once at load, while the bar is still at its pre-layout
        // position, and stays stale forever (that is what put the popup in the
        // top-left corner). It is therefore evaluated imperatively by
        // reposition() whenever the popup is about to be shown.
        function reposition() {
            const win = button.Window.window;
            const p = button.mapToItem(null, 0, 0);
            const ax = (win ? win.x : 0) + p.x;
            const ay = (win ? win.y : 0) + p.y;

            if (barVertical) {
                popupX = barAtLeft
                    ? ax + button.width + visualMargin
                    : ax - totalWidth - visualMargin;
                popupY = ay + (button.height - totalHeight) / 2;
            } else {
                popupX = ax + (button.width - totalWidth) / 2;
                popupY = barAtTop
                    ? ay + button.height + visualMargin
                    : ay - totalHeight - visualMargin;
            }

            // Keep the popup on screen when the bar hugs an edge.
            popupX = Math.max(visualMargin, Math.min(popupX, screenWidth - totalWidth - visualMargin));
            popupY = Math.max(visualMargin, Math.min(popupY, screenHeight - totalHeight - visualMargin));
        }

        // Escape closes the popup from anywhere inside it, not just while the
        // URL field happens to hold focus.
        Shortcut {
            sequence: "Escape"
            context: Qt.WindowShortcut
            onActivated: popup.close()
        }

        // Clicks anywhere outside the popup dismiss it. The bar button sits
        // *underneath* this full-screen surface, so without this the button
        // could never be clicked a second time to toggle the popup closed.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onPressed: popup.close()
        }

        Item {
            id: popupContainer
            x: popup.popupX
            y: popup.popupY
            width: popup.totalWidth
            height: popup.totalHeight

            // Deliberately no opacity/scale animation. Fading a full-screen
            // layer surface repaints the whole screen every frame, and because
            // the content is a ScrollView it did not follow the fade, so the
            // background and the content visibly tore down one after another.
            // Shown and hidden outright, this is immediate and looks like one
            // surface.
            StyledRect {
                id: background
                anchors.fill: parent
                anchors.margins: popup.shadowMargin
                variant: "popup"
                enableShadow: true
                radius: Styling.radius(8)

                ScrollView {
                    id: scrollArea
                    anchors.fill: parent
                    anchors.margins: popup.popupPadding
                    contentWidth: availableWidth
                    contentHeight: card.implicitHeight
                    clip: true

                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ScrollBar.vertical: ScrollBar {
                        policy: card.implicitHeight > scrollArea.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                    }

                    ColumnLayout {
                        id: card
                        width: parent.width - (ScrollBar.vertical.visible ? 10 : 0)
                        spacing: 12

                        // Header Row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            // Brand logo container with vibrant red badge
                            Item {
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Styling.radius(-2)
                                    color: Colors.red
                                    opacity: 0.15
                                }

                                YtdIcon {
                                    anchors.centerIn: parent
                                    width: 20
                                    height: 20
                                    iconSize: 20
                                    tintColor: Colors.red
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    text: YtdI18n.t("app_name")
                                    color: Colors.overBackground
                                    font.family: Styling.defaultFont
                                    font.pixelSize: Styling.fontSize(1)
                                    font.bold: true
                                }

                                RowLayout {
                                    spacing: 6

                                    Rectangle {
                                        Layout.preferredWidth: 6
                                        Layout.preferredHeight: 6
                                        radius: 3
                                        color: YtdService.running ? Colors.primary : Colors.green
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.statusText()
                                        color: Colors.overBackground
                                        opacity: 0.72
                                        font.family: Styling.defaultFont
                                        font.pixelSize: Styling.fontSize(-1)
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            HelperButton {
                                implicitWidth: 32
                                implicitHeight: 32
                                iconText: Icons.folder
                                tooltipText: YtdI18n.t("open_folder")
                                onClicked: root.openHistoryFolder(YtdService.mediaFormat === "mp3" ? "~/Music" : "~/Videos")
                            }

                            HelperButton {
                                implicitWidth: 32
                                implicitHeight: 32
                                iconText: Icons.trash
                                tooltipText: YtdI18n.t("clear_history")
                                visible: YtdService.history.length > 0
                                onClicked: YtdService.clearHistory()
                            }
                        }

                        // Section 2: Media Setup & Input Card
                        StyledRect {
                            Layout.fillWidth: true
                            implicitHeight: setupColumn.implicitHeight + 24
                            variant: "common"
                            radius: Styling.radius(0)
                            enableShadow: false

                            ColumnLayout {
                                id: setupColumn
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10

                                // Row 1: Header / Title
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        text: Icons.link
                                        font.family: Icons.font
                                        font.pixelSize: 15
                                        color: Colors.primary
                                    }

                                    Text {
                                        text: "Media Link"
                                        color: Colors.overBackground
                                        font.family: Styling.defaultFont
                                        font.pixelSize: Styling.fontSize(-1)
                                        font.bold: true
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        visible: root.urlRejected
                                        text: root.urlMessage
                                        color: Colors.red
                                        font.family: Styling.defaultFont
                                        font.pixelSize: Styling.fontSize(-2)
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                }

                                // Row 2: URL Input Field
                                TextField {
                                    id: urlField
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    placeholderText: YtdI18n.t("url_placeholder")
                                    text: YtdService.url
                                    selectByMouse: true
                                    activeFocusOnTab: true
                                    focus: popup.isOpen
                                    color: Colors.overBackground
                                    font.family: Styling.defaultFont
                                    font.pixelSize: Styling.fontSize(0)
                                    leftPadding: 12
                                    rightPadding: 12
                                    background: StyledRect {
                                        id: urlFieldBackground
                                        variant: root.urlRejected ? "common" : (urlField.activeFocus ? "focus" : "internalbg")
                                        radius: Styling.radius(-4)
                                        enableShadow: false
                                        border.width: urlField.activeFocus ? 2 : (root.urlRejected ? 1 : 0)
                                        border.color: root.urlRejected ? Colors.red : Styling.srItem("primary")
                                    }
                                    onAccepted: root.startDownload()
                                    Keys.onEscapePressed: popup.close()
                                }

                                // Row 3: Quick Action Bar (Balanced & Equal-height Buttons)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    HelperButton {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        implicitHeight: 38
                                        iconText: Icons.clipboard
                                        labelText: "Paste"
                                        tooltipText: YtdI18n.t("paste_from_clipboard")
                                        enabled: !YtdService.clipboardBusy
                                        onClicked: YtdService.readClipboard()
                                    }

                                    HelperButton {
                                        Layout.preferredWidth: 38
                                        implicitHeight: 38
                                        iconText: Icons.trash
                                        tooltipText: YtdI18n.t("clear_url")
                                        enabled: urlField.text.length > 0
                                        onClicked: urlField.clear()
                                    }

                                    HelperButton {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1.2
                                        implicitHeight: 38
                                        iconText: Icons.list
                                        labelText: YtdService.playlistScope ? "Playlist" : "Single"
                                        checked: YtdService.playlistScope
                                        tooltipText: YtdService.playlistScope ? YtdI18n.t("scope_playlist") : YtdI18n.t("scope_single")
                                        onClicked: YtdService.playlistScope = !YtdService.playlistScope
                                    }

                                    HelperButton {
                                        id: downloadButton
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1.5
                                        implicitHeight: 38
                                        iconText: Icons.arrowDown
                                        labelText: YtdI18n.t("download")
                                        primary: true
                                        enabled: root.urlFilled && root.urlValid && !YtdService.running
                                        tooltipText: YtdI18n.t("download")
                                        onClicked: root.startDownload()
                                    }
                                }

                                // Divider
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    color: Colors.overBackground
                                    opacity: 0.08
                                }

                                // Row 4: Format / Quality Selector
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Text {
                                        text: Icons.player
                                        font.family: Icons.font
                                        font.pixelSize: 15
                                        color: Colors.primary
                                    }

                                    Text {
                                        text: "Quality"
                                        color: Colors.overBackground
                                        font.family: Styling.defaultFont
                                        font.pixelSize: Styling.fontSize(-1)
                                        font.bold: true
                                    }

                                    Item { Layout.fillWidth: true }

                                    FormatSelector {
                                        id: formatSwitch
                                        options: root.formatOptions
                                        currentIndex: root.formatIndex(YtdService.mediaFormat)
                                        onSelected: function(index) {
                                            YtdService.mediaFormat = root.formatOptions[index].value;
                                        }

                                        Connections {
                                            target: YtdService
                                            function onMediaFormatChanged() {
                                                formatSwitch.currentIndex = root.formatIndex(YtdService.mediaFormat);
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Connections {
                            target: YtdService
                            function onClipboardTextChanged() {
                                if (YtdService.clipboardText !== "")
                                    urlField.text = YtdService.clipboardText;
                            }
                        }

                        // Section 3: Active Download / Current Status Card
                        StyledRect {
                            Layout.fillWidth: true
                            implicitHeight: activeDetailsColumn.implicitHeight + 24
                            visible: root.activeCardVisible
                            variant: "common"
                            radius: Styling.radius(0)
                            enableShadow: false

                            ColumnLayout {
                                id: activeDetailsColumn
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8

                                // Row 1: Status header
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Rectangle {
                                        Layout.preferredWidth: 6
                                        Layout.preferredHeight: 6
                                        radius: 3
                                        color: YtdService.state === "error" ? Colors.red : (YtdService.running ? Colors.green : Colors.outline)
                                    }

                                    Text {
                                        text: YtdService.running
                                            ? (YtdI18n.t("downloading") + (YtdService.itemCount > 1 ? (" (" + (YtdService.itemIndex || 1) + "/" + YtdService.itemCount + ")") : ""))
                                            : (YtdService.state === "error" ? YtdI18n.t("download_failed") : YtdI18n.t("download_stopped"))
                                        color: Colors.overBackground
                                        font.family: Styling.defaultFont
                                        font.pixelSize: Styling.fontSize(-1)
                                        font.bold: true
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Speed badge
                                    Rectangle {
                                        visible: YtdService.running && YtdService.speed > 0
                                        Layout.preferredHeight: 20
                                        width: speedText.implicitWidth + 10
                                        radius: 4
                                        color: Colors.surfaceVariant

                                        Text {
                                            id: speedText
                                            anchors.centerIn: parent
                                            text: YtdService.formatSpeed(YtdService.speed)
                                            color: Colors.primary
                                            font.family: Styling.defaultFont
                                            font.pixelSize: Styling.fontSize(-2)
                                            font.bold: true
                                        }
                                    }

                                    // Cancel button
                                    HelperButton {
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        iconText: Icons.cancel
                                        danger: true
                                        tooltipText: YtdI18n.t("stop_download")
                                        visible: YtdService.running
                                        onClicked: YtdService.cancel()
                                    }
                                }

                                // Divider
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    color: Colors.overBackground
                                    opacity: 0.08
                                }

                                // Row 2: Media preview
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    // Thumbnail with quality badge
                                    ClippingRectangle {
                                        Layout.preferredWidth: 60
                                        Layout.preferredHeight: 60
                                        radius: Styling.radius(-2)
                                        color: Colors.surfaceVariant

                                        YtdIcon {
                                            anchors.centerIn: parent
                                            width: 24
                                            height: 24
                                            iconSize: 24
                                            visible: thumbnailImage.status !== Image.Ready || YtdService.thumbnail === ""
                                        }

                                        Image {
                                            id: thumbnailImage
                                            anchors.fill: parent
                                            source: YtdService.thumbnail
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            smooth: true
                                        }

                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            anchors.right: parent.right
                                            anchors.margins: 4
                                            height: 14
                                            width: formatBadgeText.implicitWidth + 6
                                            radius: 3
                                            color: Colors.primary

                                            Text {
                                                id: formatBadgeText
                                                anchors.centerIn: parent
                                                text: YtdService.mediaFormat.toUpperCase()
                                                color: Styling.srItem("overprimary")
                                                font.family: Styling.defaultFont
                                                font.pixelSize: 9
                                                font.bold: true
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3

                                        Text {
                                            Layout.fillWidth: true
                                            text: YtdService.title !== "" ? YtdService.title : root.statusText()
                                            color: Colors.overBackground
                                            font.family: Styling.defaultFont
                                            font.pixelSize: Styling.fontSize(0)
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            visible: YtdService.filename !== ""
                                            text: YtdService.filename
                                            color: Colors.outline
                                            font.family: Styling.defaultFont
                                            font.pixelSize: Styling.fontSize(-2)
                                            elide: Text.ElideMiddle
                                        }
                                    }
                                }

                                // Divider (when downloading)
                                Rectangle {
                                    visible: YtdService.state === "starting" || YtdService.state === "downloading"
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    color: Colors.overBackground
                                    opacity: 0.08
                                }

                                // Row 3: Progress Bar & Stats
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    visible: YtdService.state === "starting" || YtdService.state === "downloading"

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 6
                                        radius: 3
                                        color: Colors.surfaceVariant

                                        Rectangle {
                                            width: parent.width * Math.max(0, Math.min(100, YtdService.progress)) / 100
                                            height: parent.height
                                            radius: 3
                                            color: Colors.primary

                                            Behavior on width {
                                                enabled: Config.animDuration > 0
                                                NumberAnimation { duration: 250; easing.type: Easing.OutQuad }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true

                                        Text {
                                            text: Math.round(YtdService.progress) + "%"
                                            color: Colors.primary
                                            font.family: Styling.defaultFont
                                            font.pixelSize: Styling.fontSize(0)
                                            font.bold: true
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: YtdService.formatBytes(YtdService.downloaded) + " / " + (YtdService.total > 0 ? YtdService.formatBytes(YtdService.total) : "unknown")
                                            color: Colors.outline
                                            font.family: Styling.defaultFont
                                            font.pixelSize: Styling.fontSize(-1)
                                            font.bold: true
                                        }
                                    }
                                }

                                // Error or cancelled notification banner
                                Text {
                                    Layout.fillWidth: true
                                    visible: YtdService.message !== "" && (YtdService.state === "error" || YtdService.state === "cancelled")
                                    text: YtdService.message
                                    color: Colors.red
                                    font.family: Styling.defaultFont
                                    font.pixelSize: Styling.fontSize(-1)
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        // Section 4: Recent Downloads History
                        RowLayout {
                            visible: root.historyVisible
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: Icons.folder
                                font.family: Icons.font
                                font.pixelSize: 15
                                color: Colors.primary
                            }

                            Text {
                                text: YtdI18n.t("downloads")
                                color: Colors.overBackground
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(-1)
                                font.bold: true
                            }

                            Rectangle {
                                Layout.preferredHeight: 18
                                width: historyBadgeText.implicitWidth + 10
                                radius: 9
                                color: Colors.surfaceVariant

                                Text {
                                    id: historyBadgeText
                                    anchors.centerIn: parent
                                    text: YtdService.history.length
                                    font.family: Styling.defaultFont
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: Colors.overBackground
                                }
                            }

                            Item { Layout.fillWidth: true }

                            HelperButton {
                                implicitWidth: 28
                                implicitHeight: 28
                                iconText: Icons.trash
                                tooltipText: YtdI18n.t("clear_history")
                                onClicked: YtdService.clearHistory()
                            }
                        }

                        StyledRect {
                            visible: root.historyVisible
                            Layout.fillWidth: true
                            implicitHeight: historyColumn.implicitHeight + 16
                            variant: "common"
                            radius: Styling.radius(0)
                            enableShadow: false

                            ColumnLayout {
                                id: historyColumn
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 4

                                Repeater {
                                    id: historyRepeater
                                    model: YtdService.history

                                    delegate: ColumnLayout {
                                        required property var modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        spacing: 4

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 52
                                            spacing: 10

                                            // Thumbnail
                                            ClippingRectangle {
                                                Layout.preferredWidth: 48
                                                Layout.preferredHeight: 48
                                                radius: Styling.radius(-2)
                                                color: Colors.surfaceVariant

                                                YtdIcon {
                                                    anchors.centerIn: parent
                                                    width: 20
                                                    height: 20
                                                    iconSize: 20
                                                    visible: historyThumbnail.status !== Image.Ready || modelData.thumbnail === ""
                                                }

                                                Image {
                                                    id: historyThumbnail
                                                    anchors.fill: parent
                                                    source: modelData.thumbnail || ""
                                                    fillMode: Image.PreserveAspectCrop
                                                    asynchronous: true
                                                    smooth: true
                                                }

                                                Rectangle {
                                                    anchors.bottom: parent.bottom
                                                    anchors.right: parent.right
                                                    anchors.margins: 2
                                                    height: 12
                                                    width: histFormatText.implicitWidth + 4
                                                    radius: 2
                                                    color: Colors.primary

                                                    Text {
                                                        id: histFormatText
                                                        anchors.centerIn: parent
                                                        text: String(modelData.format || "").toUpperCase()
                                                        color: Styling.srItem("overprimary")
                                                        font.family: Styling.defaultFont
                                                        font.pixelSize: 8
                                                        font.bold: true
                                                    }
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.title
                                                    color: Colors.overBackground
                                                    font.family: Styling.defaultFont
                                                    font.pixelSize: Styling.fontSize(-1)
                                                    font.bold: true
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.format
                                                    color: Colors.outline
                                                    font.family: Styling.defaultFont
                                                    font.pixelSize: Styling.fontSize(-2)
                                                }
                                            }

                                            RowLayout {
                                                spacing: 4

                                                HelperButton {
                                                    implicitWidth: 32
                                                    implicitHeight: 32
                                                    iconText: Icons.folder
                                                    tooltipText: YtdI18n.t("open_folder")
                                                    enabled: modelData.filename !== ""
                                                    onClicked: root.openHistoryFolder(modelData.filename)
                                                }

                                                HelperButton {
                                                    implicitWidth: 32
                                                    implicitHeight: 32
                                                    iconText: Icons.trash
                                                    tooltipText: YtdI18n.t("remove_from_history")
                                                    onClicked: YtdService.removeHistoryItem(modelData.itemId || modelData.filename || modelData.url)
                                                }
                                            }
                                        }

                                        // Divider between items (except last)
                                        Rectangle {
                                            visible: index < YtdService.history.length - 1
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 1
                                            color: Colors.overBackground
                                            opacity: 0.08
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        readonly property real screenHeight: root.bar?.screen?.height > 0 ? root.bar.screen.height : 900
        readonly property real screenWidth: root.bar?.screen?.width > 0 ? root.bar.screen.width : 900
        readonly property int availableHeight: Math.max(260, screenHeight - 64)
        readonly property int maximumContentHeight: 520
        contentWidth: Math.max(380, Math.min(420, screenWidth - 72))
        contentHeight: Math.min(availableHeight, Math.max(280, Math.min(maximumContentHeight, card.implicitHeight + popupPadding * 2)))

        function open() {
            if (visible)
                return;

            isOpen = true;
            // Measure the button now, while it is at its real on-screen
            // position, instead of relying on a load-time value.
            reposition();
            visible = true;

            // The window needs to be mapped before an item inside it can take
            // active focus, otherwise the keystrokes go nowhere.
            Qt.callLater(() => urlField.forceActiveFocus());
        }

        function close() {
            // Always clear the logical flag, even when the surface is already
            // hidden. Skipping it here would leave the button stuck in its
            // active state with no popup showing.
            isOpen = false;
            // Hide immediately. Unmapping is what tears the surface down in
            // one step; a fade on a full-screen layer surface left the
            // background and its content visibly unwinding separately.
            visible = false;
        }

        function toggle() {
            if (isOpen)
                close();
            else
                open();
        }

        // The bar can move (hide/reveal, layout change) while the popup is
        // open, so keep it pinned to the button.
        onVisibleChanged: {
            if (visible)
                reposition();
        }
    }
}
