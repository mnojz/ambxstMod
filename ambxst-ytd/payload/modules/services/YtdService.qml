pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "YtdHistory.js" as YtdHistory
import "YtdUrl.js" as YtdUrl


Singleton {
    id: root

    readonly property string helperPath: decodeURIComponent(Qt.resolvedUrl("../bar/ytd_helper.py").toString().replace("file://", ""))
    readonly property var formats: ["mp3", "480p", "720p", "1080p", "1440p", "2160p"]
    readonly property string defaultFormat: "1080p"
    readonly property string historyStateKey: "community.ambxstytd.history"
    readonly property int historyLimit: 40
    readonly property int maxQueuedRequests: 5

    property string url: ""
    property string mediaFormat: defaultFormat
    // "single" drops the list parameter, "playlist" keeps it. Single is the
    // default so a shared playlist link never silently grabs the whole list.
    property bool playlistScope: false
    property string title: ""
    property string filename: ""
    property string message: ""
    property real progress: 0
    property real downloaded: 0
    property real total: 0
    property real speed: 0
    property int eta: 0
    property int itemIndex: 0
    property int itemCount: 0
    property int completedCount: 0
    property string state: "idle"
    property string clipboardText: ""
    property bool clipboardBusy: false
    property var history: []
    property var requestQueue: []
    property string thumbnail: ""
    property var completedItems: ({})
    property bool cancelRequested: false
    property bool historyRestored: false
    readonly property int queueCount: requestQueue.length
    readonly property bool running: process.running

    signal downloadRequested(string requestUrl, string requestFormat, int queuedCount)

    onHistoryChanged: persistHistory()

    function reset() {
        title = "";
        filename = "";
        message = "";
        progress = 0;
        downloaded = 0;
        total = 0;
        speed = 0;
        eta = 0;
        thumbnail = "";
        completedItems = ({});
        itemIndex = 0;
        itemCount = 0;
        completedCount = 0;
        state = "idle";
    }

    function normalizeFormat(value) {
        var requested = String(value === undefined || value === null ? "" : value).trim().toLowerCase();
        return formats.indexOf(requested) >= 0 ? requested : defaultFormat;
    }

    function resolveScope(scope) {
        if (scope === "single" || scope === "playlist")
            return scope;
        return root.playlistScope ? "playlist" : "single";
    }

    // Validates a YouTube/YouTube Music link and returns the resolved request,
    // or null when the link cannot be downloaded. Nothing is spawned for an
    // invalid link, so the failure is reported before yt-dlp ever runs.
    function resolveRequest(rawUrl, scope) {
        return YtdUrl.resolve(String(rawUrl || "").trim(), root.resolveScope(scope));
    }

    function isValidUrl(rawUrl) {
        return YtdUrl.isValid(String(rawUrl || "").trim());
    }

    function rejectRequest(rawUrl, reason) {
        url = String(rawUrl || "").trim();
        title = "";
        filename = "";
        progress = 0;
        downloaded = 0;
        total = 0;
        speed = 0;
        eta = 0;
        thumbnail = "";
        itemIndex = 0;
        itemCount = 0;
        state = "error";
        message = reason === "playlist_required"
            ? YtdI18n.t("playlist_required") : YtdI18n.t("invalid_url");
    }

    function normalizeHistoryItems(value) {
        return YtdHistory.normalize(value, formats, defaultFormat, historyLimit);
    }

    function persistHistory() {
        if (historyRestored && StateService.initialized)
            StateService.set(historyStateKey, normalizeHistoryItems(history));
    }

    function restoreHistory() {
        if (!StateService.initialized || historyRestored)
            return;
        historyRestored = true;
        history = normalizeHistoryItems(StateService.get(historyStateKey, []));
    }

    function clearHistory() {
        history = [];
    }

    function removeHistoryItem(itemId) {
        var key = String(itemId || "");
        history = normalizeHistoryItems(history.filter(function(item) {
            return (item.itemId || item.filename || item.url) !== key;
        }));
    }

    function addHistoryItem(source) {
        if (!source || typeof source !== "object")
            return;

        var item = {
            itemId: String(source.item_id || source.itemId || ""),
            title: String(source.title || root.title),
            url: String(source.url || root.url),
            filename: String(source.filename || source.filepath || root.filename),
            format: normalizeFormat(source.format || root.mediaFormat),
            thumbnail: String(source.thumbnail || root.thumbnail),
            finishedAt: Date.now()
        };
        var key = item.itemId || item.filename || item.url;
        if (item.title === "" || key === "" || completedItems[key])
            return;

        completedItems[key] = true;
        history = normalizeHistoryItems([item].concat(history));
    }

    function cancel() {
        if (!process.running)
            return;
        cancelRequested = true;
        state = "cancelled";
        message = YtdI18n.t("download_stopped");
        process.signal(15);
        cancelWatchdog.restart();
    }

    function requestDownload(nextUrl, nextFormat, nextScope) {
        var trimmed = String(nextUrl || "").trim();
        if (trimmed === "")
            return false;

        var scope = root.resolveScope(nextScope);
        var resolved = root.resolveRequest(trimmed, scope);
        if (!resolved.valid) {
            root.rejectRequest(trimmed, resolved.reason);
            downloadRequested(trimmed, root.normalizeFormat(nextFormat), 0);
            return false;
        }

        var request = {
            url: resolved.url,
            format: root.normalizeFormat(nextFormat),
            scope: resolved.scope
        };
        if (!process.running) {
            downloadRequested(request.url, request.format, 0);
            return root.start(request.url, request.format, request.scope);
        }

        if (requestQueue.length >= maxQueuedRequests) {
            console.warn("YTD: request queue is full", requestQueue.length);
            return false;
        }

        requestQueue = requestQueue.concat([request]);
        message = YtdI18n.t("queue_count").replace("%1", requestQueue.length);
        downloadRequested(request.url, request.format, requestQueue.length);
        return true;
    }

    function startNextRequest() {
        if (process.running || requestQueue.length === 0)
            return false;
        var next = requestQueue[0];
        requestQueue = requestQueue.slice(1);
        return start(next.url, next.format, next.scope);
    }

    function start(nextUrl, nextFormat, nextScope) {
        var trimmed = String(nextUrl || "").trim();
        if (trimmed === "" || process.running)
            return false;

        var scope = root.resolveScope(nextScope);
        var resolved = root.resolveRequest(trimmed, scope);
        if (!resolved.valid) {
            root.rejectRequest(trimmed, resolved.reason);
            return false;
        }

        reset();
        url = resolved.url;
        mediaFormat = normalizeFormat(nextFormat);
        cancelRequested = false;
        state = "starting";
        process.command = ["python3", root.helperPath, resolved.url, mediaFormat, resolved.scope];
        process.running = true;
        return true;
    }

    function formatBytes(value) {
        var bytes = Number(value || 0);
        if (bytes < 1024)
            return Math.round(bytes) + " B";
        var units = ["KB", "MB", "GB"];
        var index = -1;
        do { bytes /= 1024; index++; } while (bytes >= 1024 && index < units.length - 1);
        return bytes.toFixed(bytes >= 100 ? 0 : 1) + " " + units[index];
    }

    function formatSpeed(value) {
        return value > 0 ? formatBytes(value) + "/s" : "--";
    }

    function readClipboard() {
        if (clipboardProcess.running)
            return;
        clipboardText = "";
        clipboardBusy = true;
        clipboardProcess.running = true;
    }

    Process {
        id: clipboardProcess
        command: ["wl-paste", "--no-newline"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.clipboardText = text.trim();
                root.clipboardBusy = false;
            }
        }
        onExited: root.clipboardBusy = false
    }

    Process {
        id: process
        running: false
        stdout: SplitParser {
            onRead: function(line) {
                try {
                    var event = JSON.parse(line);
                    if (event.event === "error") {
                        root.state = "error";
                        root.message = String(event.message || YtdI18n.t("download_failed"));
                    } else if (event.event === "complete") {
                        var items = Array.isArray(event.items) ? event.items : [];
                        for (var i = 0; i < items.length; i++)
                            root.addHistoryItem(items[i]);
                        if (items.length === 0)
                            root.addHistoryItem(event);

                        root.progress = 100;
                        root.state = "complete";
                        root.title = String(event.title || root.title);
                        root.filename = String(event.filename || root.filename);
                        root.thumbnail = String(event.thumbnail || root.thumbnail);
                        root.itemIndex = items.length > 0 ? items.length : root.itemIndex;
                        root.itemCount = Number(event.count || items.length || root.completedCount);
                        root.completedCount = Math.max(root.completedCount, root.itemCount);
                        root.message = root.itemCount > 1
                            ? YtdI18n.t("downloaded_count").replace("%1", root.itemCount)
                            : YtdI18n.t("download_complete");
                    } else {
                        root.state = "downloading";
                        root.title = String(event.title || root.title);
                        root.filename = String(event.filename || root.filename);
                        root.thumbnail = String(event.thumbnail || root.thumbnail);
                        root.itemIndex = Number(event.index || root.itemIndex);
                        root.itemCount = Math.max(root.itemCount, Number(event.count || 0));
                        root.downloaded = Number(event.downloaded || 0);
                        root.total = Number(event.total || 0);
                        root.progress = Math.max(0, Math.min(100, Number(event.percent || 0)));
                        root.speed = Number(event.speed || 0);
                        root.eta = Number(event.eta || 0);
                        if (event.event === "finished")
                            root.completedCount += 1;
                    }
                } catch (error) {
                    console.warn("YTD: invalid helper output", line);
                }
            }
        }
        stderr: SplitParser {
            onRead: function(line) {
                console.warn("YTD:", line);
            }
        }
        onExited: function(code) {
            cancelWatchdog.stop();
            var wasCancelled = root.cancelRequested;
            root.cancelRequested = false;
            if (!wasCancelled && code !== 0 && root.state !== "error") {
                root.state = "error";
                root.message = YtdI18n.t("downloader") + " exited with code " + code;
            }
            if (root.requestQueue.length > 0)
                Qt.callLater(function() { root.startNextRequest(); });
        }
    }

    Connections {
        target: StateService
        function onInitializedChanged() {
            root.restoreHistory();
        }
    }

    Component.onCompleted: root.restoreHistory()

    // A helper that ignores SIGTERM is escalated to a hard kill after a moment.
    Timer {
        id: cancelWatchdog
        interval: 3000
        repeat: false
        onTriggered: {
            if (process.running)
                process.running = false;
        }
    }
}