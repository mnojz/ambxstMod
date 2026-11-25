pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.theme
import "LockscreenPlacement.js" as Placement

Rectangle {
    id: root

    required property int duration
    property string desktopPath: ""
    property bool opaqueUnderlay: true
    property bool started: false
    default property alias content: sheet.data
    signal exited()

    clip: true
    color: opaqueUnderlay ? Colors.surfaceContainer : "transparent"

    function enter(immediate = false) {
        if (exit.running || (started && !immediate))
            return;
        if (immediate) {
            entry.stop();
            sheet.offset = 0;
        }
        started = true;
        if (!immediate && duration > 0)
            entry.start();
    }

    function leave() {
        entry.stop();
        if (duration > 0 && sheet.offset > -height)
            exit.start();
        else
            exited();
    }

    property Item underlay: Image {
        parent: root
        anchors.fill: parent
        source: root.opaqueUnderlay ? Placement.fileUrl(root.desktopPath) : ""
        sourceSize: Qt.size(Math.max(1, Math.round(width * (Screen.devicePixelRatio || 1))),
                            Math.max(1, Math.round(height * (Screen.devicePixelRatio || 1))))
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        mipmap: true
        visible: status === Image.Ready
    }

    property Item slidingSheet: Item {
        parent: root
        z: 1
        id: sheet
        width: parent.width
        height: parent.height
        property real offset: 0
        y: root.started || root.duration === 0 ? offset : -height
    }

    property Animation entryAnimation: NumberAnimation {
        id: entry
        target: sheet
        property: "offset"
        from: -root.height
        to: 0
        duration: root.duration
        easing.type: Easing.OutCubic
    }

    property Animation exitAnimation: NumberAnimation {
        id: exit
        target: sheet
        property: "offset"
        to: -root.height
        duration: root.duration
        easing.type: Easing.InCubic
        onFinished: root.exited()
    }
}
