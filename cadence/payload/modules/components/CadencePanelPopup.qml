pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.modules.services
import qs.modules.theme

// A separate panel surface, with the same focus-grab and input mask as the
// KDE Connect and YTD popups.
PanelWindow {
    id: root

    required property Item anchorItem
    required property var bar
    required property Component popupContent
    required property string groupId
    required property string variant
    required property int popupPadding
    required property int visualMargin

    readonly property bool isOpen: visible
    readonly property bool vertical: bar.orientation === "vertical"
    readonly property string position: bar.barPosition ?? "top"
    readonly property var barWindow: anchorItem.QsWindow.window
    property point anchorPosition: Qt.point(0, 0)

    screen: bar.screen
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: false
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ambxst-cadence-popup"
    WlrLayershell.keyboardFocus: root.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    mask: Region { item: card }

    HyprlandFocusGrab {
        active: root.visible && root.barWindow !== null
        windows: root.barWindow ? [root, root.barWindow] : [root]
        onCleared: root.close()
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.visible
        onActivated: root.close()
    }

    MouseArea {
        parent: root.bar
        anchors.fill: parent
        z: 10000
        enabled: root.visible
        acceptedButtons: Qt.AllButtons
        onPressed: mouse => {
            const point = root.anchorItem.mapFromItem(root.bar, mouse.x, mouse.y);
            if (!root.anchorItem.contains(point))
                root.close();
            mouse.accepted = false;
        }
    }

    StyledRect {
        id: card
        width: (contentLoader.item?.implicitWidth ?? 0) + root.popupPadding * 2
        height: (contentLoader.item?.implicitHeight ?? 0) + root.popupPadding * 2
        x: Math.max(root.visualMargin, Math.min(
            root.vertical
                ? (root.position === "left" ? root.anchorPosition.x + root.anchorItem.width + root.visualMargin : root.anchorPosition.x - width - root.visualMargin)
                : root.anchorPosition.x + (root.anchorItem.width - width) / 2,
            root.width - width - root.visualMargin))
        y: Math.max(root.visualMargin, Math.min(
            root.vertical
                ? root.anchorPosition.y + (root.anchorItem.height - height) / 2
                : (root.position === "top" ? root.anchorPosition.y + root.anchorItem.height + root.visualMargin : root.anchorPosition.y - height - root.visualMargin),
            root.height - height - root.visualMargin))
        variant: root.variant
        radius: Styling.radius(8)

        Loader {
            id: contentLoader
            anchors.fill: parent
            anchors.margins: root.popupPadding
            sourceComponent: root.popupContent
        }
    }

    function open(): void {
        if (root.visible)
            return;
        const point = root.anchorItem.mapToItem(null, 0, 0);
        root.anchorPosition = Qt.point(
            (root.barWindow?.x ?? 0) + point.x - (root.screen?.x ?? 0),
            (root.barWindow?.y ?? 0) + point.y - (root.screen?.y ?? 0));
        Visibilities.registerBarPopup(root);
        root.visible = true;
    }

    function close(): void {
        if (!root.visible)
            return;
        Visibilities.unregisterBarPopup(root);
        root.visible = false;
    }

    Component.onDestruction: Visibilities.unregisterBarPopup(root)
}
