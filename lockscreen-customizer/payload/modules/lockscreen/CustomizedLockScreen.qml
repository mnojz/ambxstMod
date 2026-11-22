pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.modules.globals
import qs.modules.theme
import qs.config

WlSessionLockSurface {
    id: root

    property bool authenticating: false
    property string errorMessage: ""
    property int failLockSecondsLeft: 0

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
            username: usernameCollector.text.trim()

            onHasCustomBackgroundChanged: {
                if (hasCustomBackground && entryDelay.running)
                    root.showLockscreen();
            }

            onPasswordSubmitted: password => {
                if (root.authenticating)
                    return;
                authPasswordHolder.password = password;
                root.authenticating = true;
                root.errorMessage = "";
                pamAuth.start();
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

    // Processes for user info
    Process {

        command: ["whoami"]
        running: true

        stdout: StdioCollector {
            id: usernameCollector
            waitForEnd: true
        }
    }

    Process {

        command: ["hostname"]
        running: true

        stdout: StdioCollector {

            waitForEnd: true
        }
    }

    // Holder temporal para la contraseña durante autenticación
    QtObject {
        id: authPasswordHolder
        property string password: ""
    }

    // Proceso para verificar tiempo de faillock
    Process {

        command: ["bash", "-c", `faillock --user '${usernameCollector.text.trim().replace(/'/g, "'\\''")}' 2>/dev/null | grep -oP 'left \\K[0-9]+' | head -1`]
        running: false

        stdout: StdioCollector {


            onStreamFinished: {
                const output = text.trim();
                const seconds = parseInt(output);

                if (!isNaN(seconds) && seconds > 0) {
                    failLockSecondsLeft = seconds;
                    failLockCountdown.start();
                } else {
                    failLockSecondsLeft = 0;
                }
            }
        }
    }

    // Timer para actualizar el countdown de faillock
    Timer {
        id: failLockCountdown
        interval: 1000
        repeat: true
        running: false

        onTriggered: {
            if (failLockSecondsLeft > 0) {
                failLockSecondsLeft--;
            } else {
                stop();
                errorMessage = "";
            }
        }
    }

    // PAM authentication process
    PamContext {
        id: pamAuth
        // Use custom PAM config for lockscreen authentication
        configDirectory: Qt.resolvedUrl("../../config/pam").toString().replace("file://", "")
        config: "password.conf"

        onPamMessage: {
            console.log("PAM Message:", this.message, "Type:", this.messageType, "Required:", this.responseRequired);
            if (this.responseRequired) {
                // pam_unix asks for password, respond with stored password
                this.respond(authPasswordHolder.password);
            }
        }

        onCompleted: result => {
            // Limpiar contraseña
            authPasswordHolder.password = "";

            if (result === PamResult.Success) {
                errorMessage = "";
                slide.leave();
            } else {
                // Error de autenticación
                errorMessage = "Authentication failed";
                console.warn("PAM auth failed with result:", result);
                scene.rejectPassword();
            }
        }
    }

    Component.onCompleted: entryDelay.start()
}
