pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.modules.services
import qs.modules.theme

Item {
    id: clock

    required property var settings
    property real designScale: 1
    required property date currentTime

    readonly property bool colorbxstEnabled: ModsService.modsEnabled
        && ModsService.mods.some(mod => mod.id === "ecta250.colorbxst" && mod.enabled)
    readonly property color primaryColor: {
        const gradient = Config.theme.srPrimary.gradient;
        return colorbxstEnabled
            ? (gradient?.[0]?.[0] !== undefined ? Config.resolveColor(gradient[0][0]) : Colors.primary)
            : Colors.primaryFixed;
    }
    readonly property color secondaryColor: colorbxstEnabled ? Qt.darker(primaryColor, 1.12) : Colors.primaryFixedDim
    readonly property bool orbit: settings.clockStyle === "orbit"
    readonly property bool stacked: settings.clockStyle === "stacked"
    readonly property bool offsetDigits: settings.clockStyle === "offset"
    readonly property bool twelveHour: settings.clockFormat === "12h"
        || (settings.clockFormat === "shell" && Config.bar.use12hFormat)
    readonly property bool showGreeting: settings.clockGreeting ?? false
    readonly property bool showSeconds: settings.clockSeconds ?? false
    readonly property bool showAmPm: twelveHour && (settings.clockAmPm ?? true)
    readonly property int digitSize: Math.max(1, Math.round(Math.max(32, Math.min(480, settings.clockSize))
        * (settings.clockTimeRatio ?? 100) / 100 * designScale))
    readonly property int dateSize: Math.max(1, Math.round(digitSize * dateRatio(settings) / 100))

    function dateRatio(values) {
        return values.clockDateRatio > 0 ? values.clockDateRatio
            : values.clockDateSize > 0 ? values.clockDateSize * 100 / Math.max(1, values.clockSize) : 19;
    }

    readonly property int weight: {
        const weights = { light: Font.Light, regular: Font.Normal, medium: Font.Medium,
                          semibold: Font.DemiBold, bold: Font.Bold, black: Font.Black };
        return weights[settings.clockWeight] ?? (settings.clockBold ? Font.Bold : Font.Normal);
    }
    readonly property string calendarText: {
        const pieces = [];
        if (settings.clockWeekday === "show" || (settings.clockWeekday !== "hide" && settings.clockDate))
            pieces.push(Qt.formatDate(currentTime, stacked ? "dddd" : offsetDigits ? "ddd" : "dddd"));
        if (settings.clockDate)
            pieces.push(Qt.formatDate(currentTime, stacked || offsetDigits ? "MMM d" : "MMMM d"));
        return pieces.join(stacked ? "\n" : ", ").toLocaleUpperCase();
    }
    readonly property real gap: Math.max(2, dateSize * 0.65)
    readonly property real minuteGroupWidth: minutesText.width + suffixText.width
    readonly property real digitalWidth: stacked ? Math.max(hoursText.width, minuteGroupWidth)
        : hoursText.width + minuteGroupWidth
    readonly property real digitalHeight: Math.max(hoursText.height, minutesText.y + minutesText.height)
    readonly property real stackedSideWidth: stacked && calendarText ? dateText.width + gap * 2 + Math.max(1, designScale) : 0
    readonly property real timeWidth: orbit ? digitSize : digitalWidth + stackedSideWidth
    readonly property real timeHeight: orbit ? digitSize : stacked ? Math.max(digitalHeight, dateText.height) : digitalHeight
    readonly property real dateBottomHeight: !stacked && calendarText ? gap / 2 + dateText.height : 0

    width: Math.max(timeWidth, stacked ? 0 : dateText.width, showGreeting ? greeting.width : 0)
    height: timeHeight + dateBottomHeight + (showGreeting ? gap / 2 + greeting.height : 0)

    component ClockText: Text {
        property int textSize: clock.digitSize
        font.family: clock.settings.clockFont || Config.theme.font
        font.pixelSize: textSize
        font.weight: clock.weight
        font.letterSpacing: textSize * (clock.settings.clockLetterSpacing ?? 0) / 100
        color: clock.primaryColor
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
    }

    ClockText {
        id: hoursText
        visible: !clock.orbit
        x: (clock.width - clock.timeWidth) / 2 + (clock.stacked ? (clock.digitalWidth - width) / 2 : 0)
        text: {
            if (!clock.twelveHour)
                return Qt.formatTime(clock.currentTime, "hh");
            const hours = (clock.currentTime.getHours() % 12 || 12).toString();
            return clock.stacked || clock.offsetDigits ? hours.padStart(2, "0") : hours;
        }
    }

    ClockText {
        id: minutesText
        visible: !clock.orbit
        x: clock.stacked ? (clock.width - clock.timeWidth + clock.digitalWidth - clock.minuteGroupWidth) / 2
                         : hoursText.x + hoursText.width
        y: clock.stacked ? hoursText.height * 0.82 : clock.offsetDigits ? hoursText.height * 0.5 : 0
        text: (clock.offsetDigits || clock.stacked ? "" : ":") + Qt.formatTime(clock.currentTime, "mm")
        color: clock.secondaryColor
    }

    ClockText {
        id: suffixText
        visible: !clock.orbit && text !== ""
        x: minutesText.x + minutesText.width
        y: minutesText.y + (clock.offsetDigits ? -hoursText.height * 0.15 : hoursText.height - height)
        text: (clock.showSeconds ? ":" + Qt.formatTime(clock.currentTime, "ss") : "")
            + (clock.showAmPm ? " " + Qt.formatTime(clock.currentTime, "AP") : "")
        textSize: Math.max(1, Math.round(clock.digitSize * 0.42))
    }

    Item {
        id: dial
        visible: clock.orbit
        anchors.horizontalCenter: parent.horizontalCenter
        width: clock.digitSize
        height: width

        Repeater {
            model: clock.orbit ? 12 : 0
            delegate: Rectangle {
                required property int index
                readonly property real angle: index * Math.PI / 6
                width: Math.max(1, dial.width * (index % 3 === 0 ? 0.055 : 0.035))
                height: width
                x: dial.width * (0.5 + 0.43 * Math.sin(angle)) - width / 2
                y: dial.height * (0.5 - 0.43 * Math.cos(angle)) - height / 2
                radius: width / 2
                antialiasing: true
                color: index % 3 === 0 ? clock.primaryColor : clock.secondaryColor
            }
        }

        component Hand: Rectangle {
            x: (dial.width - width) / 2
            y: dial.height / 2 - height
            transformOrigin: Item.Bottom
            radius: width / 2
            antialiasing: true
        }

        Hand {
            width: Math.max(1, dial.width * 0.052)
            height: dial.width * 0.23
            rotation: clock.currentTime.getHours() * 30 + clock.currentTime.getMinutes() / 2
            color: clock.primaryColor
        }

        Hand {
            width: Math.max(1, dial.width * 0.035)
            height: dial.width * 0.36
            rotation: clock.currentTime.getMinutes() * 6 + clock.currentTime.getSeconds() / 10
            color: clock.secondaryColor
        }

        Hand {
            visible: clock.showSeconds
            width: Math.max(1, dial.width * 0.017)
            height: dial.width * 0.39
            rotation: clock.currentTime.getSeconds() * 6
            color: clock.primaryColor
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.max(2, dial.width * 0.075)
            height: width
            radius: width / 2
            antialiasing: true
            color: clock.primaryColor
        }
    }

    Rectangle {
        visible: clock.stacked && clock.calendarText !== ""
        x: (clock.width - clock.timeWidth) / 2 + clock.digitalWidth + clock.gap
        width: Math.max(1, clock.designScale)
        height: clock.timeHeight * 0.75
        y: (clock.timeHeight - height) / 2
        color: clock.secondaryColor
        opacity: 0.65
    }

    ClockText {
        id: dateText
        visible: clock.calendarText !== ""
        x: clock.stacked ? (clock.width - clock.timeWidth) / 2 + clock.digitalWidth + clock.gap * 2 + Math.max(1, clock.designScale)
                         : (clock.width - width) / 2
        y: clock.stacked ? (clock.timeHeight - height) / 2 : clock.timeHeight + clock.gap / 2
        text: !clock.calendarText ? "" : clock.settings.clockStyle === "inline" ? "—  " + clock.calendarText + "  —" : clock.calendarText
        color: clock.secondaryColor
        font.weight: Font.Medium
        textSize: clock.dateSize
    }

    ClockText {
        id: greeting
        visible: clock.showGreeting
        x: (clock.width - width) / 2
        y: clock.timeHeight + clock.dateBottomHeight + clock.gap / 2
        text: clock.currentTime.getHours() < 12 ? "Good morning"
            : clock.currentTime.getHours() < 18 ? "Good afternoon" : "Good evening"
        textSize: clock.dateSize
    }
}
