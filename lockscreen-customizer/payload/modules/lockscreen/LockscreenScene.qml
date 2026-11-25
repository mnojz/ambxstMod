pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.corners
import qs.modules.theme
import qs.config
import "LockscreenPlacement.js" as Placement
import "LockscreenActions.js" as Actions
import "widgets" as Widgets

Item {
    id: root

    property var screen
    property bool authenticating: false
    property string username: preview ? "Enter password" : ""
    property bool preview: false
    property bool miniature: false
    property real designScale: 1
    property url videoPoster
    property Item activeEditHandle
    property var shortcutWidgets: ({})
    property bool editing: false
    property string selectedWidget: settings.clockVisible ? "clock" : "login"
    readonly property var widgetOptions: [
        { key: "clock", title: "Clock" },
        { key: "media", title: "Media player" },
        { key: "login", title: "Login" },
        { key: "visualizer", title: "Audio visualizer" },
        ...Actions.available.map(action => ({ key: "shortcut:" + action.id, title: action.label }))
    ]
    signal passwordSubmitted(string password)
    signal rejectionFinished()
    signal dismiss()
    signal layoutEdited(var values)
    signal toolsRequested(string key, Item handle)
    signal widgetInteracted(Item handle)
    signal contextMenuRequested(point position, string key)

    function hasWidget(key) {
        if (key === "login")
            return true;
        if (key.startsWith("shortcut:"))
            return Boolean(shortcutFor(key.slice(9)));
        return settings[key + "Visible"];
    }

    function setWidgetEnabled(key, enabled) {
        if (key === "login" || hasWidget(key) === enabled)
            return;
        if (key.startsWith("shortcut:"))
            layoutEdited({ shortcuts: Actions.setEnabled(Array.from(settings.shortcuts ?? []), key.slice(9), enabled) });
        else
            layoutEdited({ [key + "Visible"]: enabled });
        selectedWidget = enabled ? key : "login";
    }

    function focusPassword() {
        passwordContainer.focusPassword();
    }

    function rejectPassword() {
        passwordContainer.rejectPassword();
    }

    function coordinate(fraction, alignment, available, size) {
        return fraction >= 0 ? Math.max(0, available - size) * Math.min(1, fraction)
                             : Placement.offset(alignment, available, size, 32 * designScale);
    }

    function visualBounds(widget) {
        if (activeEditHandle?.widget === widget)
            return activeEditHandle.draft;
        return Qt.rect(widget.baseX, widget.baseY, widget.baseWidth * widget.baseScale, widget.baseHeight * widget.baseScale);
    }

    function shortcutFor(id) {
        return Array.from(settings.shortcuts ?? []).find(shortcut => shortcut?.id === id && shortcut.enabled !== false);
    }

    function placeShortcut(key, widget, x, y, requestedWidth) {
        const size = Math.max(50, Math.min(200, Math.round(requestedWidth * 100 / widget.baseWidth)));
        const scale = Placement.fit(widget.baseWidth, widget.baseHeight, width, height, size / 100);
        const maximumX = Math.max(1, width - widget.baseWidth * scale);
        const maximumY = Math.max(1, height - widget.baseHeight * scale);
        const next = Array.from(settings.shortcuts ?? []).map(shortcut => shortcut?.id === key ? {
            id: key, enabled: true, scale: size, x: Math.max(0, Math.min(1, x / maximumX)),
            y: Math.max(0, Math.min(1, y / maximumY))
        } : shortcut);
        layoutEdited({ shortcuts: next });
    }

    function placeWidget(key, widget, x, y, requestedWidth, requestedHeight) {
        if (key === "visualizer") {
            layoutEdited({
                visualizerWidth: Math.min(1, requestedWidth / Math.max(1, width)),
                visualizerHeight: Math.min(1, requestedHeight / Math.max(1, height)),
                visualizerX: x / Math.max(1, width - requestedWidth),
                visualizerY: y / Math.max(1, height - requestedHeight)
            });
            return;
        }
        if (key.startsWith("shortcut:")) {
            placeShortcut(key.slice(9), widget, x, y, requestedWidth);
            return;
        }
        const ratio = requestedWidth / Math.max(1, widget.baseWidth * widget.baseScale);
        const sizeKey = key === "clock" ? "clockSize" : key + "Scale";
        if (Math.abs(ratio - 1) > 0.001) {
            const current = settings[sizeKey];
            const requested = key === "clock" ? current * widget.baseScale * ratio / designScale : 100 * widget.baseScale * ratio;
            const minimum = key === "clock" ? 32 : key === "login" ? 75 : 65;
            layoutEdited({ [sizeKey]: Math.round(Math.max(minimum, Math.min(key === "clock" ? 480 : 160, requested))) });
        }
        const availableX = Math.max(1, width - widget.baseWidth * widget.baseScale);
        const availableY = Math.max(1, height - widget.baseHeight * widget.baseScale);
        layoutEdited({
            [key + "X"]: Math.max(0, Math.min(1, x / availableX)),
            [key + "Y"]: Math.max(0, Math.min(1, y / availableY))
        });
    }

    Keys.onEscapePressed: event => {
        if (root.preview) {
            event.accepted = true;
            root.dismiss();
        }
    }

    property var settings: Config.customLockscreen
    readonly property alias waitingForVideo: wallpaper.waitingForVideo
    readonly property alias hasCustomBackground: wallpaper.hasCustomBackground
    readonly property alias customWallpaper: wallpaper.customWallpaper

    function placement(value, fallback) {
        return (value === "legacy" ? fallback : value).split("-");
    }

    LockscreenWallpaper {
        id: wallpaper
        anchors.fill: parent
        screen: root.screen
        settings: root.settings
        preview: root.preview
        miniature: root.miniature
        designScale: root.designScale
        videoPoster: root.videoPoster
    }

    Widgets.LockscreenVisualizer {
        id: visualizer
        settings: root.settings
        visible: root.settings.visualizerVisible
        captureAudio: !root.miniature
        sample: root.miniature
        pixelScale: Math.max(0.01, root.designScale)
        readonly property real baseWidth: Math.max(0, Math.min(root.width, root.width * root.settings.visualizerWidth))
        readonly property real baseHeight: Math.max(0, Math.min(root.height, root.height * root.settings.visualizerHeight))
        readonly property real baseScale: 1
        readonly property real baseX: root.coordinate(root.settings.visualizerX, "center", root.width, baseWidth)
        readonly property real baseY: root.coordinate(root.settings.visualizerY, "bottom", root.height, baseHeight)
        readonly property rect bounds: root.visualBounds(visualizer)
        x: bounds.x
        y: bounds.y
        width: bounds.width
        height: bounds.height
        z: root.activeEditHandle?.widget === visualizer ? 12 : 9
    }

    Widgets.LockscreenClock {
        id: clockContainer
        z: root.activeEditHandle?.widget === clockContainer ? 12 : 10
        settings: root.settings
        visible: root.settings.clockVisible
        readonly property real baseWidth: designWidth
        readonly property real baseHeight: designHeight
        readonly property var position: root.placement(root.settings.clockPosition, "center-center")
        readonly property real baseScale: Placement.fit(baseWidth, baseHeight, parent.width, parent.height, root.designScale, 32 * root.designScale)
        transformOrigin: Item.TopLeft
        readonly property real baseX: root.coordinate(root.settings.clockX, position[1], parent.width, baseWidth * baseScale)
        readonly property real baseY: root.coordinate(root.settings.clockY, position[0], parent.height, baseHeight * baseScale)
        readonly property rect bounds: root.visualBounds(clockContainer)
        x: bounds.x
        y: bounds.y
        renderScale: bounds.width / Math.max(1, baseWidth)

    }

    Item {
        id: playerContainer
        z: root.activeEditHandle?.widget === playerContainer ? 12 : 10
        readonly property var position: root.placement(root.settings.mediaPosition, root.settings.position + "-left")
        readonly property real baseWidth: playerContent.designWidth
        readonly property real baseHeight: playerContent.designHeight
        width: playerContent.width
        height: playerContent.height
        readonly property real baseScale: Placement.fit(baseWidth, baseHeight, parent.width, parent.height,
            root.designScale * Math.max(65, Math.min(160, root.settings.mediaScale)) / 100, 32 * root.designScale)
        transformOrigin: Item.TopLeft
        readonly property real baseX: root.coordinate(root.settings.mediaX, position[1], parent.width, baseWidth * baseScale)
        readonly property real baseY: root.coordinate(root.settings.mediaY, position[0], parent.height, baseHeight * baseScale)
        readonly property rect bounds: root.visualBounds(playerContainer)
        x: bounds.x
        y: bounds.y
        visible: root.settings.mediaVisible

        Widgets.LockscreenMedia {
            id: playerContent
            settings: root.settings
            renderScale: Math.max(0.01, playerContainer.bounds.width / designWidth)
            sample: root.preview
        }
    }

    Widgets.LockscreenLogin {
        id: passwordContainer
        z: root.activeEditHandle?.widget === passwordContainer ? 12 : 11
        settings: root.settings
        username: root.username
        authenticating: root.authenticating
        animate: !root.preview
        renderScale: Math.max(0.01, bounds.width / baseWidth)
        readonly property real baseWidth: designWidth
        readonly property real baseHeight: designHeight
        interactive: !root.editing && !root.miniature
        readonly property var position: root.placement(root.settings.loginPosition, root.settings.position + "-center")
        readonly property real baseScale: Placement.fit(baseWidth, baseHeight, parent.width, parent.height,
            root.designScale * Math.max(75, Math.min(160, root.settings.loginScale)) / 100, 32 * root.designScale)
        transformOrigin: Item.TopLeft
        readonly property real baseX: root.coordinate(root.settings.loginX, position[1], parent.width, baseWidth * baseScale)
        readonly property real baseY: root.coordinate(root.settings.loginY, position[0], parent.height, baseHeight * baseScale)
        readonly property rect bounds: root.visualBounds(passwordContainer)
        x: bounds.x
        y: bounds.y


        onSubmitted: password => {
            if (root.preview)
                root.dismiss();
            else
                root.passwordSubmitted(password);
        }

        onRejectionFinished: root.rejectionFinished()
    }

    Repeater {
        model: Actions.available

        delegate: Widgets.LockscreenShortcut {
            id: shortcutButton
            required property var modelData
            readonly property var placement: root.shortcutFor(modelData.id)
            readonly property real baseWidth: designWidth
            readonly property real baseHeight: designHeight
            readonly property real baseScale: Placement.fit(baseWidth, baseHeight, root.width, root.height,
                root.designScale * Math.max(50, Math.min(200, placement?.scale ?? 100)) / 100, 32 * root.designScale)
            readonly property real baseX: root.coordinate(placement?.x ?? 0, "left", root.width, baseWidth * baseScale)
            readonly property real baseY: root.coordinate(placement?.y ?? 0, "top", root.height, baseHeight * baseScale)
            readonly property rect bounds: root.visualBounds(shortcutButton)
            shortcutAction: modelData
            usable: !root.preview && !root.authenticating && visible
            visible: placement !== undefined
            x: bounds.x
            y: bounds.y
            renderScale: Math.max(0.01, bounds.width / baseWidth)
            z: root.activeEditHandle?.widget === shortcutButton ? 12 : 9
        }

        onItemAdded: (index, item) => {
            const action = Actions.available[index];
            const next = Object.assign({}, root.shortcutWidgets);
            next[action.id] = item;
            root.shortcutWidgets = next;
        }
    }

    // Screen corners
    RoundCorner {

        visible: !root.miniature
        size: Styling.radius(4)
        anchors.left: parent.left
        anchors.top: parent.top
        corner: RoundCorner.CornerEnum.TopLeft
        z: 100
    }

    RoundCorner {

        visible: !root.miniature
        size: Styling.radius(4)
        anchors.right: parent.right
        anchors.top: parent.top
        corner: RoundCorner.CornerEnum.TopRight
        z: 100
    }

    RoundCorner {

        visible: !root.miniature
        size: Styling.radius(4)
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        corner: RoundCorner.CornerEnum.BottomLeft
        z: 100
    }

    RoundCorner {

        visible: !root.miniature
        size: Styling.radius(4)
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        corner: RoundCorner.CornerEnum.BottomRight
        z: 100
    }

    Loader {
        anchors.fill: parent
        active: root.editing
        z: 110
        sourceComponent: Item {
            id: editorLayer
            readonly property var widgets: root.widgetOptions.map(option => {
                const widget = option.key === "clock" ? clockContainer
                    : option.key === "media" ? playerContainer
                    : option.key === "login" ? passwordContainer
                    : option.key === "visualizer" ? visualizer : root.shortcutWidgets[option.key.slice(9)];
                return { key: option.key, title: option.title, widget };
            }).filter(entry => entry.widget)

            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: point => {
                    const position = point.position;
                    const hits = editorLayer.widgets.filter(entry => {
                        if (!entry.widget.visible)
                            return false;
                        const bounds = root.visualBounds(entry.widget);
                        return position.x >= bounds.x && position.x <= bounds.x + bounds.width
                            && position.y >= bounds.y && position.y <= bounds.y + bounds.height;
                    });
                    const target = hits.find(entry => entry.key === root.selectedWidget) ?? hits[hits.length - 1];
                    root.contextMenuRequested(position, target?.key ?? "");
                }
            }

            Rectangle {
                x: Math.round(parent.width / 2)
                width: 1
                height: parent.height
                color: Colors.primary
                opacity: 0.30
            }

            Rectangle {
                y: Math.round(parent.height / 2)
                width: parent.width
                height: 1
                color: Colors.primary
                opacity: 0.30
            }

            Repeater {
                model: editorLayer.widgets

                delegate: LockscreenEditorHandle {
                    id: handle
                    required property var modelData
                    widget: modelData.widget
                    visible: widget.visible
                    siblings: editorLayer.widgets.filter(entry => entry.key !== modelData.key
                        && entry.widget.visible).map(entry => entry.widget)
                    title: modelData.title
                    selected: root.selectedWidget === modelData.key
                    z: selected ? 1 : 0
                    toolsAvailable: !modelData.key.startsWith("shortcut:")
                    onSelect: {
                        root.selectedWidget = modelData.key;
                        root.widgetInteracted(handle);
                    }
                    onToolsRequested: root.toolsRequested(modelData.key, handle)
                    onMovingChanged: {
                        if (moving)
                            root.activeEditHandle = handle;
                        else if (root.activeEditHandle === handle)
                            root.activeEditHandle = null;
                    }
                    freeResize: modelData.key === "visualizer"
                    onDone: (x, y, width, height) => root.placeWidget(modelData.key, widget, x, y, width, height)
                }
            }
        }
    }
}
