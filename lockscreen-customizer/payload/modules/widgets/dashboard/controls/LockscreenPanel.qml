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
import "../../../../modules/lockscreen/widgets" as Widgets
import qs.modules.theme
import "../../../../config/defaults/lockscreen.js" as Defaults
import "../../../../modules/lockscreen/LockscreenPlacement.js" as Placement
import "../../../../modules/lockscreen/LockscreenPresets.js" as Presets
import "../../../../modules/lockscreen/LockscreenCustomization.js" as Customization

Control {
    id: root

    property string editorWidget: ""
    property var editorSettings
    property string editorPart: ""
    property Item editorTarget
    property string editorPage: "presets"
    readonly property var editorPages: [
        ["Presets", "presets"], ["Content", "content"], ["Parts", "parts"], ["Style", "appearance"]
    ]

    function showEditorPage(pageKey) {
        editorPage = pageKey;
        if (viewport)
            viewport.contentY = 0;
    }
    signal editorPartSelected(string part)
    signal editorPartGuideChanged(string axis)
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
        property color swatchColor: "transparent"
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

                Rectangle {
                    visible: action.swatchColor.a > 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: width
                    radius: 4
                    color: action.swatchColor
                    border.color: Qt.alpha(actionLabel.foreground, 0.55)
                    antialiasing: true
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

    component ColorActions: RowLayout {
        id: colorActions
        required property bool overridden
        required property color currentColor
        property string customLabel: "Custom color"
        signal resetColor()
        signal chooseColor()

        Layout.fillWidth: true
        uniformCellSizes: true
        spacing: 8

        ActionButton {
            Layout.fillWidth: true
            label: "Default"
            accent: !colorActions.overridden
            helpText: "Restore the preset color."
            onClicked: colorActions.resetColor()
        }

        ActionButton {
            Layout.fillWidth: true
            label: colorActions.customLabel
            swatchColor: colorActions.currentColor
            accent: colorActions.overridden
            helpText: "Pick a custom color."
            onClicked: colorActions.chooseColor()
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

    component OptionChoice: SettingRow {
        id: choice
        required property var options
        required property string selectedValue
        property string helpText: ""
        signal valueSelected(string value)

        FlatCombo {
            Layout.preferredWidth: 152
            model: choice.options.map(option => option[0])
            currentIndex: Math.max(0, choice.options.findIndex(option => option[1] === choice.selectedValue))
            helpText: choice.helpText
            Accessible.name: choice.label
            onActivated: index => choice.valueSelected(choice.options[index][1])
        }
    }

    component FontPicker: FlatCombo {
        id: fontPicker
        property string selectedFamily: root.settings.clockFont
        property string defaultLabel: "Shell font"
        property var updateFamily: family => root.setSetting("clockFont", family)
        property var families: []
        readonly property var matchingFamilies: [...new Set(["", fontPicker.selectedFamily, ...families])]
            .filter(family => (family || fontPicker.defaultLabel).toLowerCase().includes((fontSearch?.text || "").trim().toLowerCase()))

        model: matchingFamilies.map(family => family || fontPicker.defaultLabel)
        currentIndex: matchingFamilies.indexOf(selectedFamily)
        displayText: selectedFamily || defaultLabel
        helpText: "Search for a font or use the shell font."
        Accessible.name: "Clock font family"
        onActivated: index => updateFamily(matchingFamilies[index])

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
        property string key: ""
        required property int minimum
        required property int maximum
        property string unit: "%"
        property string helpText: ""
        property var snapValue
        property alias pressed: slider.pressed
        property real displayValue: root.settings[key] ?? minimum
        property var update: value => root.setSetting(key, value)
        readonly property real trackWidth: Math.round(Math.min(220, viewport.width * 0.28))
        readonly property real trackOrigin: unit === "%" && minimum < 0 && maximum > 0
            ? -minimum / (maximum - minimum) : 0

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
            Binding on value {
                when: !slider.pressed
                value: row.displayValue
                restoreMode: Binding.RestoreNone
            }
            Accessible.name: row.label
            ToolTip.text: row.helpText
            ToolTip.visible: hovered && row.helpText !== ""
            ToolTip.delay: 500
            onMoved: {
                const next = pressed && row.snapValue ? row.snapValue(Math.round(value)) : Math.round(value);
                if (pressed && value !== next)
                    value = next;
                row.update(next);
            }

            background: Rectangle {
                x: slider.leftPadding
                y: (slider.height - height) / 2
                width: slider.availableWidth
                height: 4
                radius: 2
                color: Colors.outlineVariant

                Rectangle {
                    x: Math.min(slider.visualPosition, row.trackOrigin) * parent.width
                    width: Math.abs(slider.visualPosition - row.trackOrigin) * parent.width
                    height: parent.height
                    radius: 2
                    color: Colors.primary
                }

                Rectangle {
                    visible: row.trackOrigin > 0
                    x: (parent.width - width) * row.trackOrigin
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1
                    height: 7
                    color: Colors.outline
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
        id: customColorPicker
        property string pickerTitle: ""
        property var applyColor
        property real hue: 0
        property real saturation: 0
        property real lightness: 1
        readonly property color draftColor: Qt.hsla(hue, saturation, lightness, 1)

        function openFor(initialColor: color, title: string, apply: var) {
            pickerTitle = title;
            applyColor = apply;
            hue = Math.max(0, initialColor.hslHue);
            saturation = initialColor.hslSaturation;
            lightness = initialColor.hslLightness;
            open();
        }

        function trackColor(channel, value) {
            switch (channel) {
            case "hue": return Qt.hsla(value, 1, 0.5, 1);
            case "saturation": return Qt.hsla(hue, value, lightness, 1);
            default: return Qt.hsla(hue, saturation, value, 1);
            }
        }

        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(320, (parent?.width ?? root.width) - 24)
        modal: true
        focus: true
        padding: 14
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: Colors.surfaceContainerHigh
            border.color: Colors.outlineVariant
            radius: 10
        }

        contentItem: ColumnLayout {
            spacing: 8

            Label {
                text: customColorPicker.pickerTitle
                color: Colors.overSurface
                font.bold: true
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                radius: 8
                color: customColorPicker.draftColor

                Label {
                    anchors.centerIn: parent
                    text: parent.color.toString().toUpperCase()
                    font.bold: true
                    font.pixelSize: Styling.fontSize(3)
                    color: (0.2126 * parent.color.r + 0.7152 * parent.color.g + 0.0722 * parent.color.b) > 0.56
                        ? "black" : "white"
                }
            }

            Repeater {
                model: [
                    { label: "Hue", key: "hue", maximum: 360, unit: "°" },
                    { label: "Saturation", key: "saturation", maximum: 100, unit: "%" },
                    { label: "Lightness", key: "lightness", maximum: 100, unit: "%" }
                ]
                delegate: ColumnLayout {
                    id: channel
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            Layout.fillWidth: true
                            text: channel.modelData.label
                            color: Colors.overSurface
                        }
                        Label {
                            text: Math.round(hslSlider.value * channel.modelData.maximum) + channel.modelData.unit
                            color: Colors.overSurfaceVariant
                        }
                    }

                    Basic.Slider {
                        id: hslSlider
                        Layout.fillWidth: true
                        implicitHeight: 24
                        from: 0
                        to: 1
                        stepSize: 1 / channel.modelData.maximum
                        value: customColorPicker[channel.modelData.key]
                        Accessible.name: channel.modelData.label
                        onMoved: customColorPicker[channel.modelData.key] = value

                        background: Rectangle {
                            x: hslSlider.leftPadding
                            y: (hslSlider.height - height) / 2
                            width: hslSlider.availableWidth
                            height: 14
                            radius: height / 2
                            antialiasing: true
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: customColorPicker.trackColor(channel.modelData.key, 0) }
                                GradientStop { position: 1 / 6; color: customColorPicker.trackColor(channel.modelData.key, 1 / 6) }
                                GradientStop { position: 2 / 6; color: customColorPicker.trackColor(channel.modelData.key, 2 / 6) }
                                GradientStop { position: 3 / 6; color: customColorPicker.trackColor(channel.modelData.key, 3 / 6) }
                                GradientStop { position: 4 / 6; color: customColorPicker.trackColor(channel.modelData.key, 4 / 6) }
                                GradientStop { position: 5 / 6; color: customColorPicker.trackColor(channel.modelData.key, 5 / 6) }
                                GradientStop { position: 1; color: customColorPicker.trackColor(channel.modelData.key, 1) }
                            }
                        }

                        handle: Rectangle {
                            x: hslSlider.leftPadding + hslSlider.visualPosition * (hslSlider.availableWidth - width)
                            y: (hslSlider.height - height) / 2
                            width: 20
                            height: width
                            radius: width / 2
                            border.width: hslSlider.visualFocus ? 3 : 2
                            border.color: "white"
                            color: customColorPicker.trackColor(channel.modelData.key, hslSlider.value)
                            antialiasing: true
                        }
                    }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight

                ActionButton {
                    label: "Cancel"
                    helpText: "Close without changing the color."
                    onClicked: customColorPicker.close()
                }
                ActionButton {
                    label: "Use color"
                    helpText: "Apply this custom color."
                    onClicked: {
                        customColorPicker.applyColor(customColorPicker.draftColor.toString());
                        customColorPicker.close();
                    }
                }
            }
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
        width: Math.max(0, Math.min(340, (parent?.width ?? root.width) - 24))
        modal: true
        focus: true
        padding: 16
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
            spacing: 10

            Label {
                text: presetNameDialog.targetPreset ? "Rename preset" : "Save to preset"
                color: Colors.overSurface
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(2)
                font.bold: true
            }

            Basic.TextField {
                id: presetName
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                leftPadding: 10
                rightPadding: 10
                maximumLength: 64
                selectByMouse: true
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(0)
                color: Colors.overSurface
                placeholderTextColor: Colors.overSurfaceVariant
                selectionColor: Colors.primary
                selectedTextColor: Colors.overPrimary
                background: Rectangle {
                    color: Colors.surfaceContainer
                    border.color: presetNameDialog.duplicateName ? Colors.error
                        : presetName.activeFocus ? Colors.primary : Colors.outlineVariant
                    radius: 6
                }
                placeholderText: "Preset name"
                Accessible.name: placeholderText
                onAccepted: presetNameDialog.commitName()
            }

            Label {
                Layout.fillWidth: true
                opacity: presetNameDialog.duplicateName ? 1 : 0
                text: "That preset name is already in use."
                color: Colors.error
            }

            RowLayout {
                Layout.fillWidth: true
                uniformCellSizes: true
                spacing: 8

                ActionButton {
                    Layout.fillWidth: true
                    implicitHeight: 34
                    label: "Cancel"
                    helpText: "Close without saving the name."
                    onClicked: presetNameDialog.close()
                }
                ActionButton {
                    Layout.fillWidth: true
                    implicitHeight: 34
                    label: presetNameDialog.targetPreset ? "Rename" : "Save"
                    accent: enabled
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
                const builtin = option.id ?? option.values[styleKey];
                const recordIndex = records.findIndex(record => record?.schemaVersion === Presets.version
                    && record.widget === kind && record.builtin === builtin && typeof record.name === "string");
                return Object.assign({}, option, {
                    builtin, recordIndex, name: records[recordIndex]?.name ?? option.name,
                    values: Object.assign({
                        [kind + "PartStyles"]: kind === "clock" ? Customization.clockPartStyles("{}", builtin) : "{}",
                        [kind + "Appearance"]: "{}"
                    },
                        kind === "media" ? { mediaLayoutOptions: "{}" }
                        : kind === "login" ? { loginArrangement: "preset" } : {}, option.values)
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
                            readonly property var settings: Object.assign({}, root.settings,
                                preset.modelData.builtin ? { [grid.kind + "Frame"]: "{}" } : {}, preset.modelData.values)
                            sourceComponent: grid.kind === "clock" ? clockSample
                                : grid.kind === "media" ? mediaSample
                                : grid.kind === "visualizer" ? visualizerSample : loginSample

                            Component {
                                id: clockSample

                                Item {
                                    Widgets.LockscreenClock {
                                        anchors.centerIn: parent
                                        settings: !preset.modelData.builtin ? sample.settings : Object.assign({}, sample.settings, {
                                            clockSize: preset.modelData.sampleSize, clockSeconds: false, clockGreeting: false, clockFormat: "24h",
                                            clockDateRatio: Math.max(23, sample.settings.clockDateRatio)
                                        })
                                        live: false
                                        renderScale: Math.min(parent.width / Math.max(1, naturalWidth),
                                                              parent.height / Math.max(1, naturalHeight))
                                    }
                                }
                            }

                            Component {
                                id: mediaSample

                                Item {
                                    Widgets.LockscreenMedia {
                                        anchors.centerIn: parent
                                        settings: sample.settings
                                        sample: true
                                        renderScale: Math.max(0.01, Math.min(parent.width / (designWidth * 1.17),
                                                        parent.height / (designHeight * 1.25)) * Math.min(1.25, (preset.modelData.sampleSize ?? 100) / 100))
                                    }
                                }
                            }

                            Component {
                                id: visualizerSample

                                Item {
                                    Widgets.LockscreenVisualizer {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        settings: sample.settings
                                        sample: true
                                    }
                                }
                            }

                            Component {
                                id: loginSample

                                Item {
                                    Widgets.LockscreenLogin {
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

    onEditorWidgetChanged: showEditorPage(editorPart ? "parts" : "presets")
    onEditorPartChanged: if (editorPart) showEditorPage("parts")

    topPadding: inspectorTabs.visible ? inspectorTabs.height + 9 : 0

    RowLayout {
        id: inspectorTabs
        visible: root.editorWidget !== ""
        x: (parent.width - width) / 2
        width: Math.max(0, parent.width - 12)
        y: 0
        spacing: 4
        z: 1
        uniformCellSizes: true

        Repeater {
            model: root.editorPages.filter(page => {
                if (page[1] === "content")
                    return root.editorWidget === "clock" || root.editorWidget === "media";
                return page[1] !== "parts" || root.editorWidget !== "visualizer";
            })

            ActionButton {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 32
                label: modelData[0]
                helpText: "Open " + label.toLowerCase() + " settings."
                accent: root.editorPage === modelData[1]
                Accessible.checkable: true
                Accessible.checked: accent
                onClicked: root.showEditorPage(modelData[1])
            }
        }
    }

    contentItem: Flickable {
        id: viewport
        contentWidth: width
        contentHeight: page.y + page.height + 14 + (!root.editorWidget && root.dirty ? saveBar.height + 12 : 0)
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
                        Layout.preferredWidth: 132
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
                title: "Presets"
                visible: root.editorWidget !== "" && root.editorPage === "presets"
                presets: editorPresets

                PresetGrid {
                    id: editorPresets
                    kind: root.editorWidget
                    options: ({
                        clock: [
                        { name: "Glance", sampleSize: 112, values: { clockStyle: "inline", clockFont: "", clockDate: true, clockWeekday: "show", clockTimeRatio: 100, clockDateRatio: 21, clockWeight: "light", clockLetterSpacing: 4 } },
                        { name: "Ambxst", sampleSize: 240, values: { clockStyle: "offset", clockFont: "League Gothic", clockDate: true, clockWeekday: "show", clockTimeRatio: 100, clockDateRatio: 15, clockWeight: "regular", clockLetterSpacing: 0 } },
                        { name: "Stacked", sampleSize: 152, values: { clockStyle: "stacked", clockFont: "", clockDate: true, clockWeekday: "show", clockTimeRatio: 100, clockDateRatio: 24, clockWeight: "semibold", clockLetterSpacing: 0 } },
                        { name: "Orbit", sampleSize: 240, values: { clockStyle: "orbit", clockDate: false, clockWeekday: "hide", clockTimeRatio: 100, clockDateRatio: 10, clockWeight: "regular", clockLetterSpacing: 0 } }
                    ],
                        media: [
                        { name: "Ambxst", sampleSize: 100, values: { mediaStyle: "bg", mediaArtwork: true } },
                        { name: "Compact", sampleSize: 75, values: { mediaStyle: "compact", mediaArtwork: false } },
                        { name: "Cover", sampleSize: 100, values: { mediaStyle: "cover", mediaArtwork: false } },
                        { name: "Outline", sampleSize: 100, values: { mediaStyle: "outline", mediaArtwork: false } },
                        { id: "stacked-cover", name: "Stacked cover", sampleSize: 100, values: {
                            mediaStyle: "cover", mediaArtwork: false,
                            mediaLayoutOptions: '{"artPlacement":"above","playButton":"controls","textAlignment":"center","times":true}'
                        } }
                    ],
                        login: [
                        { name: "Ambxst", sampleSize: 100, values: { loginStyle: "bg", loginAvatar: true } },
                        { name: "Minimal", sampleSize: 90, values: { loginStyle: "plain", loginAvatar: false } },
                        { name: "Profile", sampleSize: 130, values: { loginStyle: "pane", loginAvatar: true } },
                        { name: "Badge", sampleSize: 100, values: { loginStyle: "badge", loginAvatar: true } },
                        { name: "Underline", sampleSize: 100, values: { loginStyle: "line", loginAvatar: false } },
                        { name: "Sign-in card", sampleSize: 100, values: { loginStyle: "card", loginAvatar: false } }
                    ],
                        visualizer: [
                        { name: "Gradient wave", values: { visualizerStyle: "wave" } },
                        { name: "Rounded bars", values: { visualizerStyle: "bars" } },
                        { name: "Mirrored bars", values: { visualizerStyle: "mirror" } },
                        { name: "Ripple ring", values: { visualizerStyle: "ring" } },
                        { name: "Spectrum dots", values: { visualizerStyle: "dots" } }
                    ]
                    })[kind] ?? []
                }
            }

            Section {
                id: partSection
                title: "Widget parts"
                visible: root.editorWidget !== "" && root.editorPage === "parts"
                readonly property var options: [["", "Choose a part"], ...(Customization.parts[root.editorWidget] ?? [])
                    .filter(option => ["art", "avatar"].includes(option[0])
                        || (root.editorTarget?.editableParts?.[option[0]]?.visible ?? true))]
                readonly property var selected: options.find(option => option[0] === root.editorPart) ?? options[0]
                readonly property Item targetPart: root.editorTarget?.editableParts?.[selected[0]] ?? null
                readonly property bool artworkSelected: root.editorWidget === "media" && selected[0] === "art"
                readonly property bool avatarSelected: root.editorWidget === "login" && selected[0] === "avatar"
                readonly property bool showPartColor: selected[0] !== "" && (!artworkSelected || mediaSection.hasArtwork)
                    && (!avatarSelected || root.settings.loginAvatar)
                readonly property bool clockPart: root.editorWidget === "clock" && targetPart !== null
                readonly property bool movesHorizontally: clockPart
                    && (selected[0] !== "dial" || root.editorTarget.width - targetPart.width > 1)
                readonly property bool movesVertically: clockPart
                    && (selected[0] !== "dial" || root.editorTarget.height - targetPart.height > 1)
                readonly property var styles: Customization.read(root.settings[root.editorWidget + "PartStyles"])
                readonly property var currentStyle: Customization.part(styles, selected[0])
                readonly property bool scalable: selected[2] || (avatarSelected && root.settings.loginAvatar)

                function positionPercent(axis) {
                    return Math.round(targetPart?.[axis + "Position"] ?? 0);
                }

                function movePart(axis, value) {
                    if (!clockPart)
                        return;
                    const presetValue = root.editorTarget.presetPosition(targetPart, axis);
                    root.setSetting(root.editorWidget + "PartStyles",
                        Customization.editClockPosition(styles, selected[0], axis, value, presetValue));
                }

                function change(property, value) {
                    root.setSetting(root.editorWidget + "PartStyles",
                                    Customization.editPart(styles, selected[0], property, value));
                }

                FlatCombo {
                    Layout.fillWidth: true
                    model: partSection.options.map(option => option[1])
                    currentIndex: partSection.options.indexOf(partSection.selected)
                    helpText: "Choose a part here or click it on the canvas."
                    Accessible.name: "Widget part"
                    onActivated: index => root.editorPartSelected(partSection.options[index][0])
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: partSection.artworkSelected
                    spacing: 8

                    WidgetToggle {
                        label: "Show album art"
                        key: "artwork"
                        value: mediaSection.hasArtwork
                        helpText: "Show the album cover."
                        update: enabled => mediaSection.change("artwork", enabled === mediaSection.defaultArtwork ? undefined : enabled)
                    }

                    OptionChoice {
                        label: "Artwork position"
                        selectedValue: mediaSection.options.artPlacement ?? "auto"
                        visible: mediaSection.hasArtwork
                        options: [["Automatic", "auto"], ["Above track", "above"], ["Left", "left"], ["Right", "right"]]
                        helpText: "Automatic puts artwork on top in narrow, tall cards."
                        onValueSelected: value => mediaSection.change("artPlacement", value === "auto" ? undefined : value)
                    }

                    OptionChoice {
                        label: "Play button"
                        selectedValue: mediaSection.options.playButton ?? "art"
                        visible: mediaSection.hasArtwork && (mediaSection.options.transport ?? true)
                        options: [["On artwork", "art"], ["In controls", "controls"]]
                        helpText: "Choose where the play and pause control appears."
                        onValueSelected: value => mediaSection.change("playButton", value === "art" ? undefined : value)
                    }

                    WidgetSlider {
                        label: "Artwork gap"
                        visible: mediaSection.hasArtwork
                        minimum: 4
                        maximum: 28
                        unit: "px"
                        displayValue: mediaSection.options.gap ?? 16
                        update: value => mediaSection.change("gap", value === 16 ? undefined : value)
                    }

                    WidgetSlider {
                        label: "Artwork size"
                        visible: mediaSection.hasArtwork
                        key: "mediaThumbnailRatio"
                        minimum: 20
                        maximum: 100
                        displayValue: root.settings.mediaThumbnailRatio >= 0 ? root.settings.mediaThumbnailRatio
                            : mediaSection.topArtwork ? (mediaSection.options.wideArtwork === false ? 46 : 75)
                            : root.settings.mediaStyle === "cover" ? 95 : root.settings.mediaStyle === "pane" ? 80 : 100
                    }
                    WidgetSlider {
                        label: "Artwork corner radius"
                        key: "mediaThumbnailRadius"
                        minimum: 0
                        maximum: 52
                        unit: "px"
                        visible: mediaSection.hasArtwork
                        displayValue: root.settings.mediaThumbnailRadius >= 0 ? root.settings.mediaThumbnailRadius
                            : ["cover", "pane"].includes(root.settings.mediaStyle) ? 12
                            : Math.round((root.settings.mediaStyle === "compact" ? 44 : 64) * Config.roundness / 32)
                    }
                    WidgetToggle {
                        label: "Show entire cover"
                        key: "fitArtwork"
                        visible: mediaSection.hasArtwork
                        value: mediaSection.options.fitArtwork ?? false
                        update: checked => mediaSection.change(key, checked || undefined)
                        helpText: "Fit the cover inside its frame instead of cropping its edges."
                    }
                }

                Label {
                    visible: partSection.selected[2] === true
                    Layout.topMargin: 3
                    text: "Typography"
                    color: Colors.overSurfaceVariant
                    font.bold: true
                }

                SettingRow {
                    label: "Font"
                    visible: partSection.selected[2] === true

                    FontPicker {
                        Layout.preferredWidth: 160
                        selectedFamily: partSection.currentStyle.font ?? ""
                        defaultLabel: "Preset font"
                        updateFamily: font => partSection.change("font", font || undefined)
                        helpText: "Choose a font for this part."
                        Accessible.name: "Part font"
                    }
                }

                SettingRow {
                    label: "Weight"
                    visible: partSection.selected[2] === true

                    FlatCombo {
                        readonly property var weights: [["Preset weight", undefined], ["Light", Font.Light],
                            ["Regular", Font.Normal], ["Medium", Font.Medium],
                            ["Semibold", Font.DemiBold], ["Bold", Font.Bold], ["Black", Font.Black]]
                        Layout.preferredWidth: 160
                        model: weights.map(option => option[0])
                        currentIndex: Math.max(0, weights.findIndex(option => option[1] === partSection.currentStyle.weight))
                        helpText: "Choose the weight of this part’s text."
                        Accessible.name: "Part font weight"
                        onActivated: index => partSection.change("weight", weights[index][1])
                    }
                }

                WidgetSlider {
                    label: "Relative size"
                    visible: partSection.scalable
                    minimum: 65
                    maximum: 150
                    displayValue: partSection.currentStyle.scale ?? 100
                    update: value => partSection.change("scale", value === 100 ? undefined : value)
                }

                WidgetSlider {
                    label: "Letter spacing"
                    visible: partSection.selected[2] === true
                    minimum: -10
                    maximum: 25
                    unit: "em"
                    displayValue: partSection.currentStyle.spacing ?? (root.editorWidget === "clock" ? root.settings.clockLetterSpacing : 0)
                    update: value => partSection.change("spacing", value)
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: partSection.avatarSelected
                    spacing: 8

                    WidgetToggle {
                        label: "Show profile picture"
                        key: "loginAvatar"
                        helpText: "Display your profile picture on the login widget."
                    }

                    OptionChoice {
                        label: "Profile picture position"
                        selectedValue: root.settings.loginArrangement
                        visible: root.settings.loginAvatar
                        options: [["Preset (adaptive)", "preset"], ["Above password", "above"], ["Left of password", "left"], ["Right of password", "right"]]
                        helpText: "The adaptive preset places the picture above the field in narrow, tall widgets."
                        onValueSelected: value => root.setSetting("loginArrangement", value)
                    }
                }

                WidgetSlider {
                    label: "Profile rounding"
                    visible: partSection.avatarSelected && root.settings.loginAvatar
                    minimum: 0
                    maximum: 100
                    displayValue: partSection.currentStyle.radius ?? Math.round(100 * Config.roundness / 16)
                    update: value => partSection.change("radius", value)
                }

                SettingRow {
                    label: "Placeholder"
                    visible: root.editorWidget === "login" && partSection.selected[0] === "password"

                    Basic.TextField {
                        Layout.preferredWidth: 160
                        text: partSection.currentStyle.placeholder ?? ""
                        placeholderText: "Preset text"
                        maximumLength: 80
                        Accessible.name: "Password field placeholder"
                        onTextEdited: partSection.change("placeholder", text || undefined)
                    }
                }

                Label {
                    visible: partSection.showPartColor
                    Layout.topMargin: 3
                    text: partSection.artworkSelected ? "Outline color" : "Color"
                    color: Colors.overSurfaceVariant
                    font.bold: true
                }

                ColorActions {
                    visible: partSection.showPartColor
                    overridden: Boolean(partSection.currentStyle.color)
                    currentColor: Customization.color(partSection.currentStyle, Colors.primary, Colors)
                    onResetColor: partSection.change("color", undefined)
                    onChooseColor: {
                        const widget = root.editorWidget;
                        const key = root.editorPart;
                        customColorPicker.openFor(currentColor, partSection.selected[1] + " color", color => {
                            const setting = widget + "PartStyles";
                            root.setSetting(setting, Customization.editPart(Customization.read(root.settings[setting]), key, "color", color));
                        });
                    }
                }

                Label {
                    visible: partSection.movesHorizontally || partSection.movesVertically
                    Layout.topMargin: 3
                    text: "Position in widget"
                    color: Colors.overSurfaceVariant
                    font.bold: true
                }

                WidgetSlider {
                    label: "Horizontal"
                    visible: partSection.movesHorizontally
                    minimum: -100
                    maximum: 100
                    helpText: "Zero centers this part. The ends of the slider align it to the frame edges."
                    snapValue: Customization.snapClockPosition
                    onPressedChanged: root.editorPartGuideChanged(pressed ? "x" : "")
                    displayValue: partSection.positionPercent("x")
                    update: value => partSection.movePart("x", value)
                }

                WidgetSlider {
                    label: "Vertical"
                    visible: partSection.movesVertically
                    minimum: -100
                    maximum: 100
                    helpText: "Zero centers this part. The ends of the slider align it to the frame edges."
                    snapValue: Customization.snapClockPosition
                    onPressedChanged: root.editorPartGuideChanged(pressed ? "y" : "")
                    displayValue: partSection.positionPercent("y")
                    update: value => partSection.movePart("y", value)
                }

                ActionButton {
                    Layout.alignment: Qt.AlignRight
                    label: "Reset part to preset"
                    helpText: "Restore the preset appearance for the selected part."
                    visible: partSection.selected[0] !== "" && Object.keys(partSection.currentStyle).length > 0
                    onClicked: partSection.change("", undefined)
                }
            }

            Section {
                id: clockSection
                title: "Clock"
                visible: root.editorWidget === "clock" && root.editorPage === "content"

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

            }

            Section {
                id: mediaSection
                title: "Playback and track"
                visible: root.editorWidget === "media" && root.editorPage === "content"
                readonly property var options: Customization.read(root.settings.mediaLayoutOptions)
                readonly property string style: root.settings.mediaStyle
                readonly property bool compactStyle: ["compact", "ribbon"].includes(style)
                readonly property bool defaultArtwork: !["outline", "ribbon"].includes(style)
                readonly property bool hasArtwork: options.artwork ?? defaultArtwork
                readonly property bool topArtwork: options.artPlacement === "above" || (root.editorTarget?.artworkAbove ?? false)

                function change(key, value) {
                    root.setSetting("mediaLayoutOptions", Customization.editOption(options, key, value));
                }

                OptionChoice {
                    label: "Text alignment"
                    selectedValue: mediaSection.options.textAlignment ?? "left"
                    options: [["Left", "left"], ["Center", "center"], ["Right", "right"]]
                    helpText: "Align the track title, artist, and heading."
                    onValueSelected: value => mediaSection.change("textAlignment", value === "left" ? undefined : value)
                }

                Repeater {
                    model: root.editorWidget === "media" ? [
                        ["heading", "Now playing heading", mediaSection.style === "pane", "Show a label above the track."],
                        ["title", "Track title", true, "Show the name of the current track."],
                        ["artist", "Artist", !mediaSection.compactStyle, "Show the performer when provided by the player."],
                        ["progress", "Progress slider", true, "Show track progress and allow seeking when supported."],
                        ["times", "Elapsed time and duration", false, "Show the current position and total track length."],
                        ["transport", "Playback buttons", true, "Show play, pause, and track navigation."],
                        ["mode", "Shuffle and repeat", !mediaSection.compactStyle, "Show the playback mode button."],
                        ["app", "Player icon", true, "Show the app icon and player picker."]
                    ] : []

                    delegate: WidgetToggle {
                        required property var modelData
                        key: modelData[0]
                        label: modelData[1]
                        value: mediaSection.options[key] ?? modelData[2]
                        helpText: modelData[3]
                        update: checked => mediaSection.change(key, checked === modelData[2] ? undefined : checked)
                    }
                }
            }

            Section {
                id: visualizerSection
                title: "Audio visualizer"
                readonly property var styles: Customization.read(root.settings.visualizerPartStyles)
                readonly property var graphStyle: Customization.part(styles, "graph")

                function setColor(useShell, color) {
                    root.edit({ visualizerUseShellColors: useShell, visualizerColor: color,
                                visualizerPartStyles: Customization.editPart(styles, "graph", "color", undefined) });
                }

                visible: root.editorWidget === "visualizer" && root.editorPage === "appearance"


                RowLayout {
                    Layout.fillWidth: true
                    uniformCellSizes: true
                    spacing: 8

                    ActionButton {
                        Layout.fillWidth: true
                        label: "Use shell colors"
                        helpText: "Follow the shell theme’s primary color."
                        accent: root.settings.visualizerUseShellColors && !visualizerSection.graphStyle.color
                        Accessible.checkable: true
                        Accessible.checked: accent
                        onClicked: visualizerSection.setColor(true, root.settings.visualizerColor)
                    }

                    ActionButton {
                        Layout.fillWidth: true
                        label: "Custom color"
                        swatchColor: Customization.color(visualizerSection.graphStyle, root.settings.visualizerColor, Colors)
                        accent: !root.settings.visualizerUseShellColors || Boolean(visualizerSection.graphStyle.color)
                        Accessible.checkable: true
                        Accessible.checked: accent
                        helpText: "Choose a color for this visualizer."
                        onClicked: customColorPicker.openFor(swatchColor, "Visualizer color",
                            color => visualizerSection.setColor(false, color))
                    }
                }
            }

            Section {
                id: appearanceSection
                title: "Appearance"
                visible: root.editorWidget !== "" && root.editorPage === "appearance"
                readonly property string setting: root.editorWidget + "Appearance"
                readonly property var style: Customization.read(root.settings[setting])

                function change(key, value) {
                    root.setSetting(setting, Customization.editOption(style, key, value));
                }

                function pick(key, fallback, title) {
                    const target = setting;
                    customColorPicker.openFor(Customization.color({ color: style[key] }, fallback, Colors), title, color =>
                        root.setSetting(target, Customization.editOption(Customization.read(root.settings[target]), key, color)));
                }

                WidgetSlider {
                    label: "Widget opacity"
                    minimum: 15
                    maximum: 100
                    displayValue: appearanceSection.style.opacity ?? 100
                    update: value => appearanceSection.change("opacity", value === 100 ? undefined : value)
                }

                OptionChoice {
                    label: "Background fill"
                    selectedValue: appearanceSection.style.fill ?? "preset"
                    options: [["Preset", "preset"], ["Solid", "solid"], ["Transparent", "none"]]
                    helpText: "Keep the preset background, add a solid fill, or make it transparent."
                    onValueSelected: value => appearanceSection.change("fill", value === "preset" ? undefined : value)
                }

                ColorActions {
                    visible: appearanceSection.style.fill === "solid"
                    overridden: Boolean(appearanceSection.style.fillColor)
                    currentColor: Customization.color({ color: appearanceSection.style.fillColor }, Colors.surfaceContainer, Colors)
                    customLabel: "Fill color"
                    onResetColor: appearanceSection.change("fillColor", undefined)
                    onChooseColor: appearanceSection.pick("fillColor", Colors.surfaceContainer, "Background fill color")
                }

                WidgetSlider {
                    label: "Fill opacity"
                    visible: appearanceSection.style.fill === "solid"
                    minimum: 0
                    maximum: 100
                    displayValue: appearanceSection.style.fillOpacity ?? 85
                    update: value => appearanceSection.change("fillOpacity", value === 85 ? undefined : value)
                }

                WidgetToggle {
                    label: "Blur artwork behind card"
                    visible: root.editorWidget === "media" && (appearanceSection.style.fill ?? "preset") === "preset"
                    helpText: "Use blurred artwork when the background fill follows the preset."
                    key: "mediaArtwork"
                }

                WidgetToggle {
                    label: "Widget border"
                    key: "border"
                    value: appearanceSection.style.border ?? false
                    update: checked => appearanceSection.change(key, checked || undefined)
                    helpText: "Draw an outline around the widget."
                }

                ColorActions {
                    visible: Boolean(appearanceSection.style.border)
                    overridden: Boolean(appearanceSection.style.borderColor)
                    currentColor: Customization.color({ color: appearanceSection.style.borderColor }, Colors.outline, Colors)
                    customLabel: "Border color"
                    onResetColor: appearanceSection.change("borderColor", undefined)
                    onChooseColor: appearanceSection.pick("borderColor", Colors.outline, "Widget border color")
                }

                WidgetSlider {
                    label: "Border width"
                    visible: Boolean(appearanceSection.style.border)
                    minimum: 1
                    maximum: 8
                    unit: "px"
                    displayValue: appearanceSection.style.borderWidth ?? 1
                    update: value => appearanceSection.change("borderWidth", value === 1 ? undefined : value)
                }

                WidgetSlider {
                    label: "Corner radius"
                    minimum: 0
                    maximum: 80
                    unit: "px"
                    displayValue: appearanceSection.style.radius ?? (root.editorWidget === "media" && root.settings.mediaRadius >= 0
                        ? root.settings.mediaRadius : Config.roundness)
                    update: value => appearanceSection.change("radius", value)
                }

                WidgetToggle {
                    label: "Drop shadow"
                    helpText: "Add a soft shadow behind this widget."
                    key: root.editorWidget + "Shadow"
                }

                ActionButton {
                    Layout.alignment: Qt.AlignRight
                    label: "Reset appearance"
                    visible: Object.keys(appearanceSection.style).length > 0 || root.settings[root.editorWidget + "Shadow"] === true
                    onClicked: root.edit({ [appearanceSection.setting]: "{}", [root.editorWidget + "Shadow"]: false })
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
