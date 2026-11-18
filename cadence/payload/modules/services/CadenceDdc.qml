pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Ambxst Cadence (mnojz.cadence): what the brightness service learned over
// DDC, remembered so it does not have to ask again under an animation.
//
// Every shell start, Brightness.qml runs `ddcutil detect` to find which I2C bus
// is which monitor and then reads each monitor's brightness with `ddcutil
// getvcp`. DDC traffic blocks the display driver while it is on the wire: on an
// NVIDIA desktop with two DDC monitors that froze the compositor's main loop
// for 1.2 s in total (measured against Hyprland's request socket: stalls of
// 288, 331, 207 and 335 ms) two seconds into every start, under the shell's own
// entrance -- a lag spike on every screen, in every application.
//
// Two files, because two things can go stale in two different ways:
//
//  * $XDG_RUNTIME_DIR/ambxst-cadence-ddc.json -- this session. Bus numbers
//    cannot change within a boot unless the set of monitors does, and the shell
//    itself is what sets the brightness, so a reload trusts it completely.
//  * ~/.cache/ambxst/cadence-ddc.json -- across boots, for the first start of a
//    session. A bus number is only reused if the same monitors are connected
//    AND the kernel still gives that bus the same adapter name
//    (/sys/bus/i2c/devices/i2c-N/name, e.g. "NVIDIA i2c adapter 4 at 1:00.0");
//    otherwise it is a normal detect. A level from an earlier boot is only
//    *provisional* -- somebody may have used the monitor's own buttons -- so it
//    is shown at once and then checked against the hardware a few seconds after
//    the entrance, one monitor at a time (Brightness.qml, "verify").
//
// A changed monitor set, a wake from suspend and `ambxst brightness -r` still
// go to the hardware.
Singleton {
    id: root

    readonly property string path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ambxst-cadence-ddc.json"
    readonly property string persistPath: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/ambxst/cadence-ddc.json"
    property var data: ({ key: "", monitors: [], levels: {} })

    // The cross-boot copy, waiting for its adapter names to be checked.
    property var candidate: null
    // True while that check runs; Brightness.qml waits for it before deciding
    // whether it has to detect.
    property bool busy: false
    // Buses whose level came from an earlier boot and has not been checked yet.
    property var provisional: ({})
    // Adapter names of the buses in `data`, for the cross-boot copy.
    property var adapters: ({})

    function screensKey() {
        const parts = [];
        const screens = Quickshell.screens || [];
        for (let i = 0; i < screens.length; i++)
            parts.push(String(screens[i].name) + "|" + String(screens[i].model || ""));
        parts.sort();
        return parts.join(";");
    }

    // The detect result for the monitors connected right now, or null.
    function cachedMonitors() {
        if (!root.data.key || root.data.key !== root.screensKey())
            return null;
        const m = root.data.monitors;
        return (Array.isArray(m) && m.length > 0) ? m : null;
    }
    function storeMonitors(monitors) {
        root.data = { key: root.screensKey(), monitors: monitors, levels: root.data.levels || {} };
        root.provisional = ({});
        root.write();
        root.readAdapters("record");
    }
    function level(busNum) {
        if (root.data.key !== root.screensKey())
            return null;
        const l = (root.data.levels || {})[String(busNum)];
        return (l && l.max > 0) ? l : null;
    }
    function isProvisional(busNum) {
        return !!root.provisional[String(busNum)];
    }
    // How long after its start a monitor waits before checking a provisional
    // level: past the entrance, and never two monitors at once.
    function verifyDelay(busNum) {
        const m = root.data.monitors || [];
        let index = 0;
        for (let i = 0; i < m.length; i++)
            if (String(m[i].busNum) === String(busNum))
                index = i;
        return 9000 + index * 2500;
    }
    function storeLevel(busNum, cur, max) {
        if (!busNum || !(max > 0))
            return;
        if (root.provisional[String(busNum)]) {
            const p = Object.assign({}, root.provisional);
            delete p[String(busNum)];
            root.provisional = p;
        }
        const levels = Object.assign({}, root.data.levels || {});
        const old = levels[String(busNum)];
        if (old && old.cur === cur && old.max === max)
            return;
        levels[String(busNum)] = { cur: cur, max: max };
        root.data = { key: root.data.key, monitors: root.data.monitors, levels: levels };
        writeTimer.restart();
    }
    function invalidate() {
        root.data = { key: "", monitors: [], levels: {} };
        root.provisional = ({});
        root.adapters = ({});
        root.candidate = null;
        root.write();
    }

    function write() {
        file.setText(JSON.stringify(root.data));
        if (root.data.key && Object.keys(root.adapters).length === 0)
            return; // names not read yet; "record" writes the cross-boot copy
        persist.setText(JSON.stringify({ key: root.data.key, monitors: root.data.monitors, levels: root.data.levels, adapters: root.adapters }));
    }
    Timer {
        id: writeTimer
        interval: 400
        onTriggered: root.write()
    }

    // mode "record": remember the adapter names of the buses just detected.
    // mode "check":  accept `candidate` only if its buses still have the names
    //                they had when it was written.
    function readAdapters(mode) {
        const source = mode === "check" ? root.candidate : root.data;
        const buses = [];
        const m = (source && source.monitors) || [];
        for (let i = 0; i < m.length; i++) {
            const b = String(m[i].busNum || "");
            if (/^[0-9]+$/.test(b))
                buses.push(b);
        }
        if (buses.length === 0) {
            root.candidate = null;
            root.busy = false;
            return;
        }
        adapterProc.mode = mode;
        adapterProc.buses = buses;
        adapterProc.lines = [];
        adapterProc.command = ["sh", "-c", "for b in \"$@\"; do cat /sys/bus/i2c/devices/i2c-$b/name 2>/dev/null || echo; done", "sh"].concat(buses);
        adapterProc.running = true;
    }
    Process {
        id: adapterProc
        property string mode: ""
        property var buses: []
        property var lines: []
        stdout: SplitParser {
            onRead: line => adapterProc.lines.push(String(line).trim())
        }
        onExited: {
            const names = {};
            for (let i = 0; i < adapterProc.buses.length; i++)
                names[adapterProc.buses[i]] = adapterProc.lines[i] || "";
            if (adapterProc.mode === "record") {
                root.adapters = names;
                root.write();
                return;
            }
            const c = root.candidate;
            root.candidate = null;
            let ok = !!c;
            for (let i = 0; ok && i < adapterProc.buses.length; i++) {
                const b = adapterProc.buses[i];
                ok = !!names[b] && names[b] === String((c.adapters || {})[b] || "");
            }
            if (ok) {
                const pending = {};
                for (const b in (c.levels || {}))
                    pending[b] = true;
                root.adapters = c.adapters;
                root.provisional = pending;
                root.data = { key: c.key, monitors: c.monitors, levels: c.levels || {} };
                file.setText(JSON.stringify(root.data));
            }
            root.busy = false;
        }
    }
    // A check that never answers must not hold the brightness service up.
    Timer {
        interval: 1500
        running: root.busy
        onTriggered: {
            root.candidate = null;
            root.busy = false;
        }
    }

    FileView {
        id: file
        path: root.path
        blockLoading: true
        printErrors: false
        atomicWrites: true
    }
    FileView {
        id: persist
        path: root.persistPath
        blockLoading: true
        printErrors: false
        atomicWrites: true
    }

    function parse(view) {
        if (!view.loaded)
            return null;
        try {
            const o = JSON.parse(view.text());
            if (o && typeof o === "object" && Array.isArray(o.monitors) && o.monitors.length > 0)
                return o;
        } catch (e) {}
        return null;
    }

    Component.onCompleted: {
        file.waitForJob();
        persist.waitForJob();
        const session = root.parse(file);
        const stored = root.parse(persist);
        if (session) {
            root.data = { key: String(session.key || ""), monitors: session.monitors, levels: session.levels || {} };
            if (stored && stored.key === root.data.key && stored.adapters)
                root.adapters = stored.adapters;
            else
                root.readAdapters("record");
            return;
        }
        // First start of the session: the copy from an earlier boot, if it
        // still describes this machine.
        if (stored && stored.adapters && String(stored.key || "") === root.screensKey()) {
            root.candidate = stored;
            root.busy = true;
            root.readAdapters("check");
        }
    }
}
