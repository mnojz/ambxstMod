//@ pragma ShellId ambxst-veil
//@ pragma Env QSG_NO_DEPTH_BUFFER=1
//@ pragma Env QSG_ATLAS_WIDTH=256
//@ pragma Env QSG_ATLAS_HEIGHT=256

// Ambxst Cadence: the reload veil.
//
// A separate, deliberately tiny Quickshell instance spawned by the shell's
// ShellTransitions singleton (see that file for the why). It imports nothing
// from the shell so it can never trip over a broken generation. Idle it owns
// no windows and no GPU context; it only keeps the current wallpaper images
// decoded in memory so they can be mapped the instant the shell's socket
// closes.
//
// Life cycle:
//   idle     connected to the shell, waiting.
//   holding  shell gone. If the shell had announced it was leaving (it faded
//            itself out before the reload), hold plain background colour on
//            the bottom layer. Otherwise it was killed cold: map the last
//            wallpaper and frame, then play the leave animation here (frame
//            collapses into the edge, wallpaper fades to the background
//            colour) and hold that. Waits for a new shell either way.
//   done     new shell said "ready" (or nobody came): unmap and exit.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ambxst-veil.sock"

    // Testing aid: AMBXST_VEIL_SCREENS=DP-3,DP-1 limits the helper to those
    // outputs. Unset (the normal case) means every connected screen.
    readonly property var screenFilter: (Quickshell.env("AMBXST_VEIL_SCREENS") || "").split(",").map(s => s.trim()).filter(s => s.length > 0)
    readonly property var screens: Quickshell.screens.filter(s => root.screenFilter.length === 0 || root.screenFilter.indexOf(s.name) !== -1)

    property var state: ({
        bg: "#000000",
        frameColor: "#000000",
        leave: 400,
        screens: []
    })
    property var held: null      // the state snapshot frozen at the moment the shell died
    property string phase: "idle"
    property bool everConnected: false
    // The shell said it is fading itself out: hold background colour only.
    property bool shellLeaving: false
    // 1 = chrome exactly as the shell drew it, 0 = gone. Animated at hold.
    property real k: 1
    readonly property int leaveMs: Math.max(0, Number((root.held || root.state).leave) || 400)

    function screenState(name) {
        const src = root.held || root.state;
        for (const s of (src.screens || [])) {
            if (s.name === name)
                return s;
        }
        return null;
    }

    function handle(line) {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (!msg || !msg.type)
            return;
        if (msg.type === "state") {
            if (root.phase === "idle")
                root.state = msg;
        } else if (msg.type === "leaving") {
            if (root.phase === "idle")
                root.shellLeaving = true;
        } else if (msg.type === "staying") {
            if (root.phase === "idle")
                root.shellLeaving = false;
        } else if (msg.type === "ready") {
            if (root.phase === "holding")
                root.finish();
        }
    }

    function hold() {
        if (root.phase !== "idle")
            return;
        root.held = root.state;
        root.phase = "holding";
        holdTimeout.restart();
        console.log("veil: shell gone, holding", root.shellLeaving ? "(shell left on its own)" : "(cold kill, leaving here)", Date.now());
        if (root.shellLeaving)
            root.k = 0;
        else
            leaveAnim.restart();
    }

    NumberAnimation {
        id: leaveAnim
        target: root
        property: "k"
        to: 0
        duration: root.leaveMs
        easing.type: Easing.OutCubic
    }

    function finish() {
        console.log("veil: done", Date.now());
        root.phase = "done";
        Qt.callLater(() => Qt.quit());
    }

    // The connection is re-created for every attempt: a Socket that failed to
    // connect keeps its target state, and setting `connected` again is then a
    // no-op, so a plain retry never reconnects.
    property bool linked: false

    Loader {
        id: sockLoader
        active: root.phase !== "done"
        sourceComponent: Socket {
            id: sock
            path: root.socketPath
            connected: true
            onConnectedChanged: {
                if (sock.connected) {
                    root.linked = true;
                    root.everConnected = true;
                    orphanTimer.stop();
                    console.log("veil: connected to shell");
                    return;
                }
                if (root.linked) {
                    root.linked = false;
                    if (root.phase === "idle")
                        root.hold();
                }
                reconnect.restart();
            }
            onError: err => {
                if (!sock.connected)
                    reconnect.restart();
            }
            parser: SplitParser {
                onRead: line => root.handle(line)
            }
        }
    }

    Timer {
        id: reconnect
        interval: 300
        onTriggered: {
            if (root.phase === "done" || root.linked)
                return;
            sockLoader.active = false;
            sockLoader.active = true;
        }
    }

    // Started without a shell to talk to: give up rather than linger.
    Timer {
        id: orphanTimer
        interval: 15000
        running: true
        onTriggered: {
            if (!root.everConnected)
                root.finish();
        }
    }

    // Shell died and nothing replaced it (`ambxst quit`, or a shell that could
    // not start): drop the wallpaper and go.
    Timer {
        id: holdTimeout
        interval: 12000
        onTriggered: {
            if (root.phase === "holding")
                root.finish();
        }
    }

    // Keep every wallpaper decoded while idle, so mapping is instant. These
    // Images live outside any window; the visible ones below hit the pixmap
    // cache because they request the identical source and sourceSize.
    Instantiator {
        model: root.screens
        delegate: Image {
            required property ShellScreen modelData
            readonly property var st: root.screenState(modelData.name)
            source: (st && st.wall) ? "file://" + st.wall : ""
            sourceSize.width: modelData.width
            sourceSize.height: modelData.height
            asynchronous: true
            cache: true
            visible: false
        }
    }

    // ─── wallpaper hold, bottom layer ─────────────────────────────────
    Variants {
        model: root.screens
        delegate: Loader {
            id: wallLoader
            required property ShellScreen modelData
            active: root.phase === "holding"
            sourceComponent: PanelWindow {
                id: wallWindow
                screen: wallLoader.modelData
                readonly property var st: root.screenState(wallLoader.modelData.name)

                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }
                WlrLayershell.layer: WlrLayer.Bottom
                WlrLayershell.namespace: "ambxst:veil-wallpaper"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                exclusionMode: ExclusionMode.Ignore
                color: (root.held || root.state).bg || "#000000"
                mask: Region {}
                Component.onCompleted: console.log("veil: wallpaper window up", wallLoader.modelData.name, Date.now())

                Image {
                    anchors.fill: parent
                    source: (wallWindow.st && wallWindow.st.wall) ? "file://" + wallWindow.st.wall : ""
                    sourceSize.width: wallLoader.modelData.width
                    sourceSize.height: wallLoader.modelData.height
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: false
                    cache: true
                    smooth: true
                    opacity: root.shellLeaving ? 0 : Math.min(1, root.k * 1.3)
                    visible: opacity > 0
                }
            }
        }
    }

    // ─── frame collapse, overlay layer ────────────────────────────────
    Variants {
        model: root.screens
        delegate: Loader {
            id: frameLoader
            required property ShellScreen modelData
            readonly property var st: root.screenState(modelData.name)
            readonly property bool wanted: root.phase === "holding" && !root.shellLeaving && root.k > 0 && st && st.frame && st.frame.enabled && (st.frame.t + st.frame.b + st.frame.l + st.frame.r) > 0
            active: wanted
            sourceComponent: PanelWindow {
                id: frameWindow
                screen: frameLoader.modelData
                readonly property var frame: frameLoader.st.frame
                readonly property color fill: (root.held || root.state).frameColor || "#000000"

                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "ambxst:veil-frame"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                mask: Region {}

                readonly property real k: root.k
                readonly property real t: frame.t * k
                readonly property real b: frame.b * k
                readonly property real l: frame.l * k
                readonly property real r: frame.r * k
                readonly property real radius: frame.radius * k

                Rectangle { x: 0; y: 0; width: parent.width; height: frameWindow.t; color: frameWindow.fill; visible: height > 0 }
                Rectangle { x: 0; y: parent.height - frameWindow.b; width: parent.width; height: frameWindow.b; color: frameWindow.fill; visible: height > 0 }
                Rectangle { x: 0; y: frameWindow.t; width: frameWindow.l; height: parent.height - frameWindow.t - frameWindow.b; color: frameWindow.fill; visible: width > 0 }
                Rectangle { x: parent.width - frameWindow.r; y: frameWindow.t; width: frameWindow.r; height: parent.height - frameWindow.t - frameWindow.b; color: frameWindow.fill; visible: width > 0 }

                VeilCorner { x: frameWindow.l; y: frameWindow.t; size: frameWindow.radius; corner: 0; color: frameWindow.fill }
                VeilCorner { x: parent.width - frameWindow.r - width; y: frameWindow.t; size: frameWindow.radius; corner: 1; color: frameWindow.fill }
                VeilCorner { x: frameWindow.l; y: parent.height - frameWindow.b - height; size: frameWindow.radius; corner: 2; color: frameWindow.fill }
                VeilCorner { x: parent.width - frameWindow.r - width; y: parent.height - frameWindow.b - height; size: frameWindow.radius; corner: 3; color: frameWindow.fill }
            }
        }
    }

    // Concave corner filler, same shape as the shell's RoundCorner.
    component VeilCorner: Item {
        id: cornerRoot
        property int corner: 0   // 0 TL, 1 TR, 2 BL, 3 BR
        property real size: 0
        property color color: "#000000"
        width: Math.ceil(size)
        height: Math.ceil(size)
        visible: size > 0.5

        onSizeChanged: canvas.requestPaint()
        onColorChanged: canvas.requestPaint()

        Canvas {
            id: canvas
            anchors.fill: parent
            antialiasing: true
            onPaint: {
                const ctx = getContext("2d");
                const r = cornerRoot.size;
                ctx.clearRect(0, 0, width, height);
                ctx.beginPath();
                switch (cornerRoot.corner) {
                case 0:
                    ctx.arc(r, r, r, Math.PI, 3 * Math.PI / 2);
                    ctx.lineTo(0, 0);
                    break;
                case 1:
                    ctx.arc(0, r, r, 3 * Math.PI / 2, 2 * Math.PI);
                    ctx.lineTo(r, 0);
                    break;
                case 2:
                    ctx.arc(r, 0, r, Math.PI / 2, Math.PI);
                    ctx.lineTo(0, r);
                    break;
                case 3:
                    ctx.arc(0, 0, r, 0, Math.PI / 2);
                    ctx.lineTo(r, r);
                    break;
                }
                ctx.closePath();
                ctx.fillStyle = cornerRoot.color;
                ctx.fill();
            }
        }
    }
}
