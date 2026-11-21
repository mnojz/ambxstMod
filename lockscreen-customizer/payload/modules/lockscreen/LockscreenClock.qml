pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.modules.components
import qs.modules.theme

Item {
    id: clock

    required property var settings
    property bool live: true
    property bool shadows: true
    property real designScale: 1

    readonly property bool offsetDigits: clock.settings.clockStyle === "offset"
    readonly property bool twelveHour: clock.settings.clockFormat === "12h"
        || (clock.settings.clockFormat === "shell" && Config.bar.use12hFormat)
    readonly property int digitSize: Math.max(1, Math.round(Math.max(32, Math.min(480, clock.settings.clockSize)) * designScale))
    property date currentTime: live ? new Date() : new Date(2000, 0, 1, 11, 33)

    readonly property bool stacked: clock.settings.clockStyle === "stacked"
    readonly property real minuteGroupWidth: minutesText.width + (amPmText.visible ? amPmText.width : 0)
    readonly property real digitsWidth: stacked
        ? Math.max(hoursText.width, minuteGroupWidth)
        : hoursText.width + minuteGroupWidth
    width: Math.max(digitsWidth, dateText.visible ? dateText.width : 0)
    height: minutesText.y + minutesText.height + (dateText.visible ? dateText.height : 0)

    component ClockText: Text {
        font.family: clock.settings.clockFont || Config.theme.font
        font.pixelSize: clock.digitSize
        font.bold: clock.settings.clockBold
        color: Colors.primaryFixed
        textFormat: Text.PlainText
        renderType: Text.CurveRendering
        antialiasing: true
        layer.enabled: clock.shadows
        layer.smooth: true
        layer.effect: BgShadow {}
    }

    ClockText {
        id: hoursText
        x: clock.offsetDigits ? 0 : (clock.width - (clock.stacked ? width : clock.digitsWidth)) / 2
        text: clock.twelveHour ? (clock.currentTime.getHours() % 12 || 12).toString()
                                        : Qt.formatTime(clock.currentTime, "hh")
    }

    ClockText {
        id: minutesText
        x: clock.stacked ? (clock.width - clock.minuteGroupWidth) / 2 : hoursText.x + hoursText.width
        y: clock.stacked ? hoursText.height * 0.82 : clock.offsetDigits ? hoursText.height * 0.5 : 0
        text: (clock.offsetDigits || clock.stacked ? "" : ":") + Qt.formatTime(clock.currentTime, "mm")
        color: Colors.primaryFixedDim
    }

    ClockText {
        id: amPmText
        x: minutesText.x + minutesText.width
        y: minutesText.y + (clock.offsetDigits ? -hoursText.height * 0.15 : hoursText.height - height)
        text: clock.twelveHour ? " " + Qt.formatTime(clock.currentTime, "AP") : ""
        visible: clock.twelveHour
        font.pixelSize: Math.max(1, Math.round(clock.digitSize * 0.42))
    }

    ClockText {
        id: dateText
        x: clock.offsetDigits ? 0 : (clock.width - width) / 2
        y: minutesText.y + minutesText.height
        text: Qt.formatDate(clock.currentTime, "dddd, MMMM d")
        visible: clock.settings.clockDate
        font.pixelSize: Math.max(1, Math.round(clock.digitSize * 0.19))
    }

    Timer {
        interval: 1000
        running: clock.live
        repeat: true
        onTriggered: clock.currentTime = new Date()
    }
}
