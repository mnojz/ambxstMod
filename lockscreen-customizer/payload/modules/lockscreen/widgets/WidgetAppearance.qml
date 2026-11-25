pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.modules.theme
import "../LockscreenCustomization.js" as Customization

Item {
    id: root

    required property Item widget
    required property var style
    required property real renderScale

    readonly property real cornerRadius: Math.min(widget.width / 2, widget.height / 2,
        (style.radius ?? Config.roundness) * renderScale)

    Rectangle {
        parent: root.widget
        anchors.fill: parent
        z: -0.5
        visible: root.style.fill === "solid"
        radius: root.cornerRadius
        antialiasing: true
        color: Qt.alpha(Customization.color({ color: root.style.fillColor }, Colors.surfaceContainer, Colors),
                        (root.style.fillOpacity ?? 85) / 100)
    }

    Rectangle {
        parent: root.widget
        anchors.fill: parent
        z: 20
        visible: Boolean(root.style.border)
        radius: root.cornerRadius
        antialiasing: true
        color: "transparent"
        border.width: Math.max(1, (root.style.borderWidth ?? 1) * root.renderScale)
        border.color: Customization.color({ color: root.style.borderColor }, Colors.outline, Colors)
    }
}
