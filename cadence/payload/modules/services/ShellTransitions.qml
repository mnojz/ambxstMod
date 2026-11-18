pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.theme
import qs.modules.services

// Ambxst Cadence (mnojz.cadence): the staged shell enter and leave.
//
// `progress` is the one number the shell's chrome follows: 1 = in place,
// 0 = slid out past the screen edge. The frame's thickness and rounding, the
// bar, notch and dock offsets all multiply by it, the wallpaper curtain (theme
// background colour) covers the wallpaper while it is 0, and the reservation
// windows only reserve space while `reserve` is true, so the compositor's
// windows follow the frame out and back in.
//
// Entering: progress runs 0 -> 1 once the config is loaded and the first
// wallpaper image has decoded (boot and reload alike).
//
// Leaving: `leave()` runs it 1 -> 0 and fades the wallpaper to the background
// colour. Quickshell exits about ten milliseconds after the SIGTERM that
// `ambxst reload` sends and runs no QML teardown, so this has to happen
// BEFORE the reload is issued: `reload()` (the `reload` ui.run command, the
// `cadence` IPC target) leaves first and issues `ambxst reload` when
// the animation is done.
//
// The veil: for an abrupt restart, a tiny detached Quickshell
// helper (veil/Veil.qml) connected over a local socket maps the last
// wallpaper and frame the instant the shell's socket closes and plays the
// leave animation on its own, then holds the background colour until the next
// shell reports in. It is idle and windowless while the shell runs.
Singleton {
    id: root

    readonly property string modId: "mnojz.cadence"

    readonly property int enterDuration: 650
    readonly property int leaveDuration: 900
    Connections {
        target: CadenceSettings
        function onValuesChanged() {
            root.scheduleSync();
        }
    }

    // ─── state ─────────────────────────────────────────────────────────
    property bool entered: false
    property bool leaving: false

    // Three animated channels, staged from one timeline so the shell reads as
    // one deliberate movement rather than parts reacting to a restart:
    //
    //   leave (base L = leaveDuration)          enter (base E = enterDuration)
    //   chrome  0        .. 0.85 L  InOutCubic   curtain 0        .. 1.4 E   OutCubic
    //   frame   0.2 L    .. 1.2 L   InOutCubic   frame   0.2 E    .. 1.2 E   OutCubic
    //   curtain 0.1 L    .. 1.5 L   InOutSine    chrome  0.45 E   .. 1.45 E  OutCubic
    //
    // The bar, notch and dock go first on the way out and arrive last on the
    // way in; the frame follows them out and leads them in; the wallpaper is
    // the slowest, so it is still fading when the chrome has gone and already
    // back when the chrome arrives.

    // Frame thickness and rounding (ScreenFrameContent): 1 in place, 0 gone.
    property real progress: 0
    // Bar, notch and dock offsets: 1 in place, 0 past the screen edge.
    property real chromeProgress: 0
    // Opacity of the background-colour sheet over the wallpaper.
    property real curtain: 1

    // Per-run parameters, set imperatively BEFORE the targets change so the
    // Behaviors read the right values whatever the binding order.
    property int frameDelay: 0
    property int frameDur: 0
    property int frameEasing: Easing.OutCubic
    property int chromeDelay: 0
    property int chromeDur: 0
    property int chromeEasing: Easing.OutCubic
    property int curtainDelay: 0
    property int curtainDur: 0
    property int curtainEasing: Easing.OutCubic

    readonly property bool animate: Config.animDuration > 0

    Behavior on progress {
        enabled: root.animate
        SequentialAnimation {
            PauseAnimation { duration: root.frameDelay }
            NumberAnimation { duration: root.frameDur; easing.type: root.frameEasing }
        }
    }
    Behavior on chromeProgress {
        enabled: root.animate
        SequentialAnimation {
            PauseAnimation { duration: root.chromeDelay }
            NumberAnimation { duration: root.chromeDur; easing.type: root.chromeEasing }
        }
    }
    Behavior on curtain {
        enabled: root.animate
        SequentialAnimation {
            PauseAnimation { duration: root.curtainDelay }
            NumberAnimation { duration: root.curtainDur; easing.type: root.curtainEasing }
        }
    }

    // Reservation windows reserve space only while this is true, so the
    // compositor's windows expand as the frame leaves and shrink as it
    // arrives. Flipped in step with the frame channel.
    property bool reserve: false

    Timer {
        id: reserveTimer
        onTriggered: root.reserve = root.entered && !root.leaving
    }

    // Total time the leave takes on screen; what leave() reports.
    readonly property int leaveTotal: Math.round(root.leaveDuration * 1.5) + 60
    readonly property int enterTotal: Math.round(root.enterDuration * 1.45) + 60

    // ─── entering ──────────────────────────────────────────────────────
    property int wallpapersShown: 0

    // Called by Wallpaper.qml when a screen's image has decoded (static) or
    // its player has been started (video/gif).
    function wallpaperShown(screenName) {
        root.wallpapersShown += 1;
        root.maybeEnter();
    }

    // Keyed on the bar config (which sizes the frame and bar), not on
    // Config.initialLoadComplete: that one also waits for optional config
    // files and never comes true on an install where they are absent.
    readonly property bool configReady: Config.barReady && Config.themeReady
    // And on the compositor state: until monitors and clients have arrived
    // the notch and dock believe the workspace is empty and reveal
    // themselves, only to hide again a moment later.
    readonly property bool monitorsReady: AxctlService.focusedMonitor !== null && (AxctlService.monitors.values || []).length > 0
    readonly property bool clientsReady: (AxctlService.clients.values || []).length > 0
    // The window list usually lands a beat after the monitors; wait for it,
    // but not forever (an empty workspace is a legitimate state).
    property bool clientsGrace: false
    Timer {
        id: clientsGraceTimer
        interval: 400
        onTriggered: root.clientsGrace = true
    }
    onMonitorsReadyChanged: {
        if (root.monitorsReady)
            clientsGraceTimer.restart();
    }
    readonly property bool compositorReady: root.monitorsReady && (root.clientsReady || root.clientsGrace)
    readonly property bool ready: root.configReady && root.compositorReady

    function maybeEnter() {
        if (root.entered)
            return;
        if (root.ready && root.wallpapersShown > 0)
            settleTimer.restart();
    }

    function enter() {
        if (root.entered)
            return;
        const E = root.enterDuration;
        root.curtainDelay = 0;
        root.curtainDur = Math.round(E * 1.4);
        root.curtainEasing = Easing.OutCubic;
        root.frameDelay = Math.round(E * 0.2);
        root.frameDur = E;
        root.frameEasing = Easing.OutCubic;
        root.chromeDelay = Math.round(E * 0.45);
        root.chromeDur = E;
        root.chromeEasing = Easing.OutCubic;
        root.entered = true;
        root.applyTargets();
        root.tuneWindows(root.frameDur, "shellTransitionsEnter");
        if (root.barHeld) {
            barReleaseTimer.interval = Math.max(1, root.animate ? root.chromeDelay : 1);
            barReleaseTimer.restart();
        }
        osdStartTimer.interval = root.enterTotal + root.osdStartGrace;
        osdStartTimer.restart();
        reserveTimer.interval = Math.max(1, root.animate ? root.frameDelay : 1);
        reserveTimer.restart();
        windowsRestoreTimer.interval = root.enterTotal + 100;
        windowsRestoreTimer.restart();
        root.sendReady();
    }

    function applyTargets() {
        const on = root.entered && !root.leaving;
        root.progress = on ? 1 : 0;
        root.chromeProgress = on ? 1 : 0;
        root.curtain = on ? 0 : 1;
    }

    // ─── boot ──────────────────────────────────────────────────────────
    readonly property string sessionMarker: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ambxst-cadence-session"
    // Distinguish the first start of the session from a shell reload.
    FileView {
        id: markerFile
        path: root.sessionMarker
        blockLoading: true
        printErrors: false
    }
    property bool firstStart: false
    property bool barHeld: root.firstStart
    readonly property real barChrome: root.firstStart ? 1 : root.chromeProgress
    Timer {
        id: barReleaseTimer
        onTriggered: root.barHeld = false
    }

    // The next shell plays the first-start sequence.
    Process {
        id: markerClear
        running: false
        command: ["rm", "-f", root.sessionMarker]
        onExited: code => {
            if (code === 0)
                root.reload();
        }
    }

    // One frame between "decoded" and "lift the curtain" so the image has
    // actually been drawn under it.
    Timer {
        id: settleTimer
        interval: 50
        onTriggered: root.enter()
    }

    // Config and compositor ready but no image has reported in (no wallpaper
    // configured, a video that failed to start, ...): enter anyway after a beat.
    Timer {
        id: noImageTimer
        interval: 1500
        onTriggered: root.enter()
    }

    // Nothing may ever leave the shell frozen off screen.
    Timer {
        id: hardFallback
        interval: 6000
        running: true
        onTriggered: root.enter()
    }

    onReadyChanged: {
        if (root.ready) {
            root.maybeEnter();
            noImageTimer.restart();
        }
    }

    onProgressChanged: {
        if (root.progress >= 1)
            root.scheduleSync();
    }

    // ─── on-screen display ─────────────────────────────────────────────
    // Stock Ambxst shows the volume / microphone / brightness OSD whenever
    // the matching service reports a change, and the services also report
    // when they read their initial state after a start: the PipeWire sink
    // and source during the first second or so, and every monitor the moment
    // its first brightness read lands, which over DDC can be ten seconds in.
    // So the pop-up plays over (or long after) the entry, and on some setups
    // it stutters while the shell is still loading. The OSD's handlers ask
    // osdAllowed() suppresses initial audio reports during entry and the
    // grace period, plus the first brightness reading when a monitor becomes ready.
    property bool osdStartWindow: true
    readonly property int osdStartGrace: 1500
    Timer {
        id: osdStartTimer
        onTriggered: root.osdStartWindow = false
    }

    // Monitors whose `ready` has just flipped on. Brightness emits the
    // initial read in the same call right after setting ready, so it is
    // still marked when the OSD asks; cleared once the event loop moves on,
    // after every screen's OSD has asked.
    property var osdInitReads: ({})
    property int osdSwallowed: 0
    // Monitors under watch (diagnostics; one per screen).
    readonly property int osdWatched: osdMonitorWatch.count

    Instantiator {
        id: osdMonitorWatch
        model: Brightness.monitors
        delegate: Connections {
            required property var modelData
            target: modelData
            ignoreUnknownSignals: true
            function onReadyChanged() {
                if (!modelData.ready)
                    return;
                const name = modelData.screen ? modelData.screen.name : "";
                root.osdInitReads[name] = true;
                Qt.callLater(() => { delete root.osdInitReads[name]; });
            }
        }
    }

    function osdAllowed(kind: string, screenName: string): bool {
        const swallow = kind === "brightness"
            ? !!root.osdInitReads[screenName || ""]
            : root.osdStartWindow;
        if (swallow)
            root.osdSwallowed += 1;
        return !swallow;
    }

    // ─── leaving ───────────────────────────────────────────────────────
    // Slide out and fade to the background colour. Returns the number of
    // milliseconds until that is done (0 if already leaving), so a caller can
    // issue the real reload once the screen is quiet.
    function leave(): int {
        if (root.leaving)
            return 0;
        const L = root.leaveDuration;
        // Gentle throughout: ease-in-out, nothing snaps away. The chrome
        // leads, the frame follows, the wallpaper is still fading when the
        // rest has gone.
        root.chromeDelay = 0;
        root.chromeDur = Math.round(L * 0.85);
        root.chromeEasing = Easing.InOutCubic;
        root.frameDelay = Math.round(L * 0.2);
        root.frameDur = L;
        root.frameEasing = Easing.InOutCubic;
        root.curtainDelay = Math.round(L * 0.1);
        root.curtainDur = Math.round(L * 1.4);
        root.curtainEasing = Easing.InOutSine;
        root.leaving = true;
        root.applyTargets();
        root.tuneWindows(root.frameDur, "shellTransitionsLeave");
        reserveTimer.interval = Math.max(1, root.animate ? root.frameDelay : 1);
        reserveTimer.restart();
        // The frame is done at frameDelay + frameDur; put the compositor's
        // window animation back before the reload kills us.
        windowsRestoreTimer.interval = root.frameDelay + root.frameDur + 60;
        windowsRestoreTimer.restart();
        root.send({ type: "leaving" });
        return root.animate ? root.leaveTotal : 0;
    }

    // Leave, then issue the real `ambxst reload`.
    function reload(): int {
        const ms = root.leave();
        reloadTimer.interval = Math.max(1, ms);
        reloadTimer.restart();
        return ms;
    }

    Timer {
        id: reloadTimer
        onTriggered: Quickshell.execDetached(["ambxst", "reload"])
    }

    IpcHandler {
        target: "cadence"

        function leave(): int {
            return root.leave();
        }

        function reload(): int {
            return root.reload();
        }

        function progress(): real {
            return root.progress;
        }

        // The farewell (ShellFarewell): `shutdown` / `reboot` do what the power
        // menu's buttons do, on the focused screen; `farewellPreview` plays the
        // same thing with a quote of that kind and then backs out, running
        // nothing; `farewellCancel` is the Escape key.
        function shutdown(): bool {
            return ShellFarewell.request("shutdown");
        }
        function reboot(): bool {
            return ShellFarewell.request("reboot");
        }
        function farewellPreview(kind: string): bool {
            const mon = AxctlService.focusedMonitor;
            return ShellFarewell.begin(kind === "reboot" ? "reboot" : "shutdown", mon?.name ?? "", true);
        }
        function farewellCancel(): void {
            ShellFarewell.cancel();
        }

        // Why a screen's bar is where it is: per screen, whether the shell
        // thinks a fullscreen window covers it, which record says so (axctl's
        // or Hyprland's) and the bar's slide state. Run it while the bar is
        // stuck and paste the output into a bug report.
        function coverState(): string {
            const out = [];
            const panels = Visibilities.barPanels || {};
            for (const name in panels) {
                const pnl = panels[name];
                if (pnl && typeof pnl.coverReport === "function")
                    out.push(pnl.coverReport());
            }
            return JSON.stringify(out, null, 2);
        }

        function bootPreview(): void {
            markerClear.running = true;
        }
        function bootState(): string {
            return JSON.stringify({ firstStart: root.firstStart, barHeld: root.barHeld, entered: root.entered });
        }

        function farewellState(): string {
            return JSON.stringify({ active: ShellFarewell.active, kind: ShellFarewell.kind, quote: ShellFarewell.quote, screen: ShellFarewell.screenName, expand: ShellFarewell.expand, solid: ShellFarewell.solid, text: ShellFarewell.text, holding: ShellFarewell.holding, committed: ShellFarewell.committed, dryRun: ShellFarewell.dryRun, holdMs: ShellFarewell.holdMs });
        }

        // Mod updates: `updateCheck` asks Ambxst's own updater to check every
        // mod now (as Settings > Mods' button does); Cadence notifies when it
        // finds something. `updateState` prints what is offered and announced.
        function updateCheck(): void {
            ModsService.checkUpdates([]);
        }
        function updateState(): string {
            return JSON.stringify(ModUpdateService.report(), null, 2);
        }

        // Diagnostics: `qs ipc --pid $(cat $XDG_RUNTIME_DIR/ambxst-qs.pid) call cadence state`
        function state(): string {
            return JSON.stringify({
                entered: root.entered,
                leaving: root.leaving,
                progress: root.progress,
                chromeProgress: root.chromeProgress,
                curtain: root.curtain,
                reserve: root.reserve,
                compositorReady: root.compositorReady,
                wallpapersShown: root.wallpapersShown,
                configReady: root.configReady,
                initialLoadComplete: Config.initialLoadComplete,
                veilConnected: !!root.client,
                osd: "quiet",
                osdStartWindow: root.osdStartWindow,
                osdWatched: root.osdWatched,
                osdSwallowed: root.osdSwallowed,
                wallpapers: root.wallpapers.length,
                frames: root.frames.length
            });
        }
    }

    // ─── registry (filled by the patched Wallpaper / ScreenFrameContent) ──
    property var wallpapers: []
    property var frames: []

    function registerWallpaper(w) {
        if (!w || root.wallpapers.indexOf(w) !== -1)
            return;
        root.wallpapers = root.wallpapers.concat([w]);
        root.scheduleSync();
    }
    function unregisterWallpaper(w) {
        root.wallpapers = root.wallpapers.filter(x => x && x !== w);
        root.scheduleSync();
    }
    function registerFrame(f) {
        if (!f || root.frames.indexOf(f) !== -1)
            return;
        root.frames = root.frames.concat([f]);
        root.scheduleSync();
    }
    function unregisterFrame(f) {
        root.frames = root.frames.filter(x => x && x !== f);
        root.scheduleSync();
    }

    // Re-snapshot whenever something the veil draws changes.
    Instantiator {
        model: root.wallpapers
        delegate: Connections {
            required property var modelData
            target: modelData
            ignoreUnknownSignals: true
            function onEffectiveWallpaperChanged() { root.scheduleSync(); }
            function onCurrentScreenNameChanged() { root.scheduleSync(); }
        }
    }

    Instantiator {
        model: root.frames
        delegate: Connections {
            required property var modelData
            target: modelData
            ignoreUnknownSignals: true
            function onTopThicknessChanged() { root.scheduleSync(); }
            function onBottomThicknessChanged() { root.scheduleSync(); }
            function onLeftThicknessChanged() { root.scheduleSync(); }
            function onRightThicknessChanged() { root.scheduleSync(); }
            function onTargetInnerRadiusChanged() { root.scheduleSync(); }
            function onFrameEnabledChanged() { root.scheduleSync(); }
        }
    }

    Connections {
        target: Colors
        ignoreUnknownSignals: true
        function onBackgroundChanged() { root.scheduleSync(); }
    }

    Connections {
        target: Config.theme
        ignoreUnknownSignals: true
        function onSrBgChanged() { root.scheduleSync(); }
    }

    // ─── compositor window animation ───────────────────────────────────
    // The windows expanding into the frame's space (and shrinking back) are
    // moved by the compositor with its own resize animation, which on
    // Hyprland is `windowsMove` (250 ms by default): they snapped ahead of
    // the frame. For the duration of a transition that animation is retuned
    // to the frame channel's duration and easing, so windows and frame move
    // as one, then restored. Hyprland only; other compositors are left alone.
    readonly property bool hyprland: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "") !== ""
    readonly property string windowsStateFile: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ambxst/cadence-windowsmove.json"

    // Effective original windowsMove settings, captured once at startup.
    property var windowsOriginal: null
    property bool windowsTuned: false

    function hypr(lua) {
        if (!root.hyprland)
            return;
        Quickshell.execDetached({ command: ["hyprctl", "eval", lua] });
    }

    function luaAnim(speed, bezier, style) {
        let lua = "hl.animation({ leaf = \"windowsMove\", enabled = true, speed = " + Number(speed).toFixed(2);
        if (bezier)
            lua += ", bezier = \"" + bezier + "\"";
        if (style)
            lua += ", style = \"" + style + "\"";
        return lua + " })";
    }

    function tuneWindows(durationMs, curve) {
        if (!root.hyprland || !root.animate || !root.windowsOriginal)
            return;
        if (!root.windowsTuned) {
            root.windowsTuned = true;
            // Remember the originals on disk so a shell killed mid-transition
            // (cold reload) still gets them restored by the next one.
            windowsStateWriter.command = ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"", "_", root.windowsStateFile, JSON.stringify(root.windowsOriginal)];
            windowsStateWriter.running = true;
        }
        // Speed is in units of 100 ms. The curve is (re)registered in the
        // same call: Ambxst reloads the Hyprland config after every shell
        // start, which drops curves registered at runtime, and a missing
        // curve silently falls back to Hyprland's default (a fast start),
        // which is exactly the lurch this is meant to remove.
        root.hypr(root.curveLua(curve) + "; " + root.luaAnim(Math.max(0.1, durationMs / 100), curve, ""));
    }

    function restoreWindows(values) {
        const o = values || root.windowsOriginal;
        if (!root.hyprland || !o)
            return;
        root.hypr(root.luaAnim(o.speed, o.bezier, o.style));
        root.windowsTuned = false;
        windowsStateWriter.command = ["rm", "-f", root.windowsStateFile];
        windowsStateWriter.running = true;
    }

    Timer {
        id: windowsRestoreTimer
        onTriggered: root.restoreWindows(null)
    }

    Process {
        id: windowsStateWriter
        running: false
    }

    // Capture the effective windowsMove settings (walk up the tree if it is
    // not overridden itself), and restore a previous shell's leftovers.
    Process {
        id: windowsProbe
        running: false
        command: ["sh", "-c", "hyprctl animations -j; echo; echo ---STATE---; cat \"$1\" 2>/dev/null", "_", root.windowsStateFile]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.split("---STATE---");
                let anims = null;
                try {
                    const d = JSON.parse(parts[0]);
                    anims = Array.isArray(d) ? d[0] : (d.animations || null);
                } catch (e) {}
                let leftover = null;
                if (parts.length > 1 && parts[1].trim().length > 0) {
                    try { leftover = JSON.parse(parts[1].trim()); } catch (e) {}
                }
                if (leftover && leftover.speed !== undefined) {
                    // A previous shell died mid-transition: these are the real
                    // originals, and Hyprland is still holding our tuning.
                    root.windowsOriginal = leftover;
                    root.restoreWindows(leftover);
                    return;
                }
                if (!Array.isArray(anims))
                    return;
                const byName = {};
                for (const a of anims)
                    byName[a.name] = a;
                let eff = null;
                for (const name of ["windowsMove", "windows", "global"]) {
                    const a = byName[name];
                    if (a && a.overridden && a.enabled) { eff = a; break; }
                }
                if (!eff) {
                    // Hyprland's built-in default when nothing is set.
                    eff = { speed: 10, bezier: "default", style: "" };
                }
                root.windowsOriginal = { speed: eff.speed, bezier: eff.bezier || "default", style: "" };
            }
        }
    }

    // The two easing curves the frame channel uses (ease-in-out cubic on the
    // way out, ease-out cubic on the way in), as Hyprland bezier definitions.
    function curveLua(name) {
        if (name === "shellTransitionsLeave")
            return "hl.curve(\"shellTransitionsLeave\", { type = \"bezier\", points = { {0.65, 0.0}, {0.35, 1.0} } })";
        return "hl.curve(\"shellTransitionsEnter\", { type = \"bezier\", points = { {0.33, 1.0}, {0.68, 1.0} } })";
    }

    // ─── veil protocol ─────────────────────────────────────────────────
    // Newline-delimited JSON, shell -> veil only:
    //   {"type":"state", ...snapshot()}   on connect and whenever it changes
    //   {"type":"leaving"}                the shell is fading out itself
    //   {"type":"staying"}                ...it is not after all (a farewell backed out)
    //   {"type":"ready"}                  this shell's wallpaper is on screen
    readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ambxst-veil.sock"
    readonly property string veilQml: Quickshell.shellPath("modules/services/veil/Veil.qml")

    property var client: null
    property int spawnsThisMinute: 0

    function frameColor() {
        const cfg = Config.theme.srBg;
        let c = Colors.background;
        let a = 1;
        if (cfg) {
            const stops = cfg.gradient;
            if (stops && stops.length > 0 && stops[0] && stops[0][0])
                c = Config.resolveColor(stops[0][0]);
            if (cfg.opacity !== undefined && cfg.opacity !== null)
                a = Number(cfg.opacity);
            if (isNaN(a))
                a = 1;
        }
        const col = Qt.color(c);
        return Qt.rgba(col.r, col.g, col.b, col.a * a).toString();
    }

    function snapshot() {
        const screens = {};
        for (const w of root.wallpapers) {
            if (!w || !w.currentScreenName)
                continue;
            let path = w.effectiveWallpaper || "";
            if (path && typeof w.getLockscreenFramePath === "function")
                path = w.getLockscreenFramePath(path) || path;
            screens[w.currentScreenName] = Object.assign(screens[w.currentScreenName] || {}, {
                name: w.currentScreenName,
                wall: path
            });
        }
        for (const f of root.frames) {
            if (!f || !f.targetScreen)
                continue;
            const name = f.targetScreen.name;
            screens[name] = Object.assign(screens[name] || { name: name, wall: "" }, {
                frame: {
                    enabled: !!f.frameEnabled,
                    t: f.topThickness,
                    b: f.bottomThickness,
                    l: f.leftThickness,
                    r: f.rightThickness,
                    radius: f.targetInnerRadius
                }
            });
        }
        return {
            type: "state",
            bg: Colors.background.toString(),
            frameColor: root.frameColor(),
            leave: root.leaveDuration,
            screens: Object.values(screens)
        };
    }

    Timer {
        id: syncTimer
        interval: 150
        onTriggered: root.sendState()
    }

    function scheduleSync() {
        if (root.client && root.progress >= 1)
            syncTimer.restart();
    }

    function send(obj) {
        if (!root.client || !root.client.connected)
            return;
        root.client.write(JSON.stringify(obj) + "\n");
        root.client.flush();
    }

    function sendState() {
        if (root.progress < 1 || root.leaving)
            return;
        root.send(root.snapshot());
    }

    function sendReady() {
        root.send({ type: "ready" });
    }

    SocketServer {
        id: server
        active: true
        path: root.socketPath
        onActiveStatusChanged: {
            if (active)
                spawnTimer.restart();
        }
        handler: Socket {
            id: conn
            onConnectedChanged: {
                if (conn.connected) {
                    root.client = conn;
                    root.sendState();
                    if (root.entered)
                        root.sendReady();
                } else if (root.client === conn) {
                    root.client = null;
                    spawnTimer.restart();
                }
            }
            parser: SplitParser {
                onRead: msg => {}
            }
        }
    }

    // Spawn the helper when none is connected. Delayed so a helper that is
    // still shutting down (after serving the previous reload) has gone first.
    Timer {
        id: spawnTimer
        interval: 1000
        onTriggered: root.ensureVeil()
    }

    Timer {
        id: spawnBudget
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.spawnsThisMinute = 0
    }

    function ensureVeil() {
        if (root.client || root.leaving)
            return;
        if (root.spawnsThisMinute >= 5) {
            console.warn("ShellTransitions: veil helper keeps exiting, not respawning this minute");
            return;
        }
        root.spawnsThisMinute += 1;
        // setsid: the helper must not sit in Quickshell's process group, which
        // the Ambxst daemon kills as a whole on shutdown.
        Quickshell.execDetached({
            command: ["setsid", "-f", "qs", "-p", root.veilQml],
            workingDirectory: Quickshell.shellDir
        });
        // If it failed to come up, try again later (bounded above).
        retryTimer.restart();
    }

    Timer {
        id: retryTimer
        interval: 4000
        onTriggered: {
            if (!root.client)
                spawnTimer.restart();
        }
    }

    Component.onCompleted: {
        // A blocking read classifies the start once, before setting the marker.
        markerFile.text();
        root.firstStart = !markerFile.loaded;
        if (root.firstStart)
            markerFile.setText("started\n");
        if (root.hyprland)
            windowsProbe.running = true;
        // This singleton is created on first use, which is usually after the
        // config has already finished loading, so the change signal above
        // never comes: evaluate the entry conditions once right now.
        if (root.monitorsReady)
            clientsGraceTimer.restart();
        if (root.ready) {
            root.maybeEnter();
            noImageTimer.restart();
        }
        // Same for the socket server: it was active before any handler could
        // observe the change, so arm the first spawn here.
        if (server.active)
            spawnTimer.restart();
    }
}
