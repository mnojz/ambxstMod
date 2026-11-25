pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.corners
import qs.modules.theme
import qs.config
import "LockscreenPlacement.js" as Placement
import "LockscreenActions.js" as Actions
import "LockscreenCustomization.js" as Customization
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
    property url preparedVideo
    property var videoCache
    property bool suspending: false
    property Item activeEditHandle
    property var shortcutWidgets: ({})
    property bool editing: false
    property string selectedPart: ""
    property string partGuideAxis: ""
    property string selectedWidget: ""
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
    signal partSelected(string widget, string part, Item handle)
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
        selectedWidget = enabled ? key : "";
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

    function widgetItem(key) {
        switch (key) {
        case "clock": return clockContainer;
        case "media": return playerContainer;
        case "login": return passwordContainer;
        case "visualizer": return visualizer;
        default: return shortcutWidgets[key.slice(9)];
        }
    }

    function relativePartBounds(widget, item) {
        if (!item || !item.visible || item.width <= 0 || item.height <= 0)
            return null;
        let x = 0;
        let y = 0;
        for (let current = item; current && current !== widget; current = current.parent) {
            x += current.x + (current.partOffsetX ?? 0);
            y += current.y + (current.partOffsetY ?? 0);
        }
        return Qt.rect(x, y, item.width, item.height);
    }

    function visualBounds(key, widget) {
        if (activeEditHandle?.widget === widget)
            return activeEditHandle.draft;

        const bounds = key === "clock" ? Qt.rect(widget.baseX, widget.baseY, widget.width, widget.height)
            : Qt.rect(widget.baseX, widget.baseY, widget.baseWidth * widget.baseScale, widget.baseHeight * widget.baseScale);
        if (!Customization.parts[key])
            return bounds;
        const anchor = Customization.read(settings[key + "Anchor"]);
        if (!anchor.target || !Customization.canAnchor(settings, key, anchor.target))
            return bounds;

        const screenRect = Qt.rect(0, 0, width, height);
        let target = screenRect;
        if (anchor.target !== "screen") {
            const targetKey = Customization.targetWidget(anchor.target);
            const targetItem = widgetItem(targetKey);
            if (!targetItem?.visible)
                return bounds;
            target = visualBounds(targetKey, targetItem);
            if (anchor.target === "avatar") {
                const avatar = relativePartBounds(targetItem, targetItem.editableParts?.avatar);
                if (!avatar)
                    return bounds;
                target = Qt.rect(target.x + avatar.x, target.y + avatar.y, avatar.width, avatar.height);
            }
        }
        return Customization.place(anchor, target, bounds, screenRect, designScale);
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

    function placeWidget(key, widget, x, y, requestedWidth, requestedHeight, resizing) {
        const anchorChange = !resizing && Customization.read(settings[key + "Anchor"]).target
            ? { [key + "Anchor"]: "{}" } : {};
        if (key === "visualizer") {
            layoutEdited(Object.assign(anchorChange, {
                visualizerWidth: Math.min(1, requestedWidth / Math.max(1, width)),
                visualizerHeight: Math.min(1, requestedHeight / Math.max(1, height)),
                visualizerX: x / Math.max(1, width - requestedWidth),
                visualizerY: y / Math.max(1, height - requestedHeight)
            }));
            return;
        }
        if (key.startsWith("shortcut:")) {
            placeShortcut(key.slice(9), widget, x, y, requestedWidth);
            return;
        }
        const frameSize = key === "clock"
            ? { scale: requestedWidth / (Math.max(1, widget.naturalWidth) * designScale) }
            : { width: requestedWidth / designScale, height: requestedHeight / designScale };
        const frame = resizing ? { [key + "Frame"]: JSON.stringify(frameSize) } : {};
        layoutEdited(Object.assign(anchorChange, frame, {
            [key + "X"]: Math.max(0, Math.min(1, x / Math.max(1, width - requestedWidth))),
            [key + "Y"]: Math.max(0, Math.min(1, y / Math.max(1, height - requestedHeight)))
        }));
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
        miniature: root.miniature
        designScale: root.designScale
        videoPoster: root.videoPoster
        preparedVideo: root.preparedVideo
        videoCache: root.videoCache
        playbackEnabled: !root.suspending
    }

    Widgets.LockscreenVisualizer {
        id: visualizer
        settings: root.settings
        visible: root.settings.visualizerVisible
        captureAudio: !root.miniature && !root.suspending
        sample: root.miniature
        pixelScale: Math.max(0.01, root.designScale)
        readonly property real baseWidth: Math.max(0, Math.min(root.width, root.width * root.settings.visualizerWidth))
        readonly property real baseHeight: Math.max(0, Math.min(root.height, root.height * root.settings.visualizerHeight))
        readonly property real baseScale: 1
        readonly property real baseX: root.coordinate(root.settings.visualizerX, "center", root.width, baseWidth)
        readonly property real baseY: root.coordinate(root.settings.visualizerY, "bottom", root.height, baseHeight)
        readonly property rect bounds: root.visualBounds("visualizer", visualizer)
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
        readonly property real baseWidth: naturalWidth
        readonly property real baseHeight: naturalHeight
        readonly property var position: root.placement(root.settings.clockPosition, "center-center")
        readonly property real baseScale: Placement.fit(baseWidth, baseHeight, parent.width, parent.height,
            root.designScale * requestedScale, Object.keys(savedFrame).length ? 0 : 32 * root.designScale)
        transformOrigin: Item.TopLeft
        readonly property real baseX: root.coordinate(root.settings.clockX, position[1], parent.width, width)
        readonly property real baseY: root.coordinate(root.settings.clockY, position[0], parent.height, height)
        readonly property rect bounds: root.visualBounds("clock", clockContainer)
        x: bounds.x
        y: bounds.y
        renderScale: root.activeEditHandle?.widget === clockContainer && root.activeEditHandle.resizing
            ? root.activeEditHandle.draft.width / Math.max(1, naturalWidth) : baseScale

    }

    Item {
        id: playerContainer
        z: root.activeEditHandle?.widget === playerContainer ? 12 : 10
        readonly property var position: root.placement(root.settings.mediaPosition, root.settings.position + "-left")
        readonly property var editableParts: playerContent.editableParts
        readonly property real renderScale: playerContent.renderScale
        readonly property bool artworkAbove: playerContent.artworkAbove
        readonly property real baseWidth: playerContent.designWidth
        readonly property real baseHeight: hasSavedFrame
            ? resizeHeight(baseWidth * root.designScale, playerContent.designHeight * root.designScale) / root.designScale
            : playerContent.designHeight

        function resizeHeight(frameWidth, frameHeight) {
            return Math.min(root.height, playerContent.heightForFrame(frameWidth, frameHeight, preferredScale));
        }
        width: playerContent.width
        height: playerContent.height
        readonly property real preferredScale: root.designScale * Math.max(65, Math.min(160, root.settings.mediaScale)) / 100
        readonly property bool hasSavedFrame: Object.keys(playerContent.savedFrame).length > 0
        readonly property real baseScale: Placement.fit(baseWidth, baseHeight, parent.width, parent.height,
            hasSavedFrame ? root.designScale : preferredScale, hasSavedFrame ? 0 : 32 * root.designScale)
        transformOrigin: Item.TopLeft
        readonly property real baseX: root.coordinate(root.settings.mediaX, position[1], parent.width, baseWidth * baseScale)
        readonly property real baseY: root.coordinate(root.settings.mediaY, position[0], parent.height, baseHeight * baseScale)
        readonly property rect bounds: root.visualBounds("media", playerContainer)
        x: bounds.x
        y: bounds.y
        visible: root.settings.mediaVisible

        Widgets.LockscreenMedia {
            id: playerContent
            settings: root.settings
            frameSize: playerContainer.hasSavedFrame || root.activeEditHandle?.widget === playerContainer && root.activeEditHandle.resizing
                ? Qt.size(playerContainer.bounds.width, playerContainer.bounds.height) : Qt.size(0, 0)
            renderScale: customFrame ? Math.max(0.01, Math.min(playerContainer.preferredScale,
                frameSize.width / 234, frameSize.height / (minimumContentHeight
                    + (preferredArtworkAbove && hasFrontArtwork ? 85 : 32))))
                : playerContainer.baseScale
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
        frameSize: hasSavedFrame || root.activeEditHandle?.widget === passwordContainer && root.activeEditHandle.resizing
            ? Qt.size(bounds.width, bounds.height) : Qt.size(0, 0)
        renderScale: customFrame ? Math.max(0.01, Math.min(preferredScale,
            frameSize.width / 190, frameSize.height / (presetPortraitAbove ? 124 : titleCard ? 112 : 78))) : baseScale
        readonly property real baseWidth: designWidth
        readonly property real baseHeight: designHeight
        interactive: !root.editing && !root.miniature
        readonly property var position: root.placement(root.settings.loginPosition, root.settings.position + "-center")
        readonly property real preferredScale: root.designScale * Math.max(75, Math.min(160, root.settings.loginScale)) / 100
        readonly property bool hasSavedFrame: Object.keys(savedFrame).length > 0
        readonly property real baseScale: Placement.fit(baseWidth, baseHeight, parent.width, parent.height,
            hasSavedFrame ? root.designScale : preferredScale, hasSavedFrame ? 0 : 32 * root.designScale)
        transformOrigin: Item.TopLeft
        readonly property real baseX: root.coordinate(root.settings.loginX, position[1], parent.width, baseWidth * baseScale)
        readonly property real baseY: root.coordinate(root.settings.loginY, position[0], parent.height, baseHeight * baseScale)
        readonly property rect bounds: root.visualBounds("login", passwordContainer)
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
            readonly property rect bounds: root.visualBounds("shortcut:" + modelData.id, shortcutButton)
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
                const widget = root.widgetItem(option.key);
                return { key: option.key, title: option.title, widget };
            }).filter(entry => entry.widget)

            MouseArea {
                anchors.fill: parent
                onClicked: root.selectedWidget = ""
            }

            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: point => {
                    const position = point.position;
                    const hits = editorLayer.widgets.filter(entry => {
                        if (!entry.widget.visible)
                            return false;
                        const bounds = root.visualBounds(entry.key, entry.widget);
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
                    targetBounds: root.visualBounds(modelData.key, widget)
                    selected: root.selectedWidget === modelData.key
                    partBounds: selected && root.selectedPart && !moving
                        ? root.relativePartBounds(widget, widget.editableParts?.[root.selectedPart]) : null
                    partGuideAxis: selected && modelData.key === "clock" ? root.partGuideAxis : ""
                    partGuideValue: partGuideAxis ? widget.editableParts?.[root.selectedPart]?.[partGuideAxis + "Position"] ?? 0 : 0
                    adjustHeight: modelData.key === "media" ? (w, h) => widget.resizeHeight(w, h) : null
                    z: selected ? 1 : 0
                    toolsAvailable: !modelData.key.startsWith("shortcut:")
                    onSelect: {
                        root.selectedWidget = modelData.key;
                        root.widgetInteracted(handle);
                    }
                    onPartTapped: position => {
                        for (const [key, item] of Object.entries(widget.editableParts ?? {})) {
                            const rect = root.relativePartBounds(widget, item);
                            if (rect && position.x >= rect.x && position.x <= rect.x + rect.width
                                    && position.y >= rect.y && position.y <= rect.y + rect.height) {
                                root.partSelected(modelData.key, key, handle);
                                break;
                            }
                        }
                    }
                    onToolsRequested: {
                        root.selectedWidget = modelData.key;
                        root.toolsRequested(modelData.key, handle);
                    }
                    onMovingChanged: {
                        if (moving)
                            root.activeEditHandle = handle;
                        else if (root.activeEditHandle === handle)
                            root.activeEditHandle = null;
                    }
                    freeResize: modelData.key !== "clock" && !modelData.key.startsWith("shortcut:")
                    minimumWidth: root.designScale * ({ media: 210, login: 168, clock: 28 }[modelData.key] ?? 36)
                    minimumHeight: root.designScale * ({ media: 76, login: 58, clock: 34 }[modelData.key] ?? 36)
                    onDone: (x, y, width, height, resizing) => root.placeWidget(modelData.key, widget, x, y, width, height, resizing)
                }
            }
        }
    }
}
