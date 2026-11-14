import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.config
import qs.modules.theme
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import "DisplayLogic.js" as Logic

Item {
    id: root
    property var outputs: []
    property string target: ""
    property bool opened: false
    property bool opening: false
    property int openingSerial: 0
    property int focused: 0
    property var controller
    property int pendingSteps: 0
    property double lastTrigger: 0
    readonly property var labels: ["Laptop only", "Mirror", "Extend", "External only"]
    readonly property var externals: Logic.external(outputs)
    readonly property int currentMode: Logic.mode(outputs, target)
    function notify(message) {
        Notifications.notifyInternal({summary: message, appName: "Display mode", replaceKey: "mnojz.displaymode", expireTimeout: 4000});
    }
    function delay(ms) {
        return new Promise(resolve => {
            const timer = timerFactory.createObject(root, {interval: ms});
            timer.triggered.connect(() => { resolve(); timer.destroy(); });
            timer.start();
        });
    }
    function run(args) {
        return new Promise((resolve, reject) => {
            const p = processFactory.createObject(root, {command: args});
            p.exited.connect((code, status) => {
                const result = p.stdout.text;
                if (code === 0 && status === 0) resolve(result);
                else reject(Error("Compositor command failed"));
                p.destroy();
            });
            p.running = true;
        });
    }
    function query() {
        return run(["hyprctl", "monitors", "all", "-j"]).then(text => {
        const data = JSON.parse(text);
        if (!Array.isArray(data)) throw Error("Invalid compositor response");
        outputs = data;
        return data;
        });
    }
    function setMonitor(s) { return run(["hyprctl", "eval", Logic.lua(s)]); }
    function close() {
        dismissTimer.stop();
        opened = false;
        opening = false;
        pendingSteps = 0;
        ++openingSerial;
    }
    function navigate(step) {
        focused = (focused + step + 4) % 4;
        lastTrigger = Date.now();
        dismissTimer.interval = 1000;
        dismissTimer.restart();
    }
    function toggle() {
        if (GlobalStates.lockscreenVisible) return;
        lastTrigger = Date.now();
        if (opened) { navigate(1); return; }
        if (opening) { ++pendingSteps; return; }
        const ticket = ++openingSerial;
        pendingSteps = 0;
        opening = true;
        query().then(data => {
            if (ticket !== openingSerial) return;
            if (!Logic.internal(data)) { notify("No internal panel identified"); return; }
            const ext = Logic.external(data);
            if (!ext.some(m => m.name === target)) target = ext.length ? ext[0].name : "";
            const active = data.find(m => m.focused);
            panel.screen = Quickshell.screens.find(s => active && s.name === active.name) || Quickshell.screens[0];
            focused = ((currentMode >= 0 ? currentMode : 0) + pendingSteps) % 4;
            opened = true;
            dismissTimer.interval = Math.max(1, 1000 - (Date.now() - lastTrigger));
            dismissTimer.restart();
            Qt.callLater(() => keyScope.forceActiveFocus());
        }).catch(e => notify(String(e.message || e))).then(() => { if (ticket === openingSerial) opening = false; });
    }
    function apply(index) {
        close();
        if (index !== 0 && !externals.length) {
            notify("No external display connected");
            return;
        }
        if (currentMode === index) return;
        controller.apply(index, target).then(() => notify(labels[index] + " applied"), e => notify(String(e.message || e)));
    }
    Timer {
        id: dismissTimer
        interval: 1000
        onTriggered: { if (root.opened) root.apply(root.focused); }
    }
    Component.onCompleted: {
        controller = new Logic.Controller({query: root.query, set: root.setMonitor, delay: root.delay});
        recovery.start();
    }
    Component.onDestruction: { if (controller) controller.cancel(); }
    Connections { target: GlobalStates; function onLockscreenVisibleChanged() { if (GlobalStates.lockscreenVisible) root.close(); } }
    Connections { target: GlobalShortcuts; function onDisplayModeRequested() { root.toggle(); } }
    IpcHandler { target: "displaymode"; function toggle(): void { root.toggle(); } }
    Component { id: timerFactory; Timer {} }
    Component {
        id: processFactory
        Process {
            id: commandProcess
            stdout: StdioCollector {}
            stderr: StdioCollector {}
            // A fresh watchdog belongs to each process; it is never reused after destruction.
            property Timer watchdog: Timer { interval: 4000; running: commandProcess.running; onTriggered: commandProcess.signal(9) }
        }
    }
    Timer {
        id: recovery
        interval: 2000
        repeat: true
        onTriggered: {
            if (!root.controller || root.controller.busy || root.opening) return;
            root.query().then(data => {
                const i = Logic.internal(data);
                if (i && !Logic.enabled(i) && !Logic.external(data).some(Logic.enabled)) {
                    root.controller.apply(0, "").then(() => root.notify("Internal display restored"), e => root.notify(String(e.message || e)));
                }
            }, () => {});
        }
    }
    PanelWindow {
        id: panel
        visible: root.opened
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "ambxst:displaymode"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        MouseArea { anchors.fill: parent; onClicked: root.close() }
        StyledRect {
            id: card
            variant: "popup"
            radius: Styling.radius(8)
            width: Math.min(536, panel.width - 32)
            height: keyScope.height + 20
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 32
            MouseArea { anchors.fill: parent } // Consume card clicks.
            Column {
                id: content
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                FocusScope {
                    id: keyScope
                    width: parent.width
                    height: 108
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) root.close();
                        else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && event.modifiers & Qt.ShiftModifier)) root.navigate(-1);
                        else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) root.navigate(1);
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) root.apply(root.focused);
                        else if (event.key === Qt.Key_Menu && root.externals.length > 1) targetPicker.popup();
                        else return;
                        event.accepted = true;
                    }
                    Menu {
                        id: targetPicker
                        onOpened: dismissTimer.stop()
                        onClosed: { if (root.opened) root.navigate(0); }
                        Repeater {
                            model: root.externals
                            MenuItem {
                                required property var modelData
                                text: modelData.name
                                checkable: true
                                checked: root.target === modelData.name
                                onTriggered: root.target = modelData.name
                            }
                        }
                    }
                    Row {
                        anchors.fill: parent
                        spacing: 6
                        Repeater {
                            model: 4
                            delegate: Button {
                                required property int index
                                width: (keyScope.width - 18) / 4
                                height: keyScope.height
                                hoverEnabled: true
                                Accessible.name: root.labels[index]
                                Accessible.description: root.currentMode === index ? "Current display arrangement" : "Apply display arrangement"
                                onClicked: root.apply(index)
                                background: StyledRect {
                                    variant: root.currentMode === index ? "focus" : "common"
                                    border.width: root.focused === index ? 2 : 0
                                    border.color: Colors.primary
                                }
                                contentItem: Item {
                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 9
                                        DisplayIcon {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: 42
                                            height: 40
                                            mode: index
                                            color: Colors.overBackground
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: root.labels[index]
                                            color: Colors.overBackground
                                            font.family: Config.theme.font
                                            font.bold: true
                                            font.pixelSize: Math.min(Config.theme.fontSize, Math.max(9, (keyScope.width - 18) / 4 / 8))
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.RightButton
                                        onClicked: { if (root.externals.length > 1) targetPicker.popup(); }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
