pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.modules.theme

Text {
    id: root

    required property real renderScale
    property bool actionable: true
    property bool enableHold: false
    property int acceptedButtons: Qt.LeftButton
    property color idleColor: Colors.overBackground
    signal activated(int button)
    signal held()

    textFormat: Text.PlainText
    renderType: Text.NativeRendering
    font.family: Icons.font
    font.pixelSize: Math.max(1, Math.round(20 * renderScale))
    color: hover.hovered ? Styling.srItem("overprimary") : idleColor
    opacity: actionable ? 1 : 0.3

    Behavior on color {
        enabled: Config.animDuration > 0
        ColorAnimation {
            duration: Config.animDuration
            easing.type: Easing.OutQuart
        }
    }

    HoverHandler {
        id: hover
        enabled: root.actionable
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.actionable
        acceptedButtons: root.acceptedButtons
        cursorShape: Qt.PointingHandCursor
        pressAndHoldInterval: 1000

        onClicked: mouse => root.activated(mouse.button)
        onPressAndHold: mouse => {
            if (root.enableHold && mouse.button === Qt.LeftButton)
                root.held();
            else
                mouse.accepted = false;
        }
    }
}
