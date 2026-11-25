pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.modules.globals
import qs.modules.theme
import qs.config

WlSessionLockSurface {
    id: root

    property bool authenticating: false

    color: Colors.surfaceContainer

    LockscreenSlide {
        id: slide
        anchors.fill: parent
        duration: Config.animDuration > 0 ? Math.max(180, Math.min(600, Config.animDuration * 2)) : 0
        desktopPath: {
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

    function showLockscreen() {
        entryDelay.stop();
        slide.enter();
        scene.focusPassword();
    }

    Timer {
        id: entryDelay
        interval: scene.customWallpaper && !scene.hasCustomBackground && slide.duration > 0 ? 280 : 1
        onTriggered: root.showLockscreen()
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

    Component.onCompleted: entryDelay.start()
}
