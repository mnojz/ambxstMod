pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property string modId: "mnojz.parcel"
    readonly property string backendPath: decodeURIComponent(Qt.resolvedUrl("../../scripts/parcel_backend.py").toString().replace("file://", ""))
    property string preferredHelper: "auto"
    property string helper: ""
    property var helpers: []
    property var installed: []
    property var updates: ({})
    property var results: []
    property int selected: 0
    readonly property var selectedPackage: results[selected] ?? null
    property var details: ({})
    property var packageMetadata: ({})
    property string detailsError: ""
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
    property string progressMode: "loading"
    property int progressStep: 1
    property string phaseDetail: ""
    property int completedPackages: 0
    property int totalPackages: 0
    property string progressUnit: "packages"
    property bool cancellable: false
    property bool stopRequested: false
    property string logs: ""
    property var activityTransaction: ({})
    property string outcome: ""
    property bool failed: false
    property var challenge: null
    property var prompt: null

    property var viewAttention: ({})
    readonly property bool hasAttentiveView: Object.values(viewAttention).some(focused => focused)
    property string lastNotifiedChallenge: ""
    property int authenticationNotificationId: 0

    function setViewAttention(key, focused) {
        if (viewAttention[key] === focused)
            return;
        viewAttention = Object.assign({}, viewAttention, {
            [key]: focused
        });
    }
    function removeViewAttention(key) {
        const views = Object.assign({}, viewAttention);
        delete views[key];
        viewAttention = views;
    }
    function clearAuthenticationNotification() {
        if (!authenticationNotificationId)
            return;
        const id = authenticationNotificationId;
        authenticationNotificationId = 0;
        Notifications.discardNotification(id);
    }
    function notifyAuthentication() {
        if (challenge?.kind !== "password" || hasAttentiveView || lastNotifiedChallenge === String(challenge.id))
            return;
        const challengeId = String(challenge.id);
        const notification = Notifications.notifyInternal({
            appName: "Parcel",
            appIcon: "system-software-install",
            summary: "Password needed to continue",
            body: "Your package operation is paused. Open Parcel to authenticate.",
            urgency: "normal",
            replaceKey: "parcel-authentication",
            expireTimeout: 10000,
            actions: [
                {
                    identifier: "open",
                    text: "Open Parcel"
                }
            ],
            actionHandlers: {
                open: function () {
                    if (root.challenge?.kind === "password" && String(root.challenge.id) === challengeId)
                        Visibilities.setActiveModule("parcel");
                }
            }
        });
        if (notification) {
            lastNotifiedChallenge = challengeId;
            authenticationNotificationId = notification.id;
        }
    }
    onChallengeChanged: {
        clearAuthenticationNotification();
        authenticationAttention.restart();
    }
    onHasAttentiveViewChanged: {
        if (hasAttentiveView) {
            clearAuthenticationNotification();
            if (databaseRefreshPending)
                automaticRefresh.restart();
        } else
            authenticationAttention.restart();
    }
    Timer {
        id: authenticationAttention
        interval: 350
        onTriggered: root.notifyAuthentication()
    }

    property bool databaseRefreshPending: false
    function queueDatabaseRefresh() {
        databaseRefreshPending = true;
        if (!busy && hasAttentiveView)
            automaticRefresh.restart();
    }
    // Pacman's transaction lock also covers changes made by other frontends.
    // Watch its directory without polling or adding an external watcher command.
    FolderListModel {
        id: packageDatabaseLock
        folder: "file:///var/lib/pacman"
        nameFilters: ["db.lck"]
        showFiles: true
        showDirs: false
        showDotAndDotDot: false
        onCountChanged: root.queueDatabaseRefresh()
        onStatusChanged: {
            if (status === FolderListModel.Ready && count === 0 && root.databaseRefreshPending)
                root.queueDatabaseRefresh();
        }
    }
    Timer {
        id: automaticRefresh
        interval: 1000
        onTriggered: {
            if (!root.databaseRefreshPending || root.busy || !root.hasAttentiveView)
                return;
            if (packageDatabaseLock.status !== FolderListModel.Ready || packageDatabaseLock.count > 0)
                return;
            root.refresh();
            if (root.query.trim())
                searchDebounce.restart();
        }
    }

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
        databaseRefreshPending = false;
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

    function rememberMetadata(rows) {
        const cached = Object.assign({}, packageMetadata);
        for (const row of rows) {
            if (row.details && Object.keys(row.details).length)
                cached[row.name] = row.details;
        }
        packageMetadata = cached;
    }

    function loadDetails() {
        detailsDebounce.stop();
        detailsError = "";
        details = selectedPackage ? (packageMetadata[selectedPackage.name] ?? ({})) : ({});
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
        activityTransaction = {
            operation: action.operation,
            name: action.name || "",
            helper: action.helper || preferredHelper,
            state: "running"
        };
        outcome = "";
        logs = "";
        failed = false;
        challenge = null;
        prompt = null;
        progress = -1;
        progressMode = "loading";
        progressStep = 1;
        phaseDetail = "";
        completedPackages = 0;
        totalPackages = 0;
        progressUnit = "packages";
        stopRequested = false;
        phase = "Retrieving info";
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
            rememberMetadata(event.rows);
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
            rememberMetadata(event.rows);
            results = event.rows;
            selected = Math.min(selected, Math.max(0, results.length - 1));
            searching = !event.done;
            status = results.length + (query.trim() ? " packages" : " explicitly installed");
            detailsDebounce.restart();
            return;
        case "details":
            if (event.id === detailsId && event.name === selectedPackage?.name) {
                if (Object.keys(event.details).length) {
                    rememberMetadata([
                        {
                            name: event.name,
                            details: event.details
                        }
                    ]);
                    details = event.details;
                } else {
                    detailsError = event.error || "Package details are unavailable.";
                }
            }
            return;
        case "error":
            if (event.id === job) {
                failed = true;
                outcome = event.message;
                activityTransaction = Object.assign({}, activityTransaction, {
                    state: "failed",
                    message: event.message
                });
                job = 0;
            } else if (event.id === detailsId) {
                detailsError = event.message;
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
            totalPackages = Math.max(0, event.total ?? 0);
            completedPackages = Math.max(0, Math.min(totalPackages, event.completed ?? 0));
            progressUnit = event.unit ?? "packages";
            progressMode = event.mode ?? (totalPackages > 1 ? "packages" : "loading");
            progressStep = event.step ?? 1;
            phaseDetail = event.detail ?? "";
            progress = progressMode === "percentage" && event.progress !== null && event.progress !== undefined ? Math.max(0, Math.min(1, event.progress / 100)) : progressMode === "packages" && totalPackages > 0 ? completedPackages / totalPackages : -1;
            cancellable = !!event.cancellable;
            return;
        case "log":
            logs = (logs + event.text).slice(-64000);
            return;
        case "challenge":
            if (event.kind === "review") {
                send("answer", {
                    job: job,
                    challenge: event.id,
                    value: true
                });
            } else {
                challenge = event;
            }
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
            activityTransaction = Object.assign({}, activityTransaction, {
                state: event.cancelled ? "cancelled" : event.ok ? "done" : "failed",
                message: event.message
            });
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
                root.activityTransaction = Object.assign({}, root.activityTransaction, {
                    state: "failed",
                    message: root.outcome
                });
                root.job = 0;
            }
            root.challenge = null;
            root.prompt = null;
        }
    }
}
