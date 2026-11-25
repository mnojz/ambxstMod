pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.modules.theme

Button {
    id: root

    required property var shortcutAction
    required property bool usable
    property real renderScale: 1
    property bool armed: false
    property bool failed: false
    readonly property real designWidth: 44
    readonly property real designHeight: designWidth

    width: designWidth * renderScale
    height: designHeight * renderScale
    flat: true
    hoverEnabled: usable
    enabled: usable && !runner.running
    Accessible.name: shortcutAction.label

    ToolTip.visible: usable && (hovered || armed || failed)
    ToolTip.text: failed ? shortcutAction.label + " failed"
        : armed ? "Click again to confirm " + shortcutAction.label.toLowerCase()
        : shortcutAction.label

    onUsableChanged: {
        armed = false;
        reset.stop();
    }

    onClicked: {
        if (!usable)
            return;
        if (!armed) {
            failed = false;
            armed = true;
            reset.restart();
            return;
        }
        armed = false;
        reset.stop();
        runner.running = true;
    }

    Timer {
        id: reset
        interval: 3000
        onTriggered: {
            root.armed = false;
            root.failed = false;
        }
    }

    Process {
        id: runner
        command: root.shortcutAction.command
        onExited: code => {
            if (code !== 0) {
                root.failed = true;
                reset.restart();
            }
        }
    }

    background: Rectangle {
        radius: width / 2
        antialiasing: true
        color: root.armed ? Colors.primaryContainer
            : root.hovered ? Colors.surfaceContainerHighest : Colors.surfaceContainerHigh
        border.color: root.armed || root.visualFocus ? Colors.primary : Colors.outlineVariant
        border.width: Math.max(1, root.renderScale)
    }

    contentItem: Item {
        Text {
            anchors.centerIn: parent
            text: Icons[root.shortcutAction.icon] || Icons.shutdown
            font.family: Icons.font
            font.pixelSize: Math.max(1, Math.round(20 * root.renderScale))
            renderType: Text.CurveRendering
            color: root.armed ? Colors.overPrimaryContainer : Colors.overSurface
        }
    }
}
