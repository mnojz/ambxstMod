pragma ComponentBehavior: Bound

import QtQuick
import "../LockscreenCustomization.js" as Customization

Item {
    id: clock

    required property var settings
    readonly property var savedFrame: Customization.read(settings.clockFrame)
    readonly property real requestedScale: {
        if (Number.isFinite(savedFrame.scale))
            return Math.max(0.01, savedFrame.scale);
        const reference = legacyFrameReference.item;
        if (!reference)
            return 1;
        return Math.min((savedFrame.width ?? reference.width) / Math.max(1, reference.width),
                        (savedFrame.height ?? reference.height) / Math.max(1, reference.height));
    }
    readonly property var appearance: Customization.read(settings.clockAppearance)
    opacity: (appearance.opacity ?? 100) / 100
    property bool live: true
    property real renderScale: 1
    property date currentTime: live ? new Date() : new Date(2026, 10, 22, 11, 33, 28)

    readonly property var editableParts: face.editableParts
    readonly property real naturalWidth: measurement.width
    readonly property real naturalHeight: measurement.height
    width: face.width
    height: face.height

    function presetPosition(item, axis) {
        return face.presetPosition(item, axis);
    }

    WidgetAppearance {
        widget: clock
        style: clock.appearance
        renderScale: clock.renderScale
    }

    LockscreenClockFace {
        id: measurement
        visible: false
        settings: clock.settings
        currentTime: clock.currentTime
    }

    // Older presets store box dimensions. Convert them using a fixed face so
    // content changes can grow or shrink the clock without changing its scale.
    Loader {
        id: legacyFrameReference
        active: !Number.isFinite(clock.savedFrame.scale)
            && (Number.isFinite(clock.savedFrame.width) || Number.isFinite(clock.savedFrame.height))
        visible: false
        sourceComponent: LockscreenClockFace {
            settings: Object.assign({}, clock.settings, {
                clockPartStyles: "{}", clockFormat: "24h", clockDate: clock.settings.clockStyle !== "orbit",
                clockWeekday: "hide", clockSeconds: false, clockGreeting: false
            })
            currentTime: new Date(2026, 10, 22, 11, 33)
        }
    }

    Item {
        id: renderedFace
        anchors.fill: parent

        LockscreenClockFace {
            id: face
            settings: clock.settings
            currentTime: clock.currentTime
            designScale: clock.renderScale
        }
    }

    LockscreenWidgetShadow {
        active: clock.settings.clockShadow === true
        foreground: renderedFace
        renderScale: clock.renderScale
    }

    Timer {
        interval: 1000
        running: clock.live
        repeat: true
        onTriggered: clock.currentTime = new Date()
    }
}
