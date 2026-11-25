pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: clock

    required property var settings
    property bool live: true
    property real renderScale: 1
    property date currentTime: live ? new Date() : new Date(2026, 10, 22, 11, 33, 28)

    readonly property real designWidth: measurement.width
    readonly property real designHeight: measurement.height
    width: face.width
    height: face.height

    LockscreenClockFace {
        id: measurement
        visible: false
        settings: clock.settings
        currentTime: clock.currentTime
    }

    LockscreenClockFace {
        id: face
        settings: clock.settings
        currentTime: clock.currentTime
        designScale: clock.renderScale
    }

    LockscreenWidgetShadow {
        active: clock.settings.clockShadow === true
        foreground: face
        renderScale: clock.renderScale
    }

    Timer {
        interval: 1000
        running: clock.live
        repeat: true
        onTriggered: clock.currentTime = new Date()
    }
}
