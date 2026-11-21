pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.services

// Ambxst Cadence (mnojz.cadence): the farewell.
//
// Show the farewell before requesting Power Off or Reboot so the compositor
// stays up long enough to render it. Previews use a longer reading pause.
Singleton {
    id: root

    readonly property int farewellDuration: 450
    readonly property int farewellHold: 1500
    readonly property int powerHold: 800

    readonly property string shutdownMessage: "hasta la vista baby"
    readonly property string rebootMessage: "wait for me, i'll be right back"

    // ─── state ─────────────────────────────────────────────────────────
    property bool active: false
    property bool committed: false
    property bool dryRun: false
    property bool backingOut: false
    property bool holding: false
    property string kind: ""        // "shutdown" | "reboot"
    property string screenName: ""  // the screen the quote is shown on ("" = all)
    property string quote: ""

    property real expand: 0
    property real solid: 0
    property real text: 0

    // Bar pills and dock: gone by the time the notch is 70% of the way.
    readonly property real chromeOpacity: Math.max(0, 1 - root.expand / 0.7)

    readonly property bool animate: (Config.animDuration !== undefined ? Config.animDuration : 300) > 0
    readonly property int expandMs: root.animate ? root.farewellDuration : 0
    readonly property int holdMs: root.farewellHold + root.quote.length * 40

    function request(kind: string): bool {
        const monitor = AxctlService.focusedMonitor;
        return root.begin(kind, monitor?.name ?? "", false);
    }

    function begin(kind: string, screenName: string, dryRun: bool): bool {
        if (root.active || runner.running || (kind !== "shutdown" && kind !== "reboot"))
            return false;
        root.kind = kind;
        root.screenName = screenName || "";
        root.dryRun = !!dryRun;
        root.quote = kind === "reboot" ? root.rebootMessage : root.shutdownMessage;
        root.committed = false;
        root.backingOut = false;
        root.holding = false;
        root.expand = 0;
        root.solid = 0;
        root.text = 0;
        root.active = true;
        console.log("ShellFarewell:", kind, root.dryRun ? "(preview)" : "", "--", root.quote);
        backOut.stop();
        timeline.restart();
        return true;
    }

    // A preview can skip its reading pause once the message is visible.
    function skip() {
        if (!root.active || root.committed || root.backingOut || !root.holding)
            return;
        timeline.stop();
        root.holding = false;
        root.finishPreview();
    }

    function cancel() {
        if (!root.active || root.backingOut || !root.dryRun)
            return;
        root.retreat();
    }

    function retreat() {
        timeline.stop();
        root.holding = false;
        failsafe.stop();
        previewEnd.stop();
        root.backingOut = true;
        backOut.restart();
    }

    function commit() {
        if (root.committed)
            return;
        root.committed = true;
        // No wallpaper flash if the shell dies before the compositor does.
        ShellTransitions.send({ type: "leaving" });
        runner.command = ["systemctl", "--no-block", root.kind === "reboot" ? "reboot" : "poweroff"];
        runner.running = true;
        failsafe.restart();
    }

    function finishPreview(): void {
        root.committed = true;
        previewEnd.restart();
    }

    SequentialAnimation {
        id: timeline
        NumberAnimation {
            target: root
            property: "expand"
            to: 1
            duration: root.expandMs
            easing.type: Easing.InOutCubic
        }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "solid"
                to: 1
                duration: root.animate ? 180 : 0
                easing.type: Easing.OutCubic
            }
            SequentialAnimation {
                PauseAnimation {
                    duration: root.animate ? 60 : 0
                }
                NumberAnimation {
                    target: root
                    property: "text"
                    to: 1
                    duration: root.animate ? 240 : 0
                    easing.type: Easing.OutCubic
                }
            }
        }
        ScriptAction {
            script: root.holding = root.dryRun
        }
        PauseAnimation {
            duration: root.dryRun ? root.holdMs : root.powerHold
        }
        ScriptAction {
            script: {
                root.holding = false;
                if (root.dryRun)
                    root.finishPreview();
                else
                    root.commit();
            }
        }
    }

    SequentialAnimation {
        id: backOut
        NumberAnimation {
            target: root
            property: "text"
            to: 0
            duration: root.animate ? 200 : 0
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "solid"
            to: 0
            duration: root.animate ? 150 : 0
        }
        // The power menu closes as the notch shrinks, so it lands on the
        // plain notch rather than back on the buttons.
        ScriptAction {
            script: Visibilities.setActiveModule("")
        }
        NumberAnimation {
            target: root
            property: "expand"
            to: 0
            duration: Math.round(root.expandMs * 0.75)
            easing.type: Easing.InOutCubic
        }
        ScriptAction {
            script: {
                root.active = false;
                root.backingOut = false;
                root.committed = false;
                root.dryRun = false;
            }
        }
    }

    Process {
        id: runner

        stderr: StdioCollector { id: powerError }

        onExited: exitCode => {
            if (exitCode === 0)
                return;
            console.warn("ShellFarewell:", root.kind, "failed:", powerError.text.trim());
            Notifications.notifyInternal({
                summary: root.kind === "reboot" ? "Could not restart" : "Could not power off",
                body: powerError.text.trim() || "The system declined the power request."
            });
            if (root.active && !root.backingOut) {
                ShellTransitions.send({ type: "staying" });
                root.retreat();
            }
        }
    }

    // Uncover the desktop if a request is delayed, rejected, or waiting for
    // authentication. The system request can finish after the animation closes.
    Timer {
        id: failsafe
        interval: 1600
        onTriggered: {
            if (!root.active)
                return;
            ShellTransitions.send({ type: "staying" });
            root.retreat();
        }
    }

    Timer {
        id: previewEnd
        interval: 1200
        onTriggered: root.retreat()
    }
}
