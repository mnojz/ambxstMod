pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.modules.globals
import qs.modules.theme
import qs.modules.widgets.dashboard.controls
import qs.config

PanelWindow {
    id: root

    required property bool editing
    required property var settings
    property url videoPoster
    property bool closing: false
    property string inspectorWidget: ""
    property bool inspectorOnRight: false
    signal dismiss()
    signal layoutEdited(var values)

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ambxst:lockscreen-preview"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    color: "transparent"

    Connections {
        target: GlobalStates
        function onLockscreenVisibleChanged() {
            if (GlobalStates.lockscreenVisible)
                root.dismiss();
        }
    }

    function closePreview() {
        if (closing)
            return;
        closing = true;
        waitForWallpaper.stop();
        startSlide.stop();
        if (slide.started)
            slide.leave();
        else
            dismiss();
    }

    function closeInspector() {
        inspectorWidget = "";
        scene.forceActiveFocus();
    }

    Timer {
        id: waitForWallpaper
        interval: 850
        onTriggered: startSlide.start()
    }

    Timer {
        id: startSlide
        interval: 32
        onTriggered: {
            waitForWallpaper.stop();
            slide.enter();
            if (root.editing)
                scene.forceActiveFocus();
            else
                scene.focusPassword();
        }
    }

    LockscreenSlide {
        id: slide
        anchors.fill: parent
        opaqueUnderlay: false
        duration: root.editing || Config.animDuration <= 0 ? 0 : Math.max(180, Math.min(600, Config.animDuration * 2))
        onExited: root.dismiss()

        LockscreenScene {
            id: scene
            anchors.fill: parent
            screen: root.screen
            preview: true
            editing: root.editing
            settings: root.settings
            videoPoster: root.videoPoster
            onLayoutEdited: values => root.layoutEdited(values)
            onDismiss: root.inspectorWidget ? root.closeInspector() : root.closePreview()
            onSelectedWidgetChanged: {
                if (root.inspectorWidget && root.inspectorWidget !== selectedWidget)
                    root.closeInspector();
            }

            onToolsRequested: (key, bounds) => {
                if (root.inspectorWidget === key) {
                    root.closeInspector();
                } else {
                    root.inspectorOnRight = bounds.x + bounds.width / 2 < scene.width / 2;
                    root.inspectorWidget = key;
                    inspector.item?.forceActiveFocus();
                }
            }

            onHasCustomBackgroundChanged: {
                if (hasCustomBackground && waitForWallpaper.running)
                    startSlide.start();
            }

            Component.onCompleted: {
                if (slide.duration > 0 && customWallpaper && !hasCustomBackground)
                    waitForWallpaper.start();
                else
                    startSlide.start();
                forceActiveFocus();
            }
        }

        Loader {
            id: inspector
            active: root.editing && root.inspectorWidget !== ""
            x: root.inspectorOnRight ? parent.width - width - 12 : 12
            y: toolbar.y + toolbar.height + 12
            width: Math.min(390, Math.max(0, parent.width - 24))
            height: Math.max(0, parent.height - y - 12)
            z: 119

            sourceComponent: FocusScope {
                Keys.onEscapePressed: root.closeInspector()

                Rectangle {
                    anchors.fill: parent
                    color: Colors.surfaceContainerLow
                    border.color: Colors.outlineVariant
                    radius: 12
                }

                // Keep clicks on the inspector from reaching widgets behind it.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 10
                        Layout.rightMargin: 4

                        Label {
                            Layout.fillWidth: true
                            text: "Widget tools"
                            font.bold: true
                            color: Colors.overSurface
                        }

                        Button {
                            flat: true
                            text: "Close"
                            focus: true
                            onClicked: root.closeInspector()
                        }
                    }

                    LockscreenPanel {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        editorWidget: root.inspectorWidget
                        editorSettings: root.settings
                        onEditorValuesChanged: values => root.layoutEdited(values)
                    }
                }
            }
        }

        Rectangle {
            id: toolbar
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 12
            width: tools.implicitWidth + 20
            height: tools.implicitHeight + 10
            radius: height / 2
            color: Colors.surfaceContainerHighest
            z: 120

            RowLayout {
                id: tools
                anchors.centerIn: parent
                spacing: 12

                Label {
                    text: root.editing ? "Drag a widget or resize it from an edge or corner" : "Lock screen preview · Esc to close"
                    color: Colors.overSurface
                }

                Button {
                    flat: true
                    text: root.editing ? "Done" : "Close"
                    onClicked: root.closePreview()
                    Keys.onEscapePressed: root.closePreview()
                }
            }
        }
    }
}
