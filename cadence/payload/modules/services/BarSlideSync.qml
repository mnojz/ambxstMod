pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Ambxst Cadence (mnojz.cadence): keeps the compositor's window move in step with the
// bar's fullscreen slide.
//
// When the bar hides for a fullscreen window its exclusive zone changes, and
// the compositor moves the windows into (or out of) that space with its own
// resize animation -- on Hyprland `windowsMove`, which Ambxst configures to
// 250 ms. Cadence retunes `windowsMove` for the slide to the bar's own
// duration and curve, and the bar's space then changes in one step as the
// slide starts: the windows glide into (or out of) it on the same function
// of time as the bar. (Until 3.0.3 the zone was walked frame by frame with
// `windowsMove` near-instant -- exact to the pixel, but every step resized
// every window on the screen, and with a browser open the slide crawled and
// snapped.) Put back once things are quiet.
// Hyprland only; other compositors are left alone.
//
// This is the same idea ShellTransitions applies to the shell enter/leave,
// on its own curve and state file. The restore is guarded: it
// re-reads Hyprland first and only writes the originals back if `windowsMove`
// still carries this mod's own curve, so a transition another mod has taken
// over is not yanked out from under it.
Singleton {
    id: root

    readonly property string modId: "mnojz.cadence"

    readonly property bool hyprland: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "") !== ""
    readonly property bool animate: (Config.animDuration !== undefined ? Config.animDuration : 0) > 0

    // The bar's slide curve (BarContent feeds it to a BezierSpline easing);
    // also registered with Hyprland under `curveName` so the restore guard
    // can recognise this mod's own tuning. Cubic ease-in-out.
    readonly property var bezier: [0.65, 0, 0.35, 1]
    readonly property string curveName: "ambxstBarSlide"

    readonly property string stateFile: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ambxst/cadence-barslide-windowsmove.json"

    // Effective original windowsMove, captured once at startup.
    property var original: null

    // How long the compositor takes to bring a (special) workspace on screen,
    // so the covered screen can let the window fully arrive before its chrome
    // leaves. From Hyprland's `specialWorkspace` animation (falling back to
    // `workspaces`, then `global`); animDuration off Hyprland.
    readonly property int arrivalDelayMs: root.arrivalFromCompositor > 0 ? root.arrivalFromCompositor : (Config.animDuration !== undefined ? Config.animDuration : 300)
    property int arrivalFromCompositor: 0
    property bool tuned: false
    property real tunedSpeed: 0

    // Hyprland has two config parsers. Stock builds take `hyprctl keyword`;
    // builds on the Lua config reject it ("keyword can't work with
    // non-legacy parsers") and take `hyprctl eval` instead. Every change is
    // issued in both dialects; the one the parser does not speak fails
    // harmlessly.
    function hyprCommand(keywords, lua) {
        let sh = "";
        for (const k of keywords)
            sh += "hyprctl keyword " + k + " >/dev/null 2>&1; ";
        sh += "hyprctl eval " + root.shellQuote(lua) + " >/dev/null 2>&1; true";
        return ["sh", "-c", sh];
    }

    function shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    function hypr(keywords, lua) {
        if (!root.hyprland)
            return;
        Quickshell.execDetached({ command: root.hyprCommand(keywords, lua) });
    }

    function curveLua() {
        const b = root.bezier;
        return "hl.curve(\"" + root.curveName + "\", { type = \"bezier\", points = { {" + b[0] + ", " + b[1] + "}, {" + b[2] + ", " + b[3] + "} } })";
    }

    function animLua(speed, bezierName, style) {
        let lua = "hl.animation({ leaf = \"windowsMove\", enabled = true, speed = " + Number(speed).toFixed(2);
        if (bezierName)
            lua += ", bezier = \"" + bezierName + "\"";
        if (style)
            lua += ", style = \"" + style + "\"";
        return lua + " })";
    }

    // The same two statements for the stock parser.
    function curveKeyword() {
        const b = root.bezier;
        return "bezier " + root.curveName + "," + b[0] + "," + b[1] + "," + b[2] + "," + b[3];
    }

    function animKeyword(speed, bezierName, style) {
        let k = "animation windowsMove,1," + Number(speed).toFixed(2) + "," + (bezierName || "default");
        if (style)
            k += "," + style;
        return k;
    }

    // Called by every BarContent starting a deliberate slide, so it is cheap
    // to call twice: a second call at the same speed only pushes the restore
    // back. `onLanded` runs once Hyprland has the new values -- the caller
    // starts its slide and changes the exclusive zone THEN, so the windows
    // never begin on the old 250 ms curve and switch mid-flight (that put
    // them a few pixels ahead of the bar for the first part of every hide).
    // Off Hyprland, or with animations off, it runs straight away.
    property var pending: []

    // `matched`: the bar's space moves in ONE step and Hyprland animates the
    // windows into it on the slide's own duration and curve (speed is in
    // tenths of a second). Walking the zone every frame instead resized every
    // window on the screen every frame; with heavy clients (a browser) each
    // step took 50-100 ms and a 480 ms slide crawled for up to 1.4 s, then
    // snapped. Without it: near-instant, for callers still walking the zone.
    function tune(durationMs, onLanded, matched) {
        const done = function() { if (onLanded) onLanded(); };
        if (!root.hyprland || !root.animate || !root.original) {
            done();
            return;
        }
        const speed = matched ? Math.max(0.1, Math.round(durationMs / 10) / 10) : 0.1;
        restoreTimer.interval = Math.round(durationMs) + 120;
        restoreTimer.restart();
        if (root.tuned && Math.abs(root.tunedSpeed - speed) < 0.01 && !tuneProc.running) {
            done();
            return;
        }
        root.pending.push(done);
        if (tuneProc.running)
            return; // the eval in flight carries the same values
        if (!root.tuned) {
            // Remember the originals on disk so a shell killed mid-slide
            // still gets them restored by the next one.
            stateWriter.command = ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"", "_", root.stateFile, JSON.stringify(root.original)];
            stateWriter.running = true;
        }
        root.tuned = true;
        root.tunedSpeed = speed;
        // The curve is (re)registered in the same call: Ambxst re-sources the
        // Hyprland config after every shell start, which drops curves added at
        // runtime, and a missing curve silently falls back to Hyprland's
        // default.
        tuneProc.command = root.hyprCommand([root.curveKeyword(), root.animKeyword(speed, root.curveName, "")],
                                            root.curveLua() + "; " + root.animLua(speed, root.curveName, ""));
        tuneProc.running = true;
        landedGuard.restart();
    }

    function flushPending() {
        landedGuard.stop();
        const cbs = root.pending;
        root.pending = [];
        // Each callback on its own: one queued by a bar whose screen has gone
        // away since (a monitor unplugged or replaced mid-slide) throws from
        // its dead context, and an uncaught throw ended the loop -- every bar
        // queued behind it kept its target and never moved. A screen plugged
        // in after all the others had gone came up without a bar that way.
        for (const cb of cbs) {
            try {
                cb();
            } catch (e) {
                console.warn("BarSlideSync: dropped a slide callback from a bar that no longer exists:", e);
            }
        }
    }

    Process {
        id: tuneProc
        running: false
        onExited: root.flushPending()
    }

    // A hyprctl that hangs or is missing must not hold the bar in place: the
    // slide goes ahead without the sync after this long.
    Timer {
        id: landedGuard
        interval: 250
        onTriggered: root.flushPending()
    }

    function restore(values) {
        const o = values || root.original;
        if (!root.hyprland || !o)
            return;
        root.hypr([root.animKeyword(o.speed, o.bezier, o.style)], root.animLua(o.speed, o.bezier, o.style));
        root.tuned = false;
        stateWriter.command = ["rm", "-f", root.stateFile];
        stateWriter.running = true;
    }

    Timer {
        id: restoreTimer
        onTriggered: restoreProbe.running = true
    }

    Process {
        id: stateWriter
        running: false
    }

    function parseAnimations(text) {
        try {
            const d = JSON.parse(text);
            const anims = Array.isArray(d) ? d[0] : (d.animations || null);
            if (!Array.isArray(anims))
                return null;
            const byName = {};
            for (const a of anims)
                byName[a.name] = a;
            return byName;
        } catch (e) {
            return null;
        }
    }

    // Only put the originals back if windowsMove still carries our curve.
    Process {
        id: restoreProbe
        running: false
        command: ["hyprctl", "animations", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                const byName = root.parseAnimations(this.text);
                const wm = byName ? byName["windowsMove"] : null;
                if (wm && wm.bezier === root.curveName) {
                    root.restore(null);
                } else {
                    // Someone else owns it now; just forget our claim.
                    root.tuned = false;
                    stateWriter.command = ["rm", "-f", root.stateFile];
                    stateWriter.running = true;
                }
            }
        }
    }

    // Capture the effective windowsMove (walk up the tree if it is not
    // overridden itself), and restore a previous shell's leftovers.
    Process {
        id: startProbe
        running: false
        command: ["sh", "-c", "hyprctl animations -j; echo; echo ---STATE---; cat \"$1\" 2>/dev/null", "_", root.stateFile]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.split("---STATE---");
                let leftover = null;
                if (parts.length > 1 && parts[1].trim().length > 0) {
                    try { leftover = JSON.parse(parts[1].trim()); } catch (e) {}
                }
                if (leftover && leftover.speed !== undefined) {
                    root.original = leftover;
                    root.restore(leftover);
                    return;
                }
                const byName = root.parseAnimations(parts[0]);
                if (!byName)
                    return;
                for (const name of ["specialWorkspace", "workspaces", "global"]) {
                    const a = byName[name];
                    if (a && a.overridden && a.enabled && a.speed > 0) {
                        root.arrivalFromCompositor = Math.round(a.speed * 100);
                        break;
                    }
                }
                let eff = null;
                for (const name of ["windowsMove", "windows", "global"]) {
                    const a = byName[name];
                    if (a && a.overridden && a.enabled) { eff = a; break; }
                }
                if (!eff)
                    eff = { speed: 10, bezier: "default", style: "" };
                // A stale copy of our own curve is not an original either.
                if (eff.bezier === root.curveName)
                    eff = { speed: 2.5, bezier: "default", style: "" };
                root.original = { speed: eff.speed, bezier: eff.bezier || "default", style: "" };
            }
        }
    }

    Component.onCompleted: {
        if (root.hyprland)
            startProbe.running = true;
    }
}
