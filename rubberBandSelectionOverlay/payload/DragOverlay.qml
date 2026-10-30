import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.services

PanelWindow {
    id: root

    required property var targetScreen
    screen: targetScreen

    property bool dragging: false
    property point startPosition: Qt.point(0, 0)
    property rect selectionRect: Qt.rect(0, 0, 0, 0)

    readonly property string modId: "mnojz.dragoverlay"

    // Visual settings, editable on the mod's Settings page.
    // Defaults mirror the fallback values declared in settings.json.
    property string overlayBgColor: "#445b93d3"
    property string overlayBorderColor: "#adaac7fc"
    property int overlayBorderWidth: 2
    property int overlayRadius: 8

    function applyValues(values) {
        if (values === undefined || values === null)
            return
        if (values.overlayBgColor !== undefined)
            root.overlayBgColor = values.overlayBgColor
        if (values.overlayBorderColor !== undefined)
            root.overlayBorderColor = values.overlayBorderColor
        if (values.overlayBorderWidth !== undefined) {
            const width = parseInt(values.overlayBorderWidth, 10)
            if (Number.isFinite(width))
                root.overlayBorderWidth = width
        }
        if (values.overlayRadius !== undefined) {
            const radius = parseInt(values.overlayRadius, 10)
            if (Number.isFinite(radius))
                root.overlayRadius = radius
        }
    }

    function loadSettings() {
        if (typeof ModsService === "undefined" || typeof ModsService.getSettings !== "function")
            return
        ModsService.getSettings(root.modId, (settings, error) => {
            if (error || !settings)
                return
            root.applyValues(settings.values)
        })
    }

    Component.onCompleted: root.loadSettings()

    Connections {
        target: ModsService

        function onSettingChanged(modId, key, value) {
            if (modId !== root.modId)
                return
            const values = {}
            values[key] = value
            root.applyValues(values)
        }
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    visible: dragging

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        x: root.selectionRect.x
        y: root.selectionRect.y - 40
        width: root.selectionRect.width
        height: root.selectionRect.height

        color: root.overlayBgColor
        border.width: root.overlayBorderWidth
        border.color: root.overlayBorderColor
        radius: root.overlayRadius
    }

    IpcHandler {
        target: "dragOverlay"

        function start(x: real, y: real): void {
            root.startPosition = Qt.point(x, y)
            root.selectionRect = Qt.rect(x, y, 0, 0)
            root.dragging = true
        }

        function update(x: real, y: real): void {
            if (!root.dragging)
                return

            const left = Math.min(root.startPosition.x, x)
            const top = Math.min(root.startPosition.y, y)
            root.selectionRect = Qt.rect(
                left,
                top,
                Math.abs(x - root.startPosition.x),
                Math.abs(y - root.startPosition.y)
            )
        }

        function stop(): void {
            root.dragging = false
        }
    }
}