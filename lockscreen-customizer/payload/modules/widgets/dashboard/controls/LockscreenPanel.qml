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
import "../../../../modules/lockscreen/LockscreenPresets.js" as Presets

Control {
    id: root

    property string editorWidget: ""
    property var editorSettings
    property var editorPresetBaseline: ({})
    signal editorValuesChanged(var values)
    signal editorPresetApplied(string widget, var values)

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
                ? JSON.stringify(value) === JSON.stringify(Array.from(saved ?? [])) : saved === value;
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
        property Component customHeader
        property PresetGrid presets
        property int contentSpacing: 12
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
            spacing: section.contentSpacing

            RowLayout {
                visible: section.customHeader === null
                Layout.fillWidth: true

                Label {
                    Layout.fillWidth: true
                    text: section.title
                    font.pixelSize: Styling.fontSize(4)
                    font.bold: true
                    color: Colors.overSurface
                }

                Item {
                    visible: section.presets !== null
                    implicitWidth: savePresetButton.implicitWidth
                    implicitHeight: savePresetButton.implicitHeight

                    ActionButton {
                        id: savePresetButton
                        anchors.fill: parent
                        label: "Save to preset"
                        helpText: "Save this widget’s appearance, size, and position as a new preset."
                        visible: section.presets?.canSavePreset ?? false
                        onClicked: presetNameDialog.begin(null, section.presets.catalog)
                    }
                }
            }

            Loader {
                Layout.fillWidth: true
                active: section.customHeader !== null
                visible: active
                sourceComponent: section.customHeader
            }
        }
    }

    component ActionButton: Button {
        id: action
        property string helpText: ""
        ToolTip.text: helpText
        ToolTip.delay: 500
        ToolTip.visible: hovered && helpText !== ""
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
                : action.accent && action.enabled ? (action.hovered && !action.checkable ? Colors.primaryContainer : Colors.primary)
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
                    : action.accent ? (action.hovered && !action.checkable ? Colors.overPrimaryContainer : Colors.overPrimary)
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
        property string helpText: ""
        ToolTip.text: helpText
        ToolTip.delay: 500
        ToolTip.visible: hovered && helpText !== ""
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
        required property real controlWidth

        FlatCombo {
            Layout.preferredWidth: choice.controlWidth
            model: choice.options.map(option => option[0])
            currentIndex: Math.max(0, choice.options.findIndex(option => option[1] === root.settings[choice.setting]))
            helpText: "Choose how thick the clock text looks."
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
        helpText: "Search for a font or use the shell font."
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
        hoverEnabled: true
        property string helpText: ""
        ToolTip.text: helpText
        ToolTip.delay: 500
        ToolTip.visible: hovered && helpText !== ""
        implicitWidth: 40
        implicitHeight: 26
        padding: 0

        indicator: Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 38
            height: 20
            radius: height / 2
            color: !toggle.enabled ? Colors.surfaceContainerLow
                : toggle.checked ? Colors.primary : Colors.surfaceContainerHighest
            border.color: toggle.visualFocus ? Colors.primary : Colors.outline
            border.width: toggle.enabled ? 1 : 0

            Rectangle {
                x: toggle.checked ? parent.width - width - 3 : 3
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                height: width
                radius: width / 2
                color: !toggle.enabled ? Colors.outlineVariant
                    : toggle.checked ? Colors.overPrimary : Colors.overSurface
            }
        }
    }

    component WidgetToggle: SettingRow {
        id: option
        required property string key
        property bool value: Boolean(root.settings[key])
        property var update: checked => root.setSetting(key, checked)
        property string helpText: ""
        ThemeSwitch {
            helpText: option.helpText
            checked: option.value
            Accessible.name: option.label
            onToggled: option.update(checked)
        }
    }

    component WidgetSlider: SettingRow {
        id: row
        required property string key
        required property int minimum
        required property int maximum
        property string unit: "%"
        property real displayValue: root.settings[key]
        readonly property real trackWidth: Math.round(Math.min(220, viewport.width * 0.28))

        FontMetrics {
            id: sliderMetrics
            font: sliderValue.font
        }

        Basic.Slider {
            id: slider
            Layout.preferredWidth: row.trackWidth
            Layout.minimumWidth: row.trackWidth
            Layout.maximumWidth: row.trackWidth
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
            id: sliderValue
            Layout.preferredWidth: Math.ceil(sliderMetrics.advanceWidth("-0.10 em"))
            horizontalAlignment: Text.AlignRight
            text: row.unit === "em" ? (slider.value / 100).toFixed(2) + " em"
                : Math.round(slider.value) + (row.unit === "%" ? "%" : " " + row.unit)
            color: Colors.overSurface
        }
    }

    Basic.Popup {
        id: presetNameDialog

        property var targetPreset: null
        property var catalog: []
        readonly property string enteredName: presetName.text.trim()
        readonly property bool duplicateName: catalog.some(entry => (!targetPreset || entry.builtin !== targetPreset.builtin
            || entry.recordIndex !== targetPreset.recordIndex)
            && entry.name.toLowerCase() === enteredName.toLowerCase())

        function begin(preset, entries) {
            targetPreset = preset;
            catalog = entries;
            presetName.text = preset?.name ?? "";
            open();
        }

        function commitName() {
            if (!enteredName || duplicateName)
                return;
            if (targetPreset?.name === enteredName) {
                close();
                return;
            }
            const records = Array.from(root.settings.widgetPresets ?? []);
            const changes = { widgetPresets: records };
            if (!targetPreset) {
                changes[root.editorWidget + "Preset"] = "saved:" + records.length;
                records.push(Presets.create(root.editorWidget, enteredName, root.settings, Defaults.data));
            } else if (targetPreset.recordIndex >= 0) {
                const index = targetPreset.recordIndex;
                records[index] = Object.assign({}, records[index], { name: enteredName });
            } else {
                records.push({ schemaVersion: Presets.version, widget: root.editorWidget,
                               builtin: targetPreset.builtin, name: enteredName });
            }
            root.edit(changes);
            close();
        }

        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(320, (parent?.width ?? root.width) - 24)
        modal: true
        focus: true
        padding: 14
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: {
            presetName.forceActiveFocus();
            presetName.selectAll();
        }
        onClosed: {
            targetPreset = null;
            catalog = [];
        }

        background: Rectangle {
            color: Colors.surfaceContainerHigh
            border.color: Colors.outlineVariant
            radius: 10
            antialiasing: true
        }

        contentItem: ColumnLayout {
            spacing: 8

            Label {
                text: presetNameDialog.targetPreset ? "Rename preset" : "Save to preset"
                color: Colors.overSurface
                font.bold: true
            }

            Basic.TextField {
                id: presetName
                Layout.fillWidth: true
                maximumLength: 64
                placeholderText: "Preset name"
                Accessible.name: placeholderText
                onAccepted: presetNameDialog.commitName()
            }

            Label {
                visible: presetNameDialog.duplicateName
                text: "That preset name is already in use."
                color: Colors.error
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight

                ActionButton {
                    label: "Cancel"
                    helpText: "Close without saving the name."
                    onClicked: presetNameDialog.close()
                }
                ActionButton {
                    label: "Save"
                    helpText: "Confirm this preset name."
                    enabled: presetNameDialog.enteredName !== "" && !presetNameDialog.duplicateName
                    onClicked: presetNameDialog.commitName()
                }
            }
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

        readonly property var catalog: {
            if (root.editorWidget !== kind)
                return [];
            const records = Array.from(root.settings.widgetPresets ?? []);
            const styleKey = kind + "Style";
            const builtins = options.map(option => {
                const builtin = option.values[styleKey];
                const recordIndex = records.findIndex(record => record?.schemaVersion === Presets.version
                    && record.widget === kind && record.builtin === builtin && typeof record.name === "string");
                return Object.assign({}, option, {
                    builtin, recordIndex, name: records[recordIndex]?.name ?? option.name
                });
            });
            const saved = [];
            records.forEach((record, recordIndex) => {
                if (record?.schemaVersion === Presets.version && record.widget === kind
                        && !record.builtin && typeof record.name === "string" && record.values) {
                    saved.push({ name: record.name, values: Presets.valuesFor(kind, record.values, Defaults.data), recordIndex });
                }
            });
            return [...builtins, ...saved];
        }

        readonly property var widgetValues: Presets.valuesFor(kind, root.settings, Defaults.data)
        readonly property var presetBaseline: Presets.valuesFor(kind, root.editorPresetBaseline, Defaults.data)

        function matchesPreset(preset) {
            const values = preset.builtin ? Object.assign({}, presetBaseline, preset.values) : preset.values;
            const keys = Object.keys(widgetValues);
            return keys.length > 0 && keys.every(key => widgetValues[key] === values[key]);
        }

        readonly property bool canSavePreset: {
            if (root.editorWidget !== kind)
                return false;
            return Object.keys(widgetValues).some(key => widgetValues[key] !== presetBaseline[key])
                && !catalog.some(preset => matchesPreset(preset));
        }

        function presetId(preset) {
            return preset.builtin ? "builtin:" + preset.builtin : "saved:" + preset.recordIndex;
        }

        readonly property string selectedPreset: {
            const current = root.settings[kind + "Preset"];
            const matching = catalog.find(preset => presetId(preset) === current && matchesPreset(preset))
                ?? catalog.find(preset => !preset.builtin && matchesPreset(preset))
                ?? catalog.find(preset => matchesPreset(preset));
            return matching ? presetId(matching) : "";
        }

        Repeater {
            model: grid.catalog

            delegate: Item {
                id: card
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 100
                Layout.minimumWidth: 72
                implicitHeight: grid.kind === "clock" ? 114 : 106
                Button {
                    id: preset
                    anchors.fill: parent
                    readonly property var modelData: card.modelData
                    Accessible.name: modelData.name
                    hoverEnabled: true
                    ToolTip.text: "Apply " + modelData.name + "."
                    ToolTip.delay: 500
                    ToolTip.visible: hovered && !renamePreset.hovered
                    readonly property bool selected: grid.selectedPreset === grid.presetId(modelData)
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
                                        settings: !preset.modelData.builtin ? sample.settings : Object.assign({}, sample.settings, {
                                            clockSize: preset.modelData.sampleSize, clockSeconds: false, clockGreeting: false, clockFormat: "24h",
                                            clockDateRatio: Math.max(23, sample.settings.clockDateRatio)
                                        })
                                        live: false
                                        renderScale: Math.min(parent.width / Math.max(1, designWidth),
                                                              parent.height / Math.max(1, designHeight))
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
                                                        parent.height / (designHeight * 1.25)) * Math.min(1.25, (preset.modelData.sampleSize ?? 100) / 100))
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
                                                        parent.height / Math.max(130, designHeight * 1.3)) * (preset.modelData.sampleSize ?? 100) / 100)
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
                            leftPadding: 20
                            rightPadding: 20
                            bottomPadding: grid.kind === "clock" ? 3 : 0
                        }
                    }

                    onClicked: {
                        root.editorPresetApplied(grid.kind, Object.assign({}, grid.widgetValues, modelData.values));
                        root.edit(Object.assign({}, modelData.values, { [grid.kind + "Preset"]: grid.presetId(modelData) }));
                    }
                }

                ActionButton {
                    id: renamePreset
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 4
                    width: 25
                    height: 25
                    bare: true
                    glyph: Icons.edit
                    Accessible.name: "Rename " + card.modelData.name
                    helpText: "Rename this preset."
                    onClicked: presetNameDialog.begin(card.modelData, grid.catalog)
                }
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
                id: previewSection
                title: "Lock screen"
                visible: !root.editorWidget
                framed: false
                readonly property real previewWidth: Math.min(440, Math.round(Math.max(0, width - 32) * 0.8))

                Button {
                    id: previewCard
                    Layout.fillWidth: true
                    Layout.maximumWidth: previewSection.previewWidth
                    Layout.alignment: Qt.AlignHCenter
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
                    Layout.maximumWidth: previewSection.previewWidth
                    Layout.alignment: Qt.AlignHCenter
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
                contentSpacing: 9
                customHeader: Component {
                    RowLayout {
                        spacing: 8

                        Label {
                            text: "Wallpaper"
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredHeight: 29
                            verticalAlignment: Text.AlignVCenter
                            font.pixelSize: Styling.fontSize(wallpaperHeader.compact ? 1 : 4)
                            font.bold: true
                            color: Colors.overSurface
                        }

                        Flow {
                            id: wallpaperHeader
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            layoutDirection: Qt.RightToLeft
                            spacing: compact ? 3 : 6
                            readonly property bool compact: width < 460

                            ActionButton {
                                bare: true
                                glyph: Icons.arrowCounterClockwise
                                mirrorGlyph: true
                                Accessible.name: "Refresh wallpapers"
                                helpText: "Rescan the wallpaper folders for new files."
                                enabled: !libraryProcess.running
                                onClicked: root.scan([])
                            }

                            ActionButton {
                                visible: root.mode === "slideshow" && root.gallery.length > 0
                                readonly property bool allSelected: root.gallery.every(entry => root.selectedImages.includes(entry.url))
                                label: wallpaperHeader.compact ? "" : Accessible.name
                                glyph: wallpaperHeader.compact ? (allSelected ? Icons.minus : Icons.squaresFour) : ""
                                horizontalPadding: wallpaperHeader.compact ? 4 : 10
                                Accessible.name: allSelected ? "Clear selection" : "Select all"
                                helpText: allSelected ? "Deselect all slideshow images." : "Select every image in the gallery for the slideshow."
                                onClicked: root.setSetting("wallpaperImages", allSelected ? [] : root.gallery.map(entry => entry.url))
                            }

                            ActionButton {
                                label: wallpaperHeader.compact ? "" : "Tint"
                                glyph: wallpaperHeader.compact ? Icons.palette : ""
                                horizontalPadding: wallpaperHeader.compact ? 4 : 10
                                Accessible.name: "Wallpaper tint"
                                helpText: "Tint the wallpaper with your shell theme."
                                checkable: true
                                checked: root.settings.wallpaperTint
                                accent: checked
                                onToggled: root.setSetting("wallpaperTint", checked)
                            }

                            ActionButton {
                                label: wallpaperHeader.compact ? "" : "Use desktop"
                                glyph: wallpaperHeader.compact ? Icons.image : ""
                                horizontalPadding: wallpaperHeader.compact ? 4 : 10
                                Accessible.name: "Use desktop wallpaper"
                                helpText: "Use your current desktop wallpaper on the lock screen."
                                enabled: root.settings.wallpaperMode !== "desktop"
                                onClicked: root.setSetting("wallpaperMode", "desktop")
                            }

                            ActionButton {
                                glyph: Icons.folder
                                horizontalPadding: wallpaperHeader.compact ? 4 : 10
                                Accessible.name: "Open wallpaper folder"
                                helpText: "Open the folder used by this gallery."
                                enabled: !libraryProcess.running && root.libraryError === ""
                                onClicked: Qt.openUrlExternally(Placement.fileUrl(root.galleryFolder))
                            }

                            ActionButton {
                                label: wallpaperHeader.compact ? "" : "Import"
                                glyph: Icons.plus
                                horizontalPadding: wallpaperHeader.compact ? 4 : 10
                                Accessible.name: "Import wallpapers"
                                helpText: "Choose files to copy into the lock screen wallpaper library."
                                enabled: !libraryProcess.running
                                onClicked: fileDialog.open()
                            }

                            FlatCombo {
                                width: wallpaperHeader.compact ? 87 : 111
                                model: root.wallpaperModes.map(option => option[0])
                                currentIndex: root.wallpaperModes.findIndex(option => option[1] === root.mode)
                                helpText: "Choose a still image, a slideshow, or a video."
                                Accessible.name: "Wallpaper type"
                                onActivated: index => root.setSetting("wallpaperMode", root.wallpaperModes[index][1])
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Colors.outlineVariant
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
                        hoverEnabled: true
                        ToolTip.text: root.mode === "slideshow"
                            ? (selected ? "Remove " + modelData.name + " from the slideshow."
                                        : "Add " + modelData.name + " to the slideshow.")
                            : "Use " + modelData.name + " as the lock screen wallpaper."
                        ToolTip.delay: 500
                        ToolTip.visible: hovered
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

                        readonly property var seconds: [...new Set([5, 10, 30, 60, 120, root.settings.wallpaperInterval])].sort((a, b) => a - b)
                        model: seconds.map(value => value + " s")
                        currentIndex: seconds.indexOf(root.settings.wallpaperInterval)
                        onActivated: index => root.setSetting("wallpaperInterval", seconds[index])
                        helpText: "Set how long each slideshow image stays on screen."
                        Accessible.name: "Slideshow interval"
                    }
                }

                WidgetSlider { label: "Wallpaper blur"; key: "wallpaperBlur"; minimum: 0; maximum: 100 }
                WidgetSlider { label: "Wallpaper dimming"; key: "wallpaperDim"; minimum: 0; maximum: 100 }
            }

            Section {
                id: clockSection
                title: "Clock"
                presets: clockPresets
                visible: root.editorWidget === "clock"

                PresetGrid {
                    id: clockPresets
                    kind: "clock"
                    options: [
                        { name: "Glance", sampleSize: 112, values: { clockStyle: "inline", clockFont: "", clockDate: true, clockWeekday: "show", clockTimeRatio: 100, clockDateRatio: 21, clockWeight: "light", clockLetterSpacing: 4 } },
                        { name: "Ambxst", sampleSize: 240, values: { clockStyle: "offset", clockFont: "League Gothic", clockDate: true, clockWeekday: "show", clockTimeRatio: 100, clockDateRatio: 15, clockWeight: "regular", clockLetterSpacing: 0 } },
                        { name: "Stacked", sampleSize: 152, values: { clockStyle: "stacked", clockFont: "", clockDate: true, clockWeekday: "show", clockTimeRatio: 100, clockDateRatio: 24, clockWeight: "semibold", clockLetterSpacing: 0 } },
                        { name: "Orbit", sampleSize: 240, values: { clockStyle: "orbit", clockDate: false, clockWeekday: "hide", clockTimeRatio: 100, clockDateRatio: 10, clockWeight: "regular", clockLetterSpacing: 0 } }
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
                        WidgetToggle { label: "Show date"; helpText: "Display the calendar date beside the time."; key: "clockDate" }
                        WidgetToggle {
                            label: "Show weekday"
                            helpText: "Include the day of the week in the clock."
                            key: "clockWeekday"
                            value: root.settings.clockWeekday === "show"
                                || (root.settings.clockWeekday !== "hide" && root.settings.clockDate)
                            update: checked => root.setSetting(key, checked ? "show" : "hide")
                        }
                    }

                    ClockGroup {
                        WidgetToggle { label: "Show seconds"; helpText: "Include seconds in the clock."; key: "clockSeconds" }
                        WidgetToggle { label: "Show greeting"; helpText: "Show a greeting based on the time of day."; key: "clockGreeting" }
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
                                        helpText: modelData.value === "12h" ? "Use a 12-hour clock." : "Use a 24-hour clock."
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
                                    helpText: "Show AM or PM when using the 12-hour clock."
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
                                Layout.preferredWidth: formatOptions.implicitWidth
                            }
                        }

                        Choice {
                            label: "Font weight"
                            setting: "clockWeight"
                            controlWidth: formatOptions.implicitWidth
                            options: [["Preset default", "legacy"], ["Light", "light"], ["Regular", "regular"],
                                      ["Medium", "medium"], ["Semibold", "semibold"], ["Bold", "bold"], ["Black", "black"]]
                        }
                    }

                    ClockGroup {
                        WidgetSlider {
                            label: "Date proportion"
                            key: "clockDateRatio"
                            minimum: 5
                            maximum: 65
                            displayValue: root.settings.clockDateRatio || (root.settings.clockDateSize > 0
                                ? root.settings.clockDateSize * 100 / Math.max(1, root.settings.clockSize) : 19)
                        }
                        WidgetSlider { label: "Letter spacing"; key: "clockLetterSpacing"; minimum: -10; maximum: 25; unit: "em" }
                    }
                }
            }

            Section {
                title: "Media player"
                presets: mediaPresets
                visible: root.editorWidget === "media"
                PresetGrid {
                    id: mediaPresets
                    kind: "media"
                    options: [
                        { name: "Ambxst", sampleSize: 100, values: { mediaStyle: "bg", mediaArtwork: true } },
                        { name: "Compact", sampleSize: 75, values: { mediaStyle: "compact", mediaArtwork: false } },
                        { name: "Cover", sampleSize: 100, values: { mediaStyle: "cover", mediaArtwork: false } },
                        { name: "Outline", sampleSize: 100, values: { mediaStyle: "outline", mediaArtwork: false } }
                    ]
                }

                WidgetSlider {
                    label: "Background corner radius"
                    key: "mediaRadius"
                    minimum: 0
                    maximum: 70
                    unit: "px"
                    displayValue: root.settings.mediaRadius >= 0 ? root.settings.mediaRadius
                        : ["cover", "outline"].includes(root.settings.mediaStyle) ? 14
                        : Math.round((root.settings.mediaStyle === "pane" ? 112 : root.settings.mediaStyle === "ribbon" ? 66
                            : root.settings.mediaStyle === "compact" ? 76 : 96) * Config.roundness / 32)
                }
                WidgetSlider {
                    label: "Thumbnail size"
                    key: "mediaThumbnailRatio"
                    minimum: 20
                    maximum: 100
                    enabled: !["outline", "ribbon"].includes(root.settings.mediaStyle)
                    displayValue: root.settings.mediaThumbnailRatio >= 0 ? root.settings.mediaThumbnailRatio
                        : root.settings.mediaStyle === "cover" ? 95 : root.settings.mediaStyle === "pane" ? 80 : 100
                }
                WidgetSlider {
                    label: "Thumbnail corner radius"
                    key: "mediaThumbnailRadius"
                    minimum: 0
                    maximum: 52
                    unit: "px"
                    enabled: !["outline", "ribbon"].includes(root.settings.mediaStyle)
                    displayValue: root.settings.mediaThumbnailRadius >= 0 ? root.settings.mediaThumbnailRadius
                        : ["cover", "pane"].includes(root.settings.mediaStyle) ? 12
                        : Math.round((root.settings.mediaStyle === "compact" ? 44 : 64) * Config.roundness / 32)
                }
                WidgetToggle { label: "Blur thumbnail as background"; helpText: "Use blurred album artwork behind the media controls."; key: "mediaArtwork" }
            }

            Section {
                title: "Login"
                presets: loginPresets
                visible: root.editorWidget === "login"

                PresetGrid {
                    id: loginPresets
                    kind: "login"
                    options: [
                        { name: "Ambxst", sampleSize: 100, values: { loginStyle: "bg", loginAvatar: true } },
                        { name: "Minimal", sampleSize: 90, values: { loginStyle: "plain", loginAvatar: false } },
                        { name: "Profile", sampleSize: 130, values: { loginStyle: "pane", loginAvatar: true } },
                        { name: "Badge", sampleSize: 100, values: { loginStyle: "badge", loginAvatar: true } },
                        { name: "Underline", sampleSize: 100, values: { loginStyle: "line", loginAvatar: false } },
                        { name: "Sign-in card", sampleSize: 100, values: { loginStyle: "card", loginAvatar: false } }
                    ]
                }

                WidgetToggle {
                    label: "Show profile picture"
                    key: "loginAvatar"
                    helpText: "Display your profile picture on the login widget."
                }
            }

            Section {
                title: "Appearance"
                visible: root.editorWidget !== ""

                WidgetToggle {
                    label: "Drop shadow"
                    helpText: "Add a soft shadow behind this widget."
                    key: root.editorWidget + "Shadow"
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
