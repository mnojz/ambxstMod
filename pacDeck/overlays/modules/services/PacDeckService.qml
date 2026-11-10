pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property string modId: "mnojz.pacdeck"
    readonly property string backendPath: decodeURIComponent(Qt.resolvedUrl("../../scripts/pacdeck_backend.py").toString().replace("file://", ""))
    property string preferredHelper: "auto"
    property string helper: ""
    property var helpers: []
    property var installed: []
    property var updates: ({})
    property var results: []
    property int selected: 0
    readonly property var selectedPackage: results[selected] ?? null
    property var details: ({})
    property string query: ""
    property string status: "Detecting package tools…"
    property bool searching: false
    property bool scanning: false
    property bool ready: false
    property var pendingRequests: []
    property int nextId: 1
    property int scanId: 0
    property int searchId: 0
    property int detailsId: 0
    property int job: 0
    readonly property bool busy: job !== 0
    property string phase: ""
    property real progress: -1
    property bool cancellable: false
    property bool stopRequested: false
    property string logs: ""
    property string outcome: ""
    property bool failed: false
    property var challenge: null
    property var prompt: null

    function send(command, data) {
        const request = Object.assign({}, data ?? ({}), {
            command: command,
            id: nextId++
        });
        if (ready)
            bridge.write(JSON.stringify(request) + "\n");
        else {
            pendingRequests = pendingRequests.concat([request]);
            if (!bridge.running)
                bridge.running = true;
        }
        return request.id;
    }

    function refresh() {
        scanning = true;
        scanId = send("scan", {
            helper: preferredHelper
        });
    }

    function setHelper(name) {
        if (!["auto", "paru", "yay"].includes(name))
            return;
        preferredHelper = name;
        ModsService.setSetting(modId, "aurHelper", name);
        refresh();
        searchDebounce.restart();
    }

    function search() {
        searching = true;
        status = "Searching…";
        searchId = send("search", {
            query: query,
            helper: preferredHelper
        });
    }

    function loadDetails() {
        details = ({});
        if (selectedPackage)
            detailsId = send("details", {
                name: selectedPackage.name,
                repo: selectedPackage.repo,
                helper: preferredHelper
            });
    }

    function begin(action) {
        if (busy)
            return;
        outcome = "";
        logs = "";
        failed = false;
        challenge = null;
        prompt = null;
        progress = -1;
        stopRequested = false;
        phase = "Starting…";
        job = send("transaction", Object.assign({}, action, {
            confirmed: true,
            helper: action.helper ?? preferredHelper
        }));
    }

    function respond(value) {
        if (!challenge)
            return;
        send("answer", {
            job: job,
            challenge: challenge.id,
            value: value
        });
        challenge = null;
    }

    function respondToPrompt(value) {
        if (!prompt)
            return;
        send("input", {
            job: job,
            prompt: prompt.id,
            value: value
        });
        prompt = null;
    }

    function cancel() {
        if (busy && !stopRequested) {
            stopRequested = true;
            send("cancel", {
                job: job,
                confirmed: true
            });
        }
    }

    function receive(event) {
        switch (event.event) {
        case "ready":
            ready = true;
            const queued = pendingRequests;
            pendingRequests = [];
            queued.forEach(request => bridge.write(JSON.stringify(request) + "\n"));
            if (scanId === 0)
                refresh();
            return;
        case "scan":
            if (event.id !== scanId)
                return;
            scanning = false;
            helper = event.helper;
            helpers = event.helpers;
            installed = event.rows;
            if (!query.trim()) {
                results = installed;
                selected = 0;
                status = installed.length + " explicitly installed";
                detailsDebounce.restart();
            }
            return;
        case "updates":
            if (event.id === scanId)
                updates = event.updates;
            return;
        case "search":
            if (event.id !== searchId)
                return;
            results = event.rows;
            selected = Math.min(selected, Math.max(0, results.length - 1));
            searching = !event.done;
            status = results.length + (query.trim() ? " packages" : " explicitly installed");
            detailsDebounce.restart();
            return;
        case "details":
            if (event.id === detailsId && event.name === selectedPackage?.name)
                details = event.details;
            return;
        case "error":
            if (event.id === job) {
                failed = true;
                outcome = event.message;
                job = 0;
            } else if (event.id === searchId) {
                searching = false;
                status = event.message;
            } else if (event.id === scanId) {
                scanning = false;
                status = event.message;
            }
            return;
        }
        if (event.job !== undefined && event.job !== job)
            return;
        switch (event.event) {
        case "phase":
            phase = event.label;
            progress = event.progress === null ? -1 : event.progress / 100;
            cancellable = !!event.cancellable;
            return;
        case "log":
            logs = (logs + event.text).slice(-64000);
            return;
        case "challenge":
            challenge = event;
            return;
        case "challenge_clear":
            if (challenge?.id === event.id)
                challenge = null;
            return;
        case "prompt":
            prompt = event;
            return;
        case "prompt_clear":
            prompt = null;
            return;
        case "notice":
            phase = event.message;
            return;
        case "finished":
            stopRequested = false;
            failed = !event.ok && !event.cancelled;
            outcome = event.message;
            job = 0;
            challenge = null;
            prompt = null;
            progress = event.ok ? 1 : -1;
            refresh();
            searchDebounce.restart();
            return;
        }
    }

    onQueryChanged: {
        selected = 0;
        searchDebounce.restart();
    }
    onSelectedChanged: detailsDebounce.restart()
    Timer {
        id: searchDebounce
        interval: 250
        onTriggered: root.search()
    }
    Timer {
        id: detailsDebounce
        interval: 180
        onTriggered: root.loadDetails()
    }

    Connections {
        target: ModsService
        function onSettingChanged(modId, key, value) {
            if (modId === root.modId && key === "aurHelper" && root.preferredHelper !== value) {
                root.preferredHelper = ["auto", "paru", "yay"].includes(value) ? value : "auto";
                root.refresh();
            }
        }
    }
    Component.onCompleted: {
        ModsService.getSettings(modId, (settings, error) => {
            const value = settings?.values?.aurHelper;
            preferredHelper = ["auto", "paru", "yay"].includes(value) ? value : "auto";
            refresh();
        });
    }

    Process {
        id: bridge
        command: ["python3", root.backendPath]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    root.receive(JSON.parse(line));
                } catch (error) {
                    root.status = "Could not read a package-service response.";
                }
            }
        }
        onExited: {
            root.ready = false;
            root.scanning = false;
            root.searching = false;
            if (root.busy) {
                root.failed = true;
                root.outcome = "The package service stopped. Check package state before retrying.";
                root.job = 0;
            }
            root.challenge = null;
            root.prompt = null;
        }
    }
}
