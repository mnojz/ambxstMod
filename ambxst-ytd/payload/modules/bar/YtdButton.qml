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
        { label: "2K", value: "1440p" },
        { label: "4K", value: "2160p" }
    ]

    // Only a real YouTube/YouTube Music link can be downloaded, so the field
    // is checked live and the download button stays disabled otherwise. A
    // playlist link also needs the Whole playlist option in single mode.
    readonly property bool urlFilled: urlField.text.trim() !== ""
    readonly property var urlRequest: YtdUrl.resolve(
        urlField.text, YtdService.playlistScope ? "playlist" : "single")
    readonly property bool urlValid: urlRequest.valid
    readonly property bool urlRejected: urlFilled && !urlValid
    readonly property bool hasPlaylistParam: urlFilled && !!urlRequest?.hasPlaylist
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
        openFolderProcess.command = ["bash", "-c", 'dir="${1/#\\~/$HOME}"; case "$dir" in *.*) dir="$(dirname "$dir")" ;; esac; xdg-open "$dir"', "--", filename];
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

    // Segmented quality/format selector with neutral semi-transparent track,
    // equal active and hover thumb sizing, and distinct text color hierarchy.
    component FormatSelector: Rectangle {
        id: selector
        property var options: []
        property int currentIndex: 0
        property int padding: 3
        signal selected(int index)

        implicitHeight: 36
        radius: Styling.radius(-3)
        color: Qt.rgba(1, 1, 1, 0.04)

        RowLayout {
            anchors.fill: parent
            anchors.margins: selector.padding
            spacing: 3

            Repeater {
                id: optionRepeater
                model: selector.options

                delegate: Button {
                    id: optionButton
                    required property var modelData
                    required property int index

                    readonly property bool isSelected: selector.currentIndex === optionButton.index

                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    focusPolicy: Qt.NoFocus
                    hoverEnabled: true
                    flat: true

                    background: Rectangle {
                        anchors.fill: parent
                        radius: Styling.radius(-4)
                        color: optionButton.isSelected
                            ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.22)
                            : (optionButton.hovered
                                ? Qt.rgba(Colors.cyan.r, Colors.cyan.g, Colors.cyan.b, 0.12)
                                : "transparent")
                        Behavior on color {
                            enabled: Config.animDuration > 0
                            ColorAnimation { duration: 150 }
                        }
                    }

                    contentItem: Item {
                        anchors.fill: parent
                        Text {
                            anchors.centerIn: parent
                            width: parent.width
                            text: optionButton.modelData.label
                            color: optionButton.isSelected
                                ? Colors.primary
                                : (optionButton.hovered ? Colors.cyan : Colors.overBackground)
                            opacity: optionButton.isSelected ? 1.0 : (optionButton.hovered ? 1.0 : 0.65)
                            font.family: Styling.defaultFont
                            font.pixelSize: 13
                            font.bold: optionButton.isSelected
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
                    // Anchored inside the styled background rather than placed with
                    // absolute window coordinates, so the content and the surface
                    // behind it are always the same rectangle and are shown and hidden
                    // together.
                    anchors.fill: parent
                    anchors.margins: popup.popupPadding
                    contentWidth: availableWidth
                    contentHeight: card.implicitHeight
                    clip: true

                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    // No scrollbar gutter. The history list is long, but the
                    // overflow affordance is not worth a permanent ~10px strip
                    // on a panel this narrow; the wheel and touchpad still
                    // scroll the view.
                    ScrollBar.vertical.policy: ScrollBar.AlwaysOff

                    ColumnLayout {
                        id: card
                        width: parent.width
                        spacing: 12

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            YtdIcon {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26
                                iconSize: 26
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    text: YtdI18n.t("app_name")
                                    color: Colors.overBackground
                                    font.family: Styling.defaultFont
                                    font.pixelSize: Styling.fontSize(1)
                                    font.bold: true
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

                            // Music Folder Button (~/Music)
                            Button {
                                id: headerMusicFolderBtn
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                focusPolicy: Qt.NoFocus
                                onClicked: root.openHistoryFolder("~/Music")
                                background: Rectangle {
                                    radius: Styling.radius(-4)
                                    color: headerMusicFolderBtn.hovered
                                        ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.15)
                                        : "transparent"
                                }
                                contentItem: Text {
                                    text: "\ue340"
                                    color: headerMusicFolderBtn.hovered ? Colors.primary : Colors.overBackground
                                    opacity: headerMusicFolderBtn.hovered ? 1.0 : 0.8
                                    font.family: Icons.font
                                    font.pixelSize: 18
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                Accessible.name: "Open Music Folder"
                                StyledToolTip {
                                    show: headerMusicFolderBtn.hovered
                                    tooltipText: "Open Music Folder (~/Music)"
                                }
                            }

                            // Videos Folder Button (~/Videos)
                            Button {
                                id: headerVideoFolderBtn
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                focusPolicy: Qt.NoFocus
                                onClicked: root.openHistoryFolder("~/Videos")
                                background: Rectangle {
                                    radius: Styling.radius(-4)
                                    color: headerVideoFolderBtn.hovered
                                        ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.15)
                                        : "transparent"
                                }
                                contentItem: Text {
                                    text: Icons.recordings
                                    color: headerVideoFolderBtn.hovered ? Colors.primary : Colors.overBackground
                                    opacity: headerVideoFolderBtn.hovered ? 1.0 : 0.8
                                    font.family: Icons.font
                                    font.pixelSize: 18
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                Accessible.name: "Open Videos Folder"
                                StyledToolTip {
                                    show: headerVideoFolderBtn.hovered
                                    tooltipText: "Open Videos Folder (~/Videos)"
                                }
                            }
                        }

                        // Row 2: Full-width Searchbar / URL Input
                        Rectangle {
                            id: inputContainer
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            radius: Styling.radius(-3)
                            color: root.urlRejected
                                ? Qt.rgba(Colors.red.r, Colors.red.g, Colors.red.b, 0.15)
                                : (inputHover.hovered || urlField.activeFocus
                                    ? Qt.rgba(1, 1, 1, 0.07)
                                    : Qt.rgba(1, 1, 1, 0.04))

                            Behavior on color {
                                enabled: Config.animDuration > 0
                                ColorAnimation { duration: Config.animDuration / 2 }
                            }

                            HoverHandler {
                                id: inputHover
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 6
                                spacing: 8

                                Text {
                                    text: Icons.link
                                    font.family: Icons.font
                                    font.pixelSize: 17
                                    color: urlField.activeFocus ? Colors.primary : Colors.overBackground
                                    opacity: urlField.activeFocus ? 1.0 : 0.5
                                    verticalAlignment: Text.AlignVCenter
                                }

                                TextField {
                                    id: urlField
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    placeholderText: YtdI18n.t("url_placeholder")
                                    text: YtdService.url
                                    selectByMouse: true
                                    activeFocusOnTab: true
                                    focus: popup.isOpen
                                    background: Item {}
                                    color: Colors.overBackground
                                    placeholderTextColor: Qt.rgba(1, 1, 1, 0.40)
                                    font.family: Styling.defaultFont
                                    font.pixelSize: Styling.fontSize(0)
                                    leftPadding: 0
                                    rightPadding: 0
                                    verticalAlignment: Text.AlignVCenter
                                    onAccepted: root.startDownload()
                                    Keys.onEscapePressed: popup.close()
                                }

                                // Icon-only Playlist Scope Toggle: shown only when link contains playlist parameter
                                Button {
                                    id: inlinePlaylistBtn
                                    visible: root.hasPlaylistParam
                                    Layout.preferredWidth: 26
                                    Layout.preferredHeight: 26
                                    focusPolicy: Qt.NoFocus
                                    onClicked: YtdService.playlistScope = !YtdService.playlistScope
                                    background: Rectangle {
                                        radius: 13
                                        color: YtdService.playlistScope
                                            ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.22)
                                            : (inlinePlaylistBtn.hovered
                                                ? Qt.rgba(1, 1, 1, 0.10)
                                                : "transparent")
                                    }
                                    contentItem: Text {
                                        text: YtdService.playlistScope ? Icons.list : Icons.play
                                        color: YtdService.playlistScope
                                            ? Colors.primary
                                            : (inlinePlaylistBtn.hovered ? Colors.primary : Colors.overBackground)
                                        opacity: YtdService.playlistScope ? 1.0 : (inlinePlaylistBtn.hovered ? 1.0 : 0.75)
                                        font.family: Icons.font
                                        font.pixelSize: 15
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    Accessible.name: YtdService.playlistScope
                                        ? YtdI18n.t("scope_playlist")
                                        : YtdI18n.t("scope_single")
                                    StyledToolTip {
                                        show: inlinePlaylistBtn.hovered
                                        tooltipText: YtdService.playlistScope
                                            ? YtdI18n.t("scope_playlist")
                                            : YtdI18n.t("scope_single")
                                    }
                                }

                                Button {
                                    id: inlinePasteBtn
                                    visible: urlField.text.length === 0
                                    Layout.preferredHeight: 28
                                    leftPadding: 8
                                    rightPadding: 8
                                    focusPolicy: Qt.NoFocus
                                    enabled: !YtdService.clipboardBusy
                                    onClicked: YtdService.readClipboard()
                                    background: Rectangle {
                                        radius: Styling.radius(-5)
                                        color: inlinePasteBtn.hovered
                                            ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.18)
                                            : Qt.rgba(1, 1, 1, 0.08)
                                    }
                                    contentItem: RowLayout {
                                        spacing: 4
                                        Text {
                                            text: Icons.clipboard
                                            font.family: Icons.font
                                            font.pixelSize: 14
                                            color: inlinePasteBtn.hovered ? Colors.primary : Colors.overBackground
                                            opacity: inlinePasteBtn.hovered ? 1.0 : 0.85
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        Text {
                                            text: "Paste"
                                            font.family: Styling.defaultFont
                                            font.pixelSize: Styling.fontSize(-2)
                                            font.bold: true
                                            color: inlinePasteBtn.hovered ? Colors.primary : Colors.overBackground
                                            opacity: inlinePasteBtn.hovered ? 1.0 : 0.85
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                    Accessible.name: YtdI18n.t("paste_from_clipboard")
                                    StyledToolTip {
                                        show: inlinePasteBtn.hovered
                                        tooltipText: YtdI18n.t("paste_from_clipboard")
                                    }
                                }

                                Button {
                                    id: inlineClearBtn
                                    visible: urlField.text.length > 0
                                    Layout.preferredWidth: 26
                                    Layout.preferredHeight: 26
                                    focusPolicy: Qt.NoFocus
                                    onClicked: urlField.clear()
                                    background: Rectangle {
                                        color: inlineClearBtn.hovered ? Qt.rgba(Colors.red.r, Colors.red.g, Colors.red.b, 0.2) : "transparent"
                                        radius: 13
                                    }
                                    contentItem: Text {
                                        text: Icons.cancel
                                        color: inlineClearBtn.hovered ? Colors.red : Colors.overBackground
                                        opacity: inlineClearBtn.hovered ? 1.0 : 0.7
                                        font.family: Icons.font
                                        font.pixelSize: 16
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    Accessible.name: YtdI18n.t("clear_url")
                                    StyledToolTip {
                                        show: inlineClearBtn.hovered
                                        tooltipText: YtdI18n.t("clear_url")
                                    }
                                }
                            }
                        }

                        // Rejection / Error Hint Row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            visible: root.urlRejected
                            Text {
                                text: Icons.alert
                                font.family: Icons.font
                                font.pixelSize: 15
                                color: Colors.red
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root.urlMessage
                                color: Colors.red
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(-1)
                                font.bold: true
                                elide: Text.ElideRight
                            }
                        }

                        // Row 3: Quality Segmented Selector + Icon-Only Download Button
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            FormatSelector {
                                id: formatSwitch
                                Layout.fillWidth: true
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

                            // Icon-Only Download Action Button
                            Button {
                                id: downloadButton
                                Layout.preferredWidth: 42
                                Layout.preferredHeight: 36
                                focusPolicy: Qt.NoFocus
                                enabled: root.urlFilled && root.urlValid && !YtdService.running
                                onClicked: root.startDownload()
                                background: Rectangle {
                                    radius: Styling.radius(-3)
                                    color: downloadButton.enabled
                                        ? (downloadButton.hovered
                                            ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.32)
                                            : Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.22))
                                        : (downloadButton.hovered
                                            ? Qt.rgba(1, 1, 1, 0.08)
                                            : Qt.rgba(1, 1, 1, 0.04))

                                    Behavior on color {
                                        enabled: Config.animDuration > 0
                                        ColorAnimation { duration: 150 }
                                    }
                                }
                                contentItem: Text {
                                    text: Icons.arrowFatLinesDown
                                    color: downloadButton.enabled ? Colors.primary : Colors.overBackground
                                    opacity: downloadButton.enabled ? 1.0 : 0.4
                                    font.family: Icons.font
                                    font.pixelSize: 19
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                Accessible.name: YtdI18n.t("download")
                                StyledToolTip {
                                    show: downloadButton.hovered
                                    tooltipText: downloadButton.enabled ? YtdI18n.t("download") : YtdI18n.t("invalid_url")
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

                        // Active download / last result, shown above the history.
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            visible: root.activeCardVisible

                            StyledRect {
                                Layout.fillWidth: true
                                implicitHeight: detailsColumn.implicitHeight + 16
                                variant: "common"
                                radius: Styling.radius(-2)
                                enableShadow: false

                                ColumnLayout {
                                    id: detailsColumn
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 8

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10

                                        ClippingRectangle {
                                            Layout.preferredWidth: 56
                                            Layout.preferredHeight: 56
                                            radius: Styling.radius(-3)
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
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 4

                                            Text {
                                                Layout.fillWidth: true
                                                text: YtdService.title !== "" ? YtdService.title : root.statusText()
                                                color: Colors.overBackground
                                                font.family: Styling.defaultFont
                                                font.pixelSize: Styling.fontSize(0)
                                                font.bold: true
                                                elide: Text.ElideMiddle
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                visible: YtdService.filename !== ""
                                                text: YtdService.filename
                                                color: Colors.overBackground
                                                opacity: 0.72
                                                font.family: Styling.defaultFont
                                                font.pixelSize: Styling.fontSize(-1)
                                                elide: Text.ElideMiddle
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 4
                                                visible: YtdService.state === "starting" || YtdService.state === "downloading"

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    height: 6
                                                    radius: 3
                                                    color: Colors.surfaceBright
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
                                                    spacing: 4

                                                    Text {
                                                        text: (YtdService.itemCount > 0 ? YtdService.completedCount + "/" + YtdService.itemCount + " · " : "") + Math.round(YtdService.progress) + "%"
                                                        color: Colors.primary
                                                        font.family: Styling.defaultFont
                                                        font.pixelSize: 13
                                                        font.bold: true
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: YtdService.formatBytes(YtdService.downloaded) + (YtdService.total > 0 ? " / " + YtdService.formatBytes(YtdService.total) : "")
                                                        color: Colors.overBackground
                                                        opacity: 0.8
                                                        font.family: Styling.defaultFont
                                                        font.pixelSize: 12
                                                        horizontalAlignment: Text.AlignRight
                                                        elide: Text.ElideRight
                                                    }

                                                    Text {
                                                        visible: YtdService.speed > 0
                                                        text: YtdService.formatSpeed(YtdService.speed)
                                                        color: Colors.overBackground
                                                        opacity: 0.8
                                                        font.family: Styling.defaultFont
                                                        font.pixelSize: 12
                                                    }

                                                    Button {
                                                        id: cancelButton
                                                        Layout.preferredWidth: 26
                                                        Layout.preferredHeight: 26
                                                        focusPolicy: Qt.NoFocus
                                                        visible: YtdService.running
                                                        onClicked: YtdService.cancel()
                                                        background: StyledRect { variant: cancelButton.hovered ? "focus" : "common"; radius: Styling.radius(-5); enableShadow: false }
                                                        contentItem: Text { text: Icons.cancel; color: cancelButton.hovered ? Colors.red : Colors.overBackground; font.family: Icons.font; font.pixelSize: 15; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                                        Accessible.name: YtdI18n.t("stop_download")
                                                        StyledToolTip {
                                                            show: cancelButton.hovered
                                                            tooltipText: YtdI18n.t("stop_download")
                                                        }
                                                    }
                                                }
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                visible: YtdService.message !== "" && (YtdService.state === "error" || YtdService.state === "cancelled")
                                                text: YtdService.message
                                                color: YtdService.state === "error" ? Colors.red : Colors.overBackground
                                                opacity: YtdService.state === "error" ? 1.0 : 0.75
                                                font.family: Styling.defaultFont
                                                font.pixelSize: Styling.fontSize(-1)
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: root.historyVisible
                            Rectangle { Layout.fillWidth: true; height: 1; color: Colors.surfaceBright; opacity: 0.4 }
                            Text {
                                text: YtdI18n.t("downloads").toUpperCase()
                                color: Colors.overBackground
                                opacity: 0.55
                                font.family: Styling.defaultFont
                                font.pixelSize: 11
                                font.bold: true
                                font.letterSpacing: 0.5
                            }
                            Rectangle { Layout.fillWidth: true; height: 1; color: Colors.surfaceBright; opacity: 0.4 }

                            Button {
                                id: clearHistoryButton
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26
                                focusPolicy: Qt.NoFocus
                                onClicked: YtdService.clearHistory()
                                background: Rectangle {
                                    radius: Styling.radius(-5)
                                    color: clearHistoryButton.hovered
                                        ? Qt.rgba(Colors.red.r, Colors.red.g, Colors.red.b, 0.15)
                                        : "transparent"
                                }
                                contentItem: Text {
                                    text: Icons.trash
                                    color: clearHistoryButton.hovered ? Colors.red : Colors.overBackground
                                    opacity: clearHistoryButton.hovered ? 1.0 : 0.6
                                    font.family: Icons.font
                                    font.pixelSize: 14
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                Accessible.name: YtdI18n.t("clear_history")
                                StyledToolTip {
                                    show: clearHistoryButton.hovered
                                    tooltipText: YtdI18n.t("clear_history")
                                }
                            }
                        }

                        ColumnLayout {
                            visible: root.historyVisible
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                id: historyRepeater
                                model: YtdService.history

                                delegate: StyledRect {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 56
                                    variant: "common"
                                    radius: Styling.radius(-2)
                                    enableShadow: false

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 10
                                        ClippingRectangle {
                                            Layout.preferredWidth: 40
                                            Layout.preferredHeight: 40
                                            radius: Styling.radius(-4)
                                            color: Colors.surfaceVariant
                                            YtdIcon {
                                                anchors.centerIn: parent
                                                width: 18
                                                height: 18
                                                iconSize: 18
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
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 3
                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.title
                                                color: Colors.overBackground
                                                font.family: Styling.defaultFont
                                                font.pixelSize: Styling.fontSize(-1)
                                                font.bold: true
                                                elide: Text.ElideRight
                                            }
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6
                                                Rectangle {
                                                    Layout.preferredHeight: 18
                                                    Layout.preferredWidth: formatBadgeText.implicitWidth + 8
                                                    radius: Styling.radius(-5)
                                                    color: Colors.surfaceBright
                                                    Text {
                                                        id: formatBadgeText
                                                        anchors.centerIn: parent
                                                        text: modelData.format
                                                        color: Colors.overBackground
                                                        font.family: Styling.defaultFont
                                                        font.pixelSize: 10
                                                        font.bold: true
                                                    }
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.filename !== "" ? modelData.filename : modelData.url
                                                    color: Colors.overBackground
                                                    opacity: 0.65
                                                    font.family: Styling.defaultFont
                                                    font.pixelSize: 11
                                                    elide: Text.ElideMiddle
                                                }
                                            }
                                        }
                                        RowLayout {
                                            Layout.preferredWidth: 54
                                            spacing: 2
                                            Button {
                                                id: openHistoryFolderButton
                                                Layout.preferredWidth: 26
                                                Layout.preferredHeight: 26
                                                focusPolicy: Qt.NoFocus
                                                enabled: modelData.filename !== ""
                                                onClicked: root.openHistoryFolder(modelData.filename)
                                                background: StyledRect { variant: openHistoryFolderButton.hovered ? "focus" : "common"; radius: Styling.radius(-5); enableShadow: false }
                                                contentItem: Text {
                                                    text: Icons.folder
                                                    color: openHistoryFolderButton.enabled
                                                        ? (openHistoryFolderButton.hovered ? Colors.primary : Colors.overBackground)
                                                        : Colors.outline
                                                    opacity: openHistoryFolderButton.hovered ? 1.0 : 0.8
                                                    font.family: Icons.font
                                                    font.pixelSize: 15
                                                    horizontalAlignment: Text.AlignHCenter
                                                    verticalAlignment: Text.AlignVCenter
                                                }
                                                Accessible.name: YtdI18n.t("open_folder")
                                                StyledToolTip {
                                                    show: openHistoryFolderButton.hovered
                                                    tooltipText: YtdI18n.t("open_folder")
                                                }
                                            }
                                            Button {
                                                id: removeHistoryButton
                                                Layout.preferredWidth: 26
                                                Layout.preferredHeight: 26
                                                focusPolicy: Qt.NoFocus
                                                onClicked: YtdService.removeHistoryItem(modelData.itemId || modelData.filename || modelData.url)
                                                background: StyledRect { variant: removeHistoryButton.hovered ? "focus" : "common"; radius: Styling.radius(-5); enableShadow: false }
                                                contentItem: Text {
                                                    text: Icons.trash
                                                    color: removeHistoryButton.hovered ? Colors.red : Colors.overBackground
                                                    opacity: removeHistoryButton.hovered ? 1.0 : 0.8
                                                    font.family: Icons.font
                                                    font.pixelSize: 15
                                                    horizontalAlignment: Text.AlignHCenter
                                                    verticalAlignment: Text.AlignVCenter
                                                }
                                                Accessible.name: YtdI18n.t("remove_from_history")
                                                StyledToolTip {
                                                    show: removeHistoryButton.hovered
                                                    tooltipText: YtdI18n.t("remove_from_history")
                                                }
                                            }
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
        // One page scrolls as a single unit: header, URL field, format
        // selector, the active card, and every history card. Tweak this
        // value to change the popup viewport height.
        readonly property int availableHeight: Math.max(240, screenHeight - 48)
        readonly property int maximumContentHeight: 350
        // The format row is fixed width: FormatSelector sizes itself from its
        // chips and the scope toggle adds 44px, so ~350px of content is the
        // point below which the selector row starts to clip. 404 keeps roughly
        // 30px of breathing room once the padding is taken off.
        contentWidth: Math.max(372, Math.min(404, screenWidth - 72))
        contentHeight: Math.min(availableHeight, Math.min(maximumContentHeight, card.implicitHeight + popup.popupPadding * 2))

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

        onTotalHeightChanged: {
            if (visible)
                reposition();
        }
    }
}
