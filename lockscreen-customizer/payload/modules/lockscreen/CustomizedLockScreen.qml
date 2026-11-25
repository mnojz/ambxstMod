pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.modules.globals
import qs.modules.services
import qs.modules.theme
import qs.config

WlSessionLockSurface {
    id: root

    property bool authenticating: false
    property var videoCache
    readonly property bool sleepTransition: SuspendManager.isSuspending || !SuspendManager.wakeReady

    color: Colors.surfaceContainer

    LockscreenSlide {
        id: slide
        anchors.fill: parent
        duration: Config.animDuration > 0 ? Math.max(180, Math.min(600, Config.animDuration * 2)) : 0
        desktopPath: {
            if (root.sleepTransition)
                return "";
            const manager = root.screen ? GlobalStates.wallpaperForScreen(root.screen.name) : GlobalStates.wallpaperManager;
            const path = manager?.effectiveWallpaper || manager?.currentWallpaper || "";
            return manager?.getLockscreenFramePath ? manager.getLockscreenFramePath(path) : path;
        }
        onExited: GlobalStates.lockscreenVisible = false

        LockscreenScene {
            id: scene
            anchors.fill: parent
            screen: root.screen
            authenticating: root.authenticating
            videoCache: root.videoCache
            preparedVideo: root.videoCache?.playback ?? ""
            videoPoster: root.videoCache?.poster ?? ""
            suspending: SuspendManager.isSuspending
            username: Quickshell.env("USER") || "Enter password"

            onHasCustomBackgroundChanged: {
                if (hasCustomBackground && entryDelay.running)
                    root.showLockscreen();
            }

            onPasswordSubmitted: password => {
                if (root.authenticating)
                    return;
                authPasswordHolder.password = password;
                root.authenticating = true;
                if (!pamAuth.start())
                    root.rejectAuthentication();
            }

            onRejectionFinished: root.authenticating = false
        }
    }

    function showLockscreen(immediate = false) {
        entryDelay.stop();
        slide.enter(immediate);
        scene.focusPassword();
    }

    Timer {
        id: entryDelay
        interval: scene.customWallpaper && !scene.hasCustomBackground && slide.duration > 0 ? 280 : 1
        onTriggered: root.showLockscreen()
    }

    Connections {
        target: SuspendManager
        function onPreparingForSleep() { root.showLockscreen(true); }
        function onWakingUp() { root.showLockscreen(true); }
    }

    QtObject {
        id: authPasswordHolder
        property string password: ""
    }

    function rejectAuthentication() {
        if (!authPasswordHolder.password)
            return;
        authPasswordHolder.password = "";
        scene.rejectPassword();
    }

    PamContext {
        id: pamAuth
        configDirectory: Qt.resolvedUrl("../../config/pam").toString().replace("file://", "")
        config: "password.conf"

        onPamMessage: {
            if (responseRequired)
                respond(authPasswordHolder.password);
        }

        onError: error => {
            console.warn("Lock screen PAM error:", error);
            root.rejectAuthentication();
        }

        onCompleted: result => {
            if (result === PamResult.Success) {
                authPasswordHolder.password = "";
                slide.leave();
            } else {
                root.rejectAuthentication();
            }
        }
    }

    Component.onCompleted: {
        if (sleepTransition)
            showLockscreen(true);
        else
            entryDelay.start();
    }
}
