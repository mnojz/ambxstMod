pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import qs.config

Scope {
    id: cache

    readonly property string source: Config.customLockscreen.wallpaperMode === "video"
        ? Config.customLockscreen.wallpaperVideo : ""
    readonly property string home: Quickshell.env("HOME")
    readonly property string library: (Quickshell.env("XDG_DATA_HOME") || home + "/.local/share")
        + "/ambxst/lockscreen-wallpapers"
    readonly property string cacheDirectory: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache")
        + "/ambxst/lockscreen-video"
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("../../scripts/lockscreen_wallpapers.py").toString().replace(/^file:\/\//, ""))
    readonly property int outputHeight: Math.max(0, ...Quickshell.screens.map(screen =>
        Math.min(screen.width, screen.height) * screen.devicePixelRatio))
    readonly property bool reduceForBlur: Config.customLockscreen.wallpaperBlur >= 50
    readonly property size dimensions: reduceForBlur || outputHeight <= 1080 ? Qt.size(1920, 1080)
        : outputHeight <= 1440 ? Qt.size(2560, 1440) : Qt.size(3840, 2160)
    readonly property string request: source ? JSON.stringify([source, dimensions.width, dimensions.height]) : ""
    readonly property url poster: prepared.url === source ? prepared.thumbnail || "" : ""
    readonly property url playback: prepared.url === source ? prepared.playback || "" : ""
    property string runningRequest: ""
    property var prepared: ({})
    property Item activeOutput
    readonly property bool primed: !activeOutput && preroll.sourceRect.width > 0
        && player.playbackState === MediaPlayer.PausedState
    readonly property string playableSource: source && !source.toLowerCase().endsWith(".gif")
        && request === runningRequest && !process.running && prepared.url === source
        ? playback.toString() || source : ""

    function prepare() {
        if (!request || process.running || runningRequest === request)
            return;
        runningRequest = request;
        prepared = { url: source, thumbnail: poster.toString() };
        process.command = ["python3", helper, "--prepare-video", source, "--playback",
            cacheDirectory, String(dimensions.width), String(dimensions.height), library, library];
        process.running = true;
    }

    onRequestChanged: prepareTimer.restart()
    onPlayableSourceChanged: warmupTimer.restart()
    Component.onCompleted: prepareTimer.start()

    function warm() {
        if (activeOutput || player.source.toString() === playableSource)
            return;
        player.stop();
        player.source = playableSource;
        if (playableSource) {
            player.play();
            prerollTimeout.restart();
        }
    }

    function acquire(output, url) {
        if (activeOutput || !playableSource || source !== url)
            return false;
        warm();
        prerollTimeout.stop();
        activeOutput = output;
        player.play();
        return true;
    }

    function release(output) {
        if (activeOutput !== output)
            return;
        player.pause();
        activeOutput = null;
        warmupTimer.restart();
    }

    Timer {
        id: warmupTimer
        interval: 1
        onTriggered: cache.warm()
    }

    Timer {
        id: prerollTimeout
        interval: 6500
        onTriggered: {
            if (!cache.activeOutput)
                player.pause();
        }
    }

    VideoOutput {
        id: preroll
        onSourceRectChanged: {
            if (sourceRect.width > 0 && !cache.activeOutput) {
                prerollTimeout.stop();
                player.pause();
            }
        }
    }

    MediaPlayer {
        id: player
        videoOutput: cache.activeOutput ?? preroll
        loops: MediaPlayer.Infinite
        activeAudioTrack: -1
    }

    Timer {
        id: prepareTimer
        interval: 100
        onTriggered: cache.prepare()
    }

    Process {
        id: process
        stdout: SplitParser {
            onRead: line => {
                try {
                    const result = JSON.parse(line);
                    if (cache.runningRequest === cache.request && result.url === cache.source)
                        cache.prepared = Object.assign({}, cache.prepared, result);
                } catch (error) {
                    console.warn("Could not read the lock screen video cache result:", error);
                }
            }
        }
        onExited: prepareTimer.restart()
    }
}
