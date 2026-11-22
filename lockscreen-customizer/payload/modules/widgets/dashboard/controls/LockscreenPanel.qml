pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.config
import qs.modules.globals
import qs.modules.lockscreen
import qs.modules.theme
import "../../../../config/defaults/lockscreen.js" as Defaults
import "../../../../modules/lockscreen/LockscreenPlacement.js" as Placement
import "../../../../modules/lockscreen/LockscreenActions.js" as Actions

Control {
    id: root

    property string editorWidget: ""
    property var editorSettings
    signal editorValuesChanged(var values)

    property int maxContentWidth: 680
    readonly property int minimumPanelWidth: 340
    property var draftStore: null
    property var localDraft: ({})
    readonly property var changes: draftStore ? draftStore.lockscreenDraft : localDraft
    readonly property bool dirty: Object.keys(changes).length > 0
    readonly property var settings: {
        if (editorWidget && editorSettings)
            return editorSettings;
        const settings = {};
        for (const key of Object.keys(Defaults.data))
            settings[key] = changes[key] ?? Config.customLockscreen[key];
        return settings;
    }
    readonly property string libraryPath: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share")
                                          + "/ambxst/lockscreen-wallpapers"
    readonly property string desktopWallpaperPath: GlobalStates.wallpaperManager?.wallpaperDir || ""
    readonly property string galleryFolder: desktopWallpaperPath || libraryPath
    readonly property string desktopThumbnailPath: Quickshell.env("HOME") + "/.cache/ambxst/thumbnails"
    readonly property url helper: Qt.resolvedUrl("../../../../scripts/lockscreen_wallpapers.py")
    readonly property url samples: Qt.resolvedUrl("../../../../assets/wallpapers_example")
    readonly property var targetScreen: Quickshell.screens.find(screen => screen.name === GlobalStates.settingsTargetScreenName)
                                        || Quickshell.screens[0]
    readonly property string mode: settings.wallpaperMode === "desktop" ? "image" : settings.wallpaperMode
    readonly property var wallpaperModes: [
        ["Static", "image"], ["Slideshow", "slideshow"], ["Video", "video"]
    ]
    readonly property var filterPatterns: mode === "video"
        ? ["*.mp4", "*.webm", "*.mov", "*.avi", "*.mkv", "*.m4v", "*.gif"]
        : ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.tif", "*.tiff", "*.bmp", "*.avif", "*.heif"]

    property var catalog: []
    property string libraryError: ""
    property string overlayError: ""
    property string importMode: ""
    property string scannedDesktopPath: ""
    readonly property var gallery: {
        const videos = mode === "video";
        const entries = catalog.filter(entry => entry.video === videos);
        const known = new Set(entries.map(entry => entry.url));
        const old = videos ? [settings.wallpaperVideo] : [settings.wallpaperImage, ...settings.wallpaperImages];
        for (const url of old) {
            if (url && !known.has(url)) {
                let name = url.split("/").pop();
                try { name = decodeURIComponent(name); } catch (error) {}
                entries.push({ name, url, video: videos, thumbnail: videos && !url.toLowerCase().endsWith(".gif") ? "" : url });
            }
        }
        return entries;
    }
    readonly property string selectedVideo: settings.wallpaperMode === "video" ? settings.wallpaperVideo : ""
    property string requestedPoster: ""
    property string loadedPoster: ""
    property string posterUrl: ""
    readonly property url videoPoster: selectedVideo === loadedPoster && posterUrl ? posterUrl
        : (catalog.find(entry => entry.url === selectedVideo)?.thumbnail || "")
    readonly property var selectedImages: Array.from(settings.wallpaperImages)

    function setDraft(changes) {
        if (draftStore)
            draftStore.lockscreenDraft = changes;
        else
            localDraft = changes;
    }

    function edit(values) {
        if (editorWidget) {
            editorValuesChanged(values);
            return;
        }
        const next = Object.assign({}, changes);
        for (const key of Object.keys(values)) {
            const value = values[key];
            const saved = Config.customLockscreen[key];
            const equal = Array.isArray(value)
                ? JSON.stringify(value) === JSON.stringify(Array.from(saved)) : saved === value;
            if (equal)
                delete next[key];
            else
                next[key] = value;
        }
        setDraft(next);
    }

    function setSetting(key, value) {
        edit({ [key]: value });
    }

    property bool saveFailed: false

    function saveChanges() {
        saveFailed = !Config.saveCustomLockscreen(changes);
        if (!saveFailed)
            setDraft({});
    }

    function applyPreset(preset) {
        if (!editorWidget) {
            edit(preset.values);
            return;
        }
        const values = Object.assign({}, preset.values);
        delete values[editorWidget + "Position"];
        delete values[editorWidget + "X"];
        delete values[editorWidget + "Y"];
        delete values[editorWidget === "clock" ? "clockSize" : editorWidget + "Scale"];
        edit(values);
    }

    function path(url) {
        return decodeURIComponent(url.toString().replace(/^file:\/\//, ""));
    }

    function scan(files) {
        if (libraryProcess.running)
            return;
        libraryError = "";
        importMode = files.length ? mode : "";
        scannedDesktopPath = desktopWallpaperPath;
        const desktopArguments = desktopWallpaperPath
            ? ["--desktop", desktopWallpaperPath, "--desktop-thumbnails", desktopThumbnailPath] : [];
        libraryProcess.command = ["python3", path(helper), ...desktopArguments,
                                  libraryPath, path(samples), ...files];
        libraryProcess.running = true;
    }

    function openOverlay(editing) {
        overlayLoader.setSource(Qt.resolvedUrl("../../../../modules/lockscreen/LockscreenPreviewWindow.qml"),
                                { screen: targetScreen, editing,
                                  videoPoster: Qt.binding(() => root.videoPoster),
                                  settings: Qt.binding(() => root.settings) });
    }

    function isSelected(url) {
        if (settings.wallpaperMode === "desktop")
            return false;
        switch (mode) {
        case "video": return settings.wallpaperVideo === url;
        case "slideshow": return selectedImages.includes(url);
        default: return settings.wallpaperImage === url;
        }
    }

    function selectWallpaper(url) {
        const values = { wallpaperMode: mode };
        if (mode === "slideshow") {
            values.wallpaperImages = selectedImages.includes(url)
                ? selectedImages.filter(image => image !== url) : [...selectedImages, url];
        } else if (mode === "video") {
            values.wallpaperVideo = url;
        } else {
            values.wallpaperImage = url;
        }
        edit(values);
    }

    palette.windowText: Colors.overSurface
    palette.buttonText: Colors.overSurface
    palette.text: Colors.overSurface
    palette.base: Colors.surfaceContainer
    palette.button: Colors.surfaceContainerHigh
    palette.window: Colors.surface
    palette.highlight: Colors.primary
    palette.highlightedText: Colors.overPrimary
    font.family: Config.theme.font
    font.pixelSize: Styling.fontSize(0)

    Component.onCompleted: {
        if (editorWidget)
            return;
        scanRequest.restart();
        posterRequest.restart();
    }
    onDesktopWallpaperPathChanged: scanRequest?.restart()

    Timer {
        id: scanRequest
        interval: 1
        onTriggered: root.scanIfNeeded()
    }

    function scanIfNeeded() {
        if (!editorWidget && (libraryProcess.command.length === 0 || scannedDesktopPath !== desktopWallpaperPath))
            scan([]);
    }

    Process {
        id: libraryProcess

        stdout: StdioCollector {
            id: libraryOutput
            waitForEnd: true
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    root.catalog = result.entries;
                    root.libraryError = result.errors.join(" ");
                    const added = result.imported;
                    if (added.length > 0) {
                        const values = {};
                        if (root.mode === root.importMode)
                            values.wallpaperMode = root.importMode;
                        if (root.importMode === "slideshow")
                            values.wallpaperImages = [...new Set([...root.selectedImages, ...added])];
                        else if (root.importMode === "video")
                            values.wallpaperVideo = added[0];
                        else
                            values.wallpaperImage = added[0];
                        root.edit(values);
                    }
                } catch (error) {
                    root.libraryError = "The wallpaper folder could not be loaded.";
                }
            }
        }

        onExited: code => {
            if (code !== 0)
                root.libraryError = "The wallpaper folder could not be loaded.";
            scanRequest.restart();
        }
    }

    onSelectedVideoChanged: requestVideoPoster()

    function requestVideoPoster() {
        const source = root.selectedVideo;
        if (editorWidget || !posterProcess || posterProcess.running || !source || source === root.requestedPoster)
            return;
        root.requestedPoster = source;
        posterProcess.command = ["python3", root.path(root.helper), "--preview-url", source,
                                 root.libraryPath, root.path(root.samples)];
        posterProcess.running = true;
    }

    Timer {
        id: posterRequest
        interval: 20
        onTriggered: root.requestVideoPoster()
    }

    Process {
        id: posterProcess

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (!text.trim())
                    return;
                const result = JSON.parse(text);
                if (result.url && result.thumbnail) {
                    root.loadedPoster = result.url;
                    root.posterUrl = result.thumbnail;
                }
            }
        }

        onExited: posterRequest.restart()
    }

    FileDialog {
        id: fileDialog
        title: "Import lock screen wallpaper"
        fileMode: root.mode === "slideshow" ? FileDialog.OpenFiles : FileDialog.OpenFile
        nameFilters: [(root.mode === "video" ? "Video and GIF" : "Images") + " (" + root.filterPatterns.join(" ") + ")"]
        onAccepted: root.scan(Array.from(selectedFiles, file => file.toString()))
    }

    Loader {
        id: overlayLoader

        onStatusChanged: {
            if (status === Loader.Error)
                root.overlayError = "Could not open the full-screen preview.";
            else if (status === Loader.Ready)
                root.overlayError = "";
        }
    }

    Connections {
        target: overlayLoader.item

        function onLayoutEdited(values) {
            root.edit(values);
        }

        function onDismiss() {
            overlayLoader.source = "";
        }
    }

    component Section: Rectangle {
        id: section
        required property string title
        property bool framed: true
        property Component headerAction
        default property alias controls: sectionContent.data
        color: framed ? Colors.surfaceContainerLow : "transparent"
        radius: Styling.radius(1)
        border.width: framed ? 1 : 0
        border.color: Colors.surfaceContainerHigh
        implicitHeight: sectionContent.implicitHeight + 32
        Layout.fillWidth: true

        ColumnLayout {
            id: sectionContent
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true

                Label {
                    Layout.fillWidth: true
                    text: section.title
                    font.pixelSize: Styling.fontSize(4)
                    font.bold: true
                    color: Colors.overSurface
                }

                Loader {
                    visible: section.headerAction !== null
                    sourceComponent: section.headerAction
                }
            }
        }
    }

    component ActionButton: Button {
        id: action
        property string label: ""
        property string glyph: ""
        property bool bare: false
        property bool mirrorGlyph: false
        property bool accent: false

        flat: true
        hoverEnabled: true
        horizontalPadding: bare ? 6 : 10
        verticalPadding: 5
        implicitWidth: Math.max(30, actionLabel.implicitWidth + leftPadding + rightPadding)
        implicitHeight: Math.max(29, actionLabel.implicitHeight + topPadding + bottomPadding)

        background: Rectangle {
            radius: 6
            color: action.bare ? "transparent"
                : action.accent && action.enabled ? (action.hovered ? Colors.primaryContainer : Colors.primary)
                : action.enabled && (action.hovered || action.down) ? Colors.surfaceContainerHighest
                : Colors.surfaceContainerHigh
            border.width: action.visualFocus ? 1 : 0
            border.color: Colors.outline
        }

        contentItem: Item {
            Row {
                id: actionLabel
                anchors.centerIn: parent
                spacing: 6
                readonly property color foreground: !action.enabled ? Colors.overSurfaceVariant
                    : action.accent ? (action.hovered ? Colors.overPrimaryContainer : Colors.overPrimary)
                    : action.bare && action.hovered ? Colors.primary : Colors.overSurface

                Text {
                    id: actionGlyph
                    visible: action.glyph !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: action.glyph
                    transform: Scale {
                        origin.x: actionGlyph.width / 2
                        xScale: action.mirrorGlyph ? -1 : 1
                    }
                    font.family: Icons.font
                    font.pixelSize: Styling.fontSize(1)
                    color: actionLabel.foreground
                }

                Label {
                    visible: action.label !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: action.label
                    color: actionLabel.foreground
                }
            }
        }
    }

    component FlatCombo: Basic.ComboBox {
        id: combo
        hoverEnabled: true
        implicitHeight: 29
        leftPadding: 9
        rightPadding: 24

        contentItem: Text {
            text: combo.displayText
            font: combo.font
            color: combo.enabled ? Colors.overSurface : Colors.overSurfaceVariant
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        indicator: Text {
            x: combo.width - width - 8
            y: (combo.height - height) / 2
            text: Icons.caretDown
            font.family: Icons.font
            font.pixelSize: Styling.fontSize(-2)
            color: Colors.overSurfaceVariant
        }

        background: Rectangle {
            radius: 6
            color: combo.hovered || combo.down ? Colors.surfaceContainerHighest : Colors.surfaceContainerHigh
            border.color: Colors.outline
            border.width: combo.visualFocus ? 1 : 0
        }
        delegate: Basic.ItemDelegate {
            id: option
            required property int index
            width: ListView.view.width
            implicitHeight: 30
            text: combo.textAt(index)
            highlighted: combo.highlightedIndex === index
            hoverEnabled: true

            contentItem: Text {
                text: option.text
                font: combo.font
                color: option.highlighted || option.hovered ? Colors.overPrimary : Colors.overSurface
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }

            background: Rectangle {
                radius: 5
                color: option.highlighted || option.hovered ? Colors.primary : "transparent"
            }
        }

        popup: Basic.Popup {
            y: combo.height + 3
            width: combo.width
            padding: 5
            margins: 5
            implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding

            contentItem: ListView {
                clip: true
                implicitHeight: Math.min(contentHeight, 240)
                model: combo.popup.visible ? combo.delegateModel : null
                currentIndex: combo.highlightedIndex
                highlightMoveDuration: 0
                ScrollBar.vertical: ScrollBar {}
            }

            background: Rectangle {
                radius: 8
                color: Colors.surfaceContainerHigh
                border.color: Colors.outlineVariant
            }
        }

    }

    component SettingRow: RowLayout {
        id: settingRow
        required property string label
        spacing: 12
        Layout.fillWidth: true

        Label {
            Layout.fillWidth: true
            text: settingRow.label
            color: Colors.overSurfaceVariant
            wrapMode: Text.WordWrap
        }
    }

    component Choice: SettingRow {
        id: choice
        required property string setting
        required property var options

        FlatCombo {
            Layout.preferredWidth: Math.min(138, viewport.width * 0.3)
            model: choice.options.map(option => option[0])
            currentIndex: Math.max(0, choice.options.findIndex(option => option[1] === root.settings[choice.setting]))
            Accessible.name: choice.label
            onActivated: index => root.setSetting(choice.setting, choice.options[index][1])
        }
    }

    component FontPicker: FlatCombo {
        id: fontPicker
        property var families: []
        readonly property var matchingFamilies: [...new Set(["", root.settings.clockFont, ...families])]
            .filter(family => (family || "Shell font").toLowerCase().includes((fontSearch?.text || "").trim().toLowerCase()))

        model: matchingFamilies.map(family => family || "Shell font")
        currentIndex: matchingFamilies.indexOf(root.settings.clockFont)
        displayText: root.settings.clockFont || "Shell font"
        Accessible.name: "Clock font family"
        onActivated: index => root.setSetting("clockFont", matchingFamilies[index])

        delegate: Basic.ItemDelegate {
            id: fontOption
            required property int index
            width: ListView.view.width
            implicitHeight: 31
            highlighted: fontPicker.highlightedIndex === index
            hoverEnabled: true

            contentItem: Text {
                text: fontPicker.textAt(fontOption.index)
                font.family: fontPicker.matchingFamilies[fontOption.index] || Config.theme.font
                font.pixelSize: Styling.fontSize(0)
                color: fontOption.highlighted || fontOption.hovered ? Colors.overPrimary : Colors.overSurface
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
            background: Rectangle {
                radius: 5
                color: fontOption.highlighted || fontOption.hovered ? Colors.primary : "transparent"
            }
        }

        popup: Basic.Popup {
            y: fontPicker.height + 3
            width: Math.min(Math.max(fontPicker.width, 235), viewport.width - 12)
            x: fontPicker.width - width
            padding: 6
            margins: 5
            implicitHeight: fontPopupContents.implicitHeight + topPadding + bottomPadding
            onAboutToShow: {
                if (!fontPicker.families.length)
                    fontPicker.families = Qt.fontFamilies().slice().sort((a, b) => a.localeCompare(b));
            }
            onOpened: fontSearch.forceActiveFocus()
            onClosed: fontSearch.clear()

            contentItem: ColumnLayout {
                id: fontPopupContents
                spacing: 5

                Basic.TextField {
                    id: fontSearch
                    Layout.fillWidth: true
                    placeholderText: "Search fonts"
                    color: Colors.overSurface
                    placeholderTextColor: Colors.overSurfaceVariant
                    selectByMouse: true
                    background: Rectangle {
                        radius: 5
                        color: Colors.surfaceContainer
                    }
                }

                Label {
                    visible: fontPicker.matchingFamilies.length === 0
                    text: "No matching fonts"
                    color: Colors.overSurfaceVariant
                    Layout.fillWidth: true
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 230)
                    clip: true
                    model: fontPicker.popup.visible ? fontPicker.delegateModel : null
                    currentIndex: fontPicker.highlightedIndex
                    ScrollBar.vertical: ScrollBar {}
                }
            }

            background: Rectangle {
                radius: 8
                color: Colors.surfaceContainerHigh
                border.color: Colors.outlineVariant
            }
        }
    }

    component ClockGroup: Rectangle {
        default property alias controls: groupControls.data
        Layout.fillWidth: true
        implicitWidth: groupControls.implicitWidth + 16
        implicitHeight: groupControls.implicitHeight + 12
        radius: 8
        color: Colors.surfaceContainer

        ColumnLayout {
            id: groupControls
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 6
            anchors.bottomMargin: 6
            spacing: 3
        }
    }

    component ThemeSwitch: Basic.Switch {
        id: toggle
        implicitWidth: 40
        implicitHeight: 26
        padding: 0

        indicator: Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 38
            height: 20
            radius: height / 2
            color: toggle.checked ? Colors.primary : Colors.surfaceContainerHighest
            border.color: toggle.visualFocus ? Colors.outline : "transparent"

            Rectangle {
                x: toggle.checked ? parent.width - width - 3 : 3
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                height: width
                radius: width / 2
                color: toggle.checked ? Colors.overPrimary : Colors.outline
            }
        }
    }

    component ClockToggle: SettingRow {
        id: option
        required property string key
        property bool value: Boolean(root.settings[key])
        property var update: checked => root.setSetting(key, checked)
        ThemeSwitch {
            checked: option.value
            Accessible.name: option.label
            onToggled: option.update(checked)
        }
    }

    component ClockSlider: SettingRow {
        id: row
        required property string key
        required property int minimum
        required property int maximum
        property string unit: "%"
        property real displayValue: root.settings[key]
        Basic.Slider {
            id: slider
            Layout.fillWidth: true
            Layout.minimumWidth: 45
            implicitHeight: 24
            from: row.minimum
            to: row.maximum
            stepSize: 1
            snapMode: Slider.SnapAlways
            value: row.displayValue
            Accessible.name: row.label
            onMoved: root.setSetting(row.key, Math.round(value))

            background: Rectangle {
                x: slider.leftPadding
                y: (slider.height - height) / 2
                width: slider.availableWidth
                height: 4
                radius: 2
                color: Colors.outlineVariant

                Rectangle {
                    width: slider.visualPosition * parent.width
                    height: parent.height
                    radius: 2
                    color: Colors.primary
                }
            }

            handle: Rectangle {
                x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                y: (slider.height - height) / 2
                width: 13
                height: width
                radius: width / 2
                color: slider.pressed ? Colors.primary : Colors.primaryFixed
                border.color: slider.visualFocus ? Colors.overSurface : "transparent"
            }
        }
        Label {
            text: row.unit === "em" ? (slider.value / 100).toFixed(2) + " em"
                : Math.round(slider.value) + "%"
            color: Colors.overSurface
        }
    }

    component PresetGrid: GridLayout {
        id: grid
        required property string kind
        required property var options
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 8
        rowSpacing: 8

        Repeater {
            model: !root.editorWidget || root.editorWidget === grid.kind ? grid.options : []

            delegate: Button {
                id: preset
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 100
                Layout.minimumWidth: 72
                implicitHeight: grid.kind === "clock" ? 114 : 106
                Accessible.name: modelData.name
                readonly property var designKeys: grid.kind === "clock" ? ["clockStyle"]
                    : grid.kind === "media" ? ["mediaStyle", "mediaArtwork"] : ["loginStyle"]
                readonly property bool selected: designKeys.every(key => root.settings[key] === modelData.values[key])
                Accessible.checkable: true
                Accessible.checked: selected

                padding: 8

                background: Rectangle {
                    radius: 8
                    antialiasing: true
                    color: preset.hovered || preset.activeFocus ? Colors.surfaceContainerHighest : Colors.surfaceContainer
                    border.color: preset.selected || preset.activeFocus ? Colors.primary : Colors.outlineVariant
                    border.width: preset.selected && grid.kind === "clock" ? 2 : 1

                    Rectangle {
                        visible: preset.selected && grid.kind === "clock"
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 8
                        width: 18
                        height: width
                        radius: width / 2
                        color: Colors.primary

                        Text {
                            anchors.centerIn: parent
                            text: "✓"
                            color: Colors.overPrimary
                            font.bold: true
                        }
                    }
                }

                contentItem: ColumnLayout {
                    spacing: 4

                    Loader {
                        id: sample
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        enabled: false
                        readonly property var settings: Object.assign({}, root.settings, preset.modelData.values)
                        sourceComponent: grid.kind === "clock" ? clockSample
                            : grid.kind === "media" ? mediaSample : loginSample

                        Component {
                            id: clockSample

                            Item {
                                LockscreenClock {
                                    anchors.centerIn: parent
                                    settings: Object.assign({}, sample.settings, {
                                        clockSeconds: false, clockGreeting: false, clockFormat: "24h",
                                        clockDateRatio: Math.max(23, sample.settings.clockDateRatio)
                                    })
                                    live: false
                                    shadows: false
                                    scale: Math.min(parent.width / Math.max(1, width),
                                                    parent.height / Math.max(1, height))
                                }
                            }
                        }

                        Component {
                            id: mediaSample

                            Item {
                                LockscreenMedia {
                                    anchors.centerIn: parent
                                    settings: sample.settings
                                    sample: true
                                    renderScale: Math.max(0.01, Math.min(parent.width / (designWidth * 1.17),
                                                    parent.height / (designHeight * 1.25)) * Math.min(1.25, sample.settings.mediaScale / 100))
                                }
                            }
                        }

                        Component {
                            id: loginSample

                            Item {
                                LockscreenLogin {
                                    anchors.centerIn: parent
                                    settings: sample.settings
                                    interactive: false
                                    animate: false
                                    renderScale: Math.max(0.01, Math.min(parent.width / 465,
                                                    parent.height / Math.max(130, designHeight * 1.3)) * sample.settings.loginScale / 100)
                                }
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: preset.modelData.name
                        color: preset.selected ? Colors.primary : Colors.overSurface
                        elide: Text.ElideRight
                        bottomPadding: grid.kind === "clock" ? 3 : 0
                    }
                }

                onClicked: root.applyPreset(modelData)
            }
        }
    }

    onEditorWidgetChanged: if (viewport) viewport.contentY = 0

    contentItem: Flickable {
        id: viewport
        contentWidth: width
        contentHeight: page.y + page.height + 14 + (root.dirty ? saveBar.height + 12 : 0)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        ColumnLayout {
            id: page
            x: (viewport.width - width) / 2
            y: 4
            width: Math.max(0, Math.min(viewport.width - (viewport.width < root.minimumPanelWidth + 24 ? 12 : 24), root.maxContentWidth))
            height: implicitHeight
            spacing: 14

            Section {
                title: "Lock screen"
                visible: !root.editorWidget
                framed: false

                Button {
                    id: previewCard
                    Layout.fillWidth: true
                    readonly property real screenWidth: root.targetScreen?.width || 1440
                    readonly property real screenHeight: root.targetScreen?.height || 900
                    Layout.preferredHeight: Math.max(1, width * screenHeight / screenWidth)
                    padding: 0
                    background: null
                    Accessible.name: "Open full-screen preview"

                    contentItem: ClippingRectangle {
                        clip: true
                        radius: 6
                        color: Colors.background
                        border.width: previewCard.activeFocus ? 2 : 0
                        border.color: Colors.primary
                        contentUnderBorder: true

                        Loader {
                            id: miniature
                            anchors.fill: parent
                            active: !root.editorWidget
                            sourceComponent: LockscreenScene {
                                screen: root.targetScreen
                                settings: root.settings
                                videoPoster: root.videoPoster
                                anchors.fill: parent
                                designScale: width / previewCard.screenWidth
                                preview: true
                                miniature: true
                            }
                        }

                        Label {
                            anchors.centerIn: parent
                            visible: miniature.item?.waitingForVideo ?? false
                            text: "Loading video…"
                            color: Colors.overSurface
                            padding: 8
                            background: Rectangle {
                                color: Colors.surfaceContainerHighest
                                radius: 6
                            }
                        }

                        HoverHandler {
                            cursorShape: Qt.PointingHandCursor
                        }
                    }
                    onClicked: root.openOverlay(false)
                }

                ActionButton {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    label: "Edit widget layout"
                    glyph: Icons.edit
                    Accessible.name: label
                    onClicked: root.openOverlay(true)
                }

                Label {
                    visible: root.overlayError !== ""
                    text: root.overlayError
                    color: Colors.error
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }

            Section {
                title: "Wallpaper"
                visible: !root.editorWidget
                headerAction: Component {
                    ActionButton {
                        bare: true
                        glyph: Icons.arrowCounterClockwise
                        mirrorGlyph: true
                        Accessible.name: "Refresh wallpapers"
                        ToolTip.visible: hovered
                        ToolTip.text: Accessible.name
                        enabled: !libraryProcess.running
                        onClicked: root.scan([])
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    FlatCombo {
                        width: 111
                        model: root.wallpaperModes.map(option => option[0])
                        currentIndex: root.wallpaperModes.findIndex(option => option[1] === root.mode)
                        Accessible.name: "Wallpaper type"
                        onActivated: index => root.setSetting("wallpaperMode", root.wallpaperModes[index][1])
                    }

                    ActionButton {
                        label: "Import"
                        glyph: Icons.plus
                        Accessible.name: "Import wallpapers"
                        enabled: !libraryProcess.running
                        onClicked: fileDialog.open()
                    }

                    ActionButton {
                        glyph: Icons.folder
                        Accessible.name: "Open wallpaper folder"
                        ToolTip.visible: hovered
                        ToolTip.text: Accessible.name
                        enabled: !libraryProcess.running && root.libraryError === ""
                        onClicked: Qt.openUrlExternally(Placement.fileUrl(root.galleryFolder))
                    }

                    ActionButton {
                        label: "Use desktop"
                        Accessible.name: label
                        enabled: root.settings.wallpaperMode !== "desktop"
                        onClicked: root.setSetting("wallpaperMode", "desktop")
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    Label {
                        Layout.fillWidth: true
                        text: root.settings.wallpaperMode === "desktop" ? "Using desktop wallpaper"
                            : root.mode === "slideshow" ? root.selectedImages.length + " selected"
                            : root.gallery.some(entry => root.isSelected(entry.url)) ? "" : "Choose a wallpaper below"
                        color: Colors.overSurfaceVariant
                        wrapMode: Text.WordWrap
                    }

                    ActionButton {
                        visible: root.mode === "slideshow" && root.gallery.length > 0
                        readonly property bool allSelected: root.gallery.every(entry => root.selectedImages.includes(entry.url))
                        label: allSelected ? "Clear selection" : "Select all"
                        Accessible.name: label
                        onClicked: root.setSetting("wallpaperImages", allSelected ? [] : root.gallery.map(entry => entry.url))
                    }
                }

                Label {
                    Layout.fillWidth: true
                    visible: root.libraryError !== "" || (!libraryProcess.running && root.gallery.length === 0)
                    text: root.libraryError || (root.mode === "video" ? "Import an MP4, GIF, or another video to get started."
                                                                    : "Import images to add them to the gallery.")
                    wrapMode: Text.WordWrap
                    color: root.libraryError ? Colors.error : Colors.overSurfaceVariant
                }

                GridView {
                    id: galleryGrid
                    readonly property int columns: Math.max(1, Math.min(4, Math.floor(width / 115)))
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(3, Math.ceil(count / columns)) * cellHeight
                    visible: count > 0
                    cellWidth: width / columns
                    cellHeight: Math.round(Math.min(112, cellWidth * 0.66))
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    model: root.gallery
                    ScrollBar.vertical: ScrollBar {}

                    delegate: Button {
                        id: tile
                        required property var modelData
                        readonly property bool selected: root.isSelected(modelData.url)
                        width: Math.max(0, galleryGrid.cellWidth - 8)
                        height: Math.max(0, galleryGrid.cellHeight - 8)
                        padding: 0
                        background: null
                        Accessible.name: modelData.name
                        Accessible.checkable: true
                        Accessible.checked: selected

                        contentItem: ClippingRectangle {
                            clip: true
                            radius: 6
                            color: Colors.surfaceContainerHighest
                            contentUnderBorder: true
                            border.width: tile.selected || tile.activeFocus ? 2 : 0
                            border.color: Colors.primary

                            Image {
                                id: thumbnail
                                anchors.fill: parent
                                source: tile.modelData.thumbnail
                                sourceSize: Qt.size(240, 160)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }

                            Label {
                                anchors.centerIn: parent
                                visible: tile.modelData.video && thumbnail.status !== Image.Ready
                                text: "▶"
                                color: Colors.primary
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 6
                                visible: tile.selected || root.mode === "slideshow"
                                width: 20
                                height: 20
                                radius: 5
                                color: tile.selected ? Colors.primary : Colors.surfaceContainerHighest
                                border.color: Colors.primary
                                Label {
                                    anchors.centerIn: parent
                                    text: tile.selected ? "✓" : ""
                                    color: Colors.overPrimary
                                }
                            }

                            HoverHandler {
                                cursorShape: Qt.PointingHandCursor
                            }
                        }
                        onClicked: root.selectWallpaper(modelData.url)
                    }
                }

                SettingRow {
                    label: "Slideshow interval"
                    visible: root.mode === "slideshow"
                    FlatCombo {
                        id: intervalPicker
                        readonly property var seconds: [...new Set([5, 10, 30, 60, 120, root.settings.wallpaperInterval])].sort((a, b) => a - b)
                        model: seconds.map(value => value + " s")
                        currentIndex: seconds.indexOf(root.settings.wallpaperInterval)
                        onActivated: index => root.setSetting("wallpaperInterval", seconds[index])
                        Accessible.name: "Slideshow interval"
                    }
                }

                SettingRow {
                    label: "Wallpaper blur (" + Math.round(blurSlider.value) + "%)"
                    Label {
                        text: "0%"
                        color: Colors.overSurfaceVariant
                    }
                    Slider {
                        id: blurSlider
                        Layout.preferredWidth: Math.min(220, viewport.width * 0.39)
                        from: 0
                        to: 100
                        stepSize: 1
                        snapMode: Slider.SnapAlways
                        value: root.settings.wallpaperBlur
                        onMoved: root.setSetting("wallpaperBlur", Math.round(value))
                        Accessible.name: "Wallpaper blur"
                    }
                    Label {
                        text: "100%"
                        Layout.minimumWidth: 36
                        horizontalAlignment: Text.AlignRight
                        color: Colors.overSurface
                    }
                }
            }

            Section {
                id: clockSection
                title: "Clock"
                visible: !root.editorWidget || root.editorWidget === "clock"

                PresetGrid {
                    kind: "clock"
                    options: [
                        { name: "Glance", values: { clockStyle: "inline", clockFont: "", clockSize: 112, clockDate: true, clockWeekday: "show", clockTimeRatio: 100, clockDateRatio: 21, clockWeight: "light", clockLetterSpacing: 4, clockPosition: "top-center", clockX: -1, clockY: -1 } },
                        { name: "Ambxst", values: { clockStyle: "offset", clockFont: "League Gothic", clockSize: 240, clockDate: true, clockWeekday: "show", clockTimeRatio: 100, clockDateRatio: 15, clockWeight: "regular", clockLetterSpacing: 0, clockPosition: "center-center", clockX: -1, clockY: -1 } },
                        { name: "Stacked", values: { clockStyle: "stacked", clockFont: "", clockSize: 152, clockDate: true, clockWeekday: "show", clockTimeRatio: 100, clockDateRatio: 24, clockWeight: "semibold", clockLetterSpacing: 0, clockPosition: "center-left", clockX: -1, clockY: -1 } },
                        { name: "Orbit", values: { clockStyle: "orbit", clockSize: 240, clockDate: false, clockWeekday: "hide", clockTimeRatio: 100, clockDateRatio: 10, clockWeight: "regular", clockLetterSpacing: 0, clockPosition: "center-center", clockX: -1, clockY: -1 } }
                    ]
                }

                Label {
                    text: "Content"
                    color: Colors.overSurfaceVariant
                    font.bold: true
                    font.letterSpacing: 1
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: clockSection.width >= 395 ? 2 : 1
                    columnSpacing: 12
                    rowSpacing: 4

                    ClockGroup {
                        ClockToggle { label: "Show date"; key: "clockDate" }
                        ClockToggle {
                            label: "Show weekday"
                            key: "clockWeekday"
                            value: root.settings.clockWeekday === "show"
                                || (root.settings.clockWeekday !== "hide" && root.settings.clockDate)
                            update: checked => root.setSetting(key, checked ? "show" : "hide")
                        }
                    }

                    ClockGroup {
                        ClockToggle { label: "Show seconds"; key: "clockSeconds" }
                        ClockToggle { label: "Show greeting"; key: "clockGreeting" }
                    }
                }

                Label {
                    text: "Time & Typography"
                    color: Colors.overSurfaceVariant
                    font.bold: true
                    font.letterSpacing: 1
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: clockSection.width >= 510 ? 2 : 1
                    columnSpacing: 12
                    rowSpacing: 6

                    ClockGroup {
                        SettingRow {
                            label: "Time format"

                            RowLayout {
                                id: formatOptions
                                spacing: 3
                                readonly property bool twelveHour: root.settings.clockFormat === "12h"
                                    || (root.settings.clockFormat === "shell" && Config.bar.use12hFormat)

                                Repeater {
                                    model: [{ label: "12h", value: "12h" }, { label: "24h", value: "24h" }]
                                    delegate: ActionButton {
                                        required property var modelData
                                        label: modelData.label
                                        horizontalPadding: 6
                                        accent: formatOptions.twelveHour === (modelData.value === "12h")
                                        Accessible.name: modelData.value === "12h" ? "12-hour format" : "24-hour format"
                                        Accessible.checkable: true
                                        Accessible.checked: accent
                                        onClicked: root.setSetting("clockFormat", modelData.value)
                                    }
                                }

                                ActionButton {
                                    label: "AM/PM"
                                    horizontalPadding: 6
                                    enabled: formatOptions.twelveHour
                                    accent: enabled && root.settings.clockAmPm
                                    Accessible.name: "Show AM or PM"
                                    Accessible.checkable: true
                                    Accessible.checked: accent
                                    onClicked: root.setSetting("clockAmPm", !root.settings.clockAmPm)
                                }
                            }
                        }

                        SettingRow {
                            label: "Font family"
                            FontPicker {
                                Layout.preferredWidth: Math.min(155, viewport.width * 0.36)
                            }
                        }

                        Choice {
                            label: "Font weight"
                            setting: "clockWeight"
                            options: [["Preset default", "legacy"], ["Light", "light"], ["Regular", "regular"],
                                      ["Medium", "medium"], ["Semibold", "semibold"], ["Bold", "bold"], ["Black", "black"]]
                        }
                    }

                    ClockGroup {
                        ClockSlider { label: "Time proportion"; key: "clockTimeRatio"; minimum: 65; maximum: 140 }
                        ClockSlider {
                            label: "Date proportion"
                            key: "clockDateRatio"
                            minimum: 5
                            maximum: 65
                            displayValue: root.settings.clockDateRatio || (root.settings.clockDateSize > 0
                                ? root.settings.clockDateSize * 100 / Math.max(1, root.settings.clockSize) : 19)
                        }
                        ClockSlider { label: "Letter spacing"; key: "clockLetterSpacing"; minimum: -10; maximum: 25; unit: "em" }
                    }
                }
            }

            Section {
                title: "Media player"
                visible: !root.editorWidget || root.editorWidget === "media"
                headerAction: Component {
                    ThemeSwitch {
                        checked: root.settings.mediaVisible
                        onToggled: root.setSetting("mediaVisible", checked)
                        Accessible.name: "Show media player"
                        ToolTip.visible: hovered
                        ToolTip.text: checked ? "Hide media player" : "Show media player"
                    }
                }

                PresetGrid {
                    kind: "media"
                    options: [
                        { name: "Ambxst", values: { mediaStyle: "bg", mediaArtwork: true, mediaScale: 100, mediaPosition: "legacy", mediaX: -1, mediaY: -1 } },
                        { name: "Compact", values: { mediaStyle: "compact", mediaArtwork: false, mediaScale: 75, mediaPosition: "bottom-left", mediaX: -1, mediaY: -1 } },
                        { name: "Now playing", values: { mediaStyle: "pane", mediaArtwork: true, mediaScale: 125, mediaPosition: "bottom-right", mediaX: -1, mediaY: -1 } },
                        { name: "Cover", values: { mediaStyle: "cover", mediaArtwork: false, mediaScale: 100, mediaPosition: "bottom-left", mediaX: -1, mediaY: -1 } },
                        { name: "Ribbon", values: { mediaStyle: "ribbon", mediaArtwork: false, mediaScale: 100, mediaPosition: "bottom-left", mediaX: -1, mediaY: -1 } },
                        { name: "Outline", values: { mediaStyle: "outline", mediaArtwork: false, mediaScale: 100, mediaPosition: "bottom-right", mediaX: -1, mediaY: -1 } }
                    ]
                }
            }

            Section {
                title: "Login"
                visible: !root.editorWidget || root.editorWidget === "login"

                PresetGrid {
                    kind: "login"
                    options: [
                        { name: "Ambxst", values: { loginStyle: "bg", loginAvatar: true, loginScale: 100, loginPosition: "legacy", loginX: -1, loginY: -1 } },
                        { name: "Minimal", values: { loginStyle: "plain", loginAvatar: false, loginScale: 90, loginPosition: "bottom-center", loginX: -1, loginY: -1 } },
                        { name: "Profile", values: { loginStyle: "pane", loginAvatar: true, loginScale: 130, loginPosition: "bottom-center", loginX: -1, loginY: -1 } },
                        { name: "Badge", values: { loginStyle: "badge", loginAvatar: true, loginScale: 100, loginPosition: "bottom-center", loginX: -1, loginY: -1 } },
                        { name: "Underline", values: { loginStyle: "line", loginAvatar: false, loginScale: 100, loginPosition: "bottom-center", loginX: -1, loginY: -1 } },
                        { name: "Sign-in card", values: { loginStyle: "card", loginAvatar: false, loginScale: 100, loginPosition: "bottom-center", loginX: -1, loginY: -1 } }
                    ]
                }

                SettingRow {
                    label: "Show profile picture"
                    Switch {
                        checked: root.settings.loginAvatar
                        onToggled: root.setSetting("loginAvatar", checked)
                        Accessible.name: "Show profile picture"
                    }
                }
            }
            Section {
                id: shortcutsSection
                title: "Shortcuts"
                visible: !root.editorWidget
                readonly property var configured: Array.from(root.settings.shortcuts ?? [])
                readonly property bool hasSelection: Actions.available.some(action => isSelected(action.id))

                function isSelected(id) {
                    return configured.some(shortcut => shortcut?.id === id && shortcut.enabled !== false);
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        model: Actions.available

                        delegate: LockscreenShortcut {
                            required property var modelData
                            shortcutAction: modelData
                            usable: true
                            toggleMode: true
                            selected: shortcutsSection.isSelected(modelData.id)
                            Layout.preferredWidth: designWidth
                            Layout.preferredHeight: designHeight
                            onSelectionRequested: root.setSetting("shortcuts",
                                Actions.toggle(shortcutsSection.configured, modelData.id))
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                ActionButton {
                    Layout.fillWidth: true
                    label: "Edit shortcut layout"
                    glyph: Icons.edit
                    Accessible.name: label
                    enabled: shortcutsSection.hasSelection
                    onClicked: root.openOverlay(true)
                }
            }

        }
    }
    Rectangle {
        id: saveBar
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        anchors.horizontalCenter: parent.horizontalCenter
        width: page.width
        height: saveControls.implicitHeight + 16
        radius: 8
        color: Colors.surfaceContainerHighest
        border.color: Colors.outlineVariant
        visible: !root.editorWidget && root.dirty
        z: 2

        RowLayout {
            id: saveControls
            anchors.fill: parent
            anchors.margins: 8

            Label {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                text: root.saveFailed ? "Could not save changes. Try again." : "Unsaved changes"
                color: root.saveFailed ? Colors.error : Colors.overSurface
            }

            ActionButton {
                label: "Save changes"
                Accessible.name: label
                accent: true
                onClicked: root.saveChanges()
            }
        }
    }

}
