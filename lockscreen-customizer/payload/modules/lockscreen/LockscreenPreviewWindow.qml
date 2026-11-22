pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.modules.globals
import qs.modules.theme
import qs.modules.widgets.dashboard.controls
import qs.config
import "../../config/defaults/lockscreen.js" as Defaults
import "LockscreenPresets.js" as Presets

PanelWindow {
    id: root

    required property bool editing
    required property var settings
    property url videoPoster
    property bool closing: false
    property string inspectorWidget: ""
    property bool inspectorOnRight: false
    property Item inspectorHandle
    property var presetBaselines: ({})

    Component.onCompleted: {
        if (!editing)
            return;
        const baselines = {};
        const stored = Array.from(settings.widgetPresetBaselines ?? []);
        for (const widget of ["clock", "media", "login"]) {
            const values = stored.find(entry => entry?.widget === widget)?.values ?? settings;
            baselines[widget] = Presets.valuesFor(widget, values, Defaults.data);
        }
        presetBaselines = baselines;
    }

    readonly property rect inspectedBounds: inspectorHandle
        ? Qt.rect(inspectorHandle.x, inspectorHandle.y, inspectorHandle.width, inspectorHandle.height)
        : Qt.rect(0, 0, 0, 0)

    onInspectedBoundsChanged: {
        if (inspectorHandle && overlapsInspector(inspectedBounds, inspectorOnRight)
                && !overlapsInspector(inspectedBounds, !inspectorOnRight))
            inspectorOnRight = !inspectorOnRight;
    }

    function overlapsInspector(bounds, right) {
        const x = right ? slide.width - inspector.width - 12 : 12;
        return bounds.x < x + inspector.width && bounds.x + bounds.width > x
            && bounds.y < inspector.y + inspector.height && bounds.y + bounds.height > inspector.y;
    }
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

    function editLayout(values) {
        const stored = Array.from(settings.widgetPresetBaselines ?? []);
        const keys = Object.keys(values);
        let changed = false;
        for (const widget of Object.keys(presetBaselines)) {
            const baseline = presetBaselines[widget];
            if (!keys.some(key => key in baseline))
                continue;
            const index = stored.findIndex(entry => entry?.widget === widget);
            if (JSON.stringify(stored[index]?.values) === JSON.stringify(baseline))
                continue;
            const entry = { widget, values: baseline };
            if (index < 0)
                stored.push(entry);
            else
                stored[index] = entry;
            changed = true;
        }
        layoutEdited(changed ? Object.assign({}, values, { widgetPresetBaselines: stored }) : values);
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
        inspectorHandle = null;
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
            onLayoutEdited: values => root.editLayout(values)
            onDismiss: root.inspectorWidget ? root.closeInspector() : root.closePreview()
            onSelectedWidgetChanged: {
                if (root.inspectorWidget && root.inspectorWidget !== selectedWidget)
                    root.closeInspector();
            }

            onToolsRequested: (key, handle) => {
                if (root.inspectorWidget === key) {
                    root.closeInspector();
                } else {
                    root.inspectorOnRight = handle.x + handle.width / 2 < scene.width / 2;
                    root.inspectorWidget = key;
                    root.inspectorHandle = handle;
                    inspector.item?.forceActiveFocus();
                }
            }

            onContextMenuRequested: (position, key) => {
                if (!key) {
                    addWidgetMenu.popup(position);
                } else if (key !== "login") {
                    removeWidgetMenu.widgetKey = key;
                    removeWidgetMenu.popup(position);
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

        component EditorMenu: Basic.Menu {
            id: menu
            readonly property bool pointerInside: menuHover.hovered

            function containsPointer(item) {
                if (!pointerInside)
                    return false;
                const position = item.mapFromItem(menu.contentItem, menuHover.point.position);
                return item.contains(position);
            }

            popupType: Popup.Item
            padding: 5
            margins: 6
            implicitWidth: 178

            background: Rectangle {
                radius: 9
                color: Colors.surfaceContainerHigh
                border.color: Colors.outlineVariant
            }

            contentItem: ListView {
                implicitHeight: contentHeight
                model: menu.contentModel
                currentIndex: menu.currentIndex
                interactive: contentHeight > height
                clip: true

                HoverHandler { id: menuHover }
            }
        }

        component EditorMenuItem: Basic.MenuItem {
            id: option
            property bool destructive: false
            property bool heading: false
            readonly property bool pointerOver: !heading && (menu?.containsPointer(option) ?? false)
            hoverEnabled: true
            padding: 8
            implicitHeight: 34

            background: Rectangle {
                radius: 5
                color: option.pointerOver
                    ? Qt.tint(Colors.surfaceContainerHigh, Qt.alpha(Colors.overSurface, option.enabled ? 0.13 : 0.08))
                    : "transparent"
                border.width: option.visualFocus && !option.menu?.pointerInside ? 1 : 0
                border.color: Colors.outline
            }

            contentItem: Text {
                text: option.text
                font: option.font
                verticalAlignment: Text.AlignVCenter
                color: option.destructive ? Colors.red
                    : option.enabled || option.heading ? Colors.overSurface : Colors.overSurfaceVariant
                opacity: option.enabled || option.heading ? 1 : 0.65
            }

            HoverHandler {
                enabled: option.enabled
                cursorShape: Qt.PointingHandCursor
            }
        }

        EditorMenu {
            id: addWidgetMenu
            title: "Add widget"

            EditorMenuItem {
                text: addWidgetMenu.title
                heading: true
                enabled: false
            }

            Instantiator {
                model: root.editing ? scene.widgetOptions : []

                delegate: EditorMenuItem {
                    required property var modelData
                    text: modelData.title
                    enabled: !scene.hasWidget(modelData.key)
                    onTriggered: scene.setWidgetEnabled(modelData.key, true)
                }

                onObjectAdded: (index, item) => addWidgetMenu.insertItem(index + 1, item)
                onObjectRemoved: (index, item) => addWidgetMenu.removeItem(item)
            }
        }

        EditorMenu {
            id: removeWidgetMenu
            property string widgetKey: ""

            EditorMenuItem {
                text: "Remove widget"
                destructive: true
                onTriggered: scene.setWidgetEnabled(removeWidgetMenu.widgetKey, false)
            }
        }

        component EditorButton: Basic.Button {
            id: action
            property string helpText: ""
            ToolTip.text: helpText
            ToolTip.delay: 500
            ToolTip.visible: hovered && helpText !== ""
            property bool destructive: false
            property bool circular: false
            hoverEnabled: true
            horizontalPadding: 12
            verticalPadding: 7

            background: Rectangle {
                radius: action.circular ? height / 2 : 6
                color: action.destructive
                    ? (action.hovered || action.down ? Qt.tint(Colors.red, Qt.alpha(Colors.overRed, 0.12)) : Colors.red)
                    : action.hovered || action.down
                        ? Qt.tint(Colors.surfaceContainerHigh, Qt.alpha(Colors.overSurface, 0.13))
                        : Colors.surfaceContainerHigh
                border.color: Colors.outline
                border.width: action.visualFocus || !action.destructive ? 1 : 0
            }

            contentItem: Text {
                text: action.text
                font: action.font
                color: action.destructive ? Colors.overRed : Colors.overSurface
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            HoverHandler { cursorShape: Qt.PointingHandCursor }
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
                        Layout.rightMargin: 6
                        Layout.topMargin: 6

                        Label {
                            Layout.fillWidth: true
                            text: root.inspectorHandle?.title ?? "Widget tools"
                            font.bold: true
                            color: Colors.overSurface
                        }

                        EditorButton {
                            text: "×"
                            circular: true
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            padding: 0
                            font.pixelSize: 21
                            Accessible.name: "Close widget settings"
                            helpText: "Close this panel and return to the layout editor."
                            focus: true
                            onClicked: root.closeInspector()
                        }
                    }

                    LockscreenPanel {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        editorWidget: root.inspectorWidget
                        editorSettings: root.settings
                        editorPresetBaseline: root.presetBaselines[editorWidget] ?? root.settings
                        onEditorPresetApplied: (widget, values) => {
                            root.presetBaselines = Object.assign({}, root.presetBaselines, { [widget]: values });
                        }
                        onEditorValuesChanged: values => root.editLayout(values)
                    }

                    EditorButton {
                        Layout.fillWidth: true
                        Layout.margins: 6
                        visible: root.inspectorWidget !== "login"
                        destructive: true
                        text: "Remove widget"
                        helpText: "Remove this widget from the lock screen layout."
                        onClicked: scene.setWidgetEnabled(root.inspectorWidget, false)
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
                    text: root.editing ? "Drag to move or resize · Right-click empty space to add a widget" : "Lock screen preview · Esc to close"
                    color: Colors.overSurface
                }

                EditorButton {
                    text: root.editing ? "Done" : "Close"
                    onClicked: root.closePreview()
                    Keys.onEscapePressed: root.closePreview()
                }
            }
        }
    }
}
