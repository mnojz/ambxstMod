pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.modules.components
import qs.modules.theme

Item {
    id: login

    required property var settings
    property string username: "Enter password"
    property bool authenticating: false
    property bool animate: true
    property bool interactive: true
    property real renderScale: 1

    function px(value) {
        return Math.max(1, Math.round(value * renderScale));
    }
    signal submitted(string password)
    signal rejectionFinished()

    readonly property real designWidth: 350
    width: designWidth * renderScale
    readonly property bool profileLayout: settings.loginStyle === "pane"
    readonly property bool portraitAbove: profileLayout && settings.loginAvatar
    readonly property bool minimalBackground: profileLayout || settings.loginStyle === "plain"
    readonly property real designHeight: portraitAbove ? 188 : settings.loginAvatar ? 96 : 72
    height: designHeight * renderScale

    function focusPassword() {
        passwordInput.forceActiveFocus();
    }

    function rejectPassword() {
        if (Config.animDuration > 0)
            wrongPasswordAnim.start();
        else
            rejectionFinished();
    }

    Item {
        id: passwordInputBox
        anchors.fill: parent

        property real shakeOffset: 0
        property bool showError: false

        transform: Translate {
            x: passwordInputBox.shakeOffset
        }

        StyledRect {
            anchors.fill: parent
            visible: !login.minimalBackground
            variant: "bg"
            radius: Config.roundness > 0 ? (height / 2) * (Config.roundness / 16) : 0
        }

        Item {
            anchors.fill: parent
            anchors.leftMargin: login.px(16)
            anchors.rightMargin: login.px(login.profileLayout ? 16 : 24)
            ClippingRectangle {
                id: avatarContainer
                visible: login.settings.loginAvatar
                width: login.px(login.portraitAbove ? 112 : 64)
                height: width
                x: login.portraitAbove ? (parent.width - width) / 2 : 0
                y: login.portraitAbove ? login.px(4) : (parent.height - height) / 2
                radius: Config.roundness > 0 ? (height / 2) * (Config.roundness / 16) : 0
                color: "transparent"
                clip: true
                antialiasing: true

                Image {
                    mipmap: true
                    id: userAvatar
                    anchors.fill: parent
                    source: login.settings.loginAvatar ? `file://${Quickshell.env("HOME")}/.face.icon` : ""
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    asynchronous: true
                    visible: status === Image.Ready
                }

                // Fallback icon if image not found
                Text {
                    anchors.centerIn: parent
                    text: Icons.user
                    font.family: Icons.font
                    font.pixelSize: login.px(login.portraitAbove ? 48 : 32)
                    color: Colors.overSurface
                    visible: userAvatar.status !== Image.Ready
                }
            }

            // Password field
            StyledRect {
                id: passwordFieldBg
                width: parent.width - x
                height: login.px(48)
                x: !login.portraitAbove && login.settings.loginAvatar ? avatarContainer.width + login.px(12) : 0
                y: login.portraitAbove ? avatarContainer.y + avatarContainer.height + login.px(16) : (parent.height - height) / 2
                variant: passwordInputBox.showError ? "error" : "common"
                radius: Config.roundness > 0 ? (height / 2) * (Config.roundness / 16) : 0

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: login.px(16)
                    anchors.rightMargin: login.px(32)
                    spacing: login.px(8)

                    // User icon / Spinner
                    Text {
                        id: userIcon
                        text: login.authenticating ? Icons.circleNotch : Icons.user
                        font.family: Icons.font
                        font.pixelSize: login.px(24)
                        color: passwordFieldBg.item
                        Layout.preferredWidth: login.px(24)
                        Layout.preferredHeight: login.px(24)
                        Layout.alignment: Qt.AlignVCenter
                        z: 10
                        rotation: 0

                        Behavior on color {
                            enabled: login.animate && Config.animDuration > 0
                            ColorAnimation {
                                duration: Config.animDuration
                                easing.type: Easing.OutCubic
                            }
                        }

                        Timer {
                            id: spinnerTimer
                            interval: 100
                            repeat: true
                            running: login.authenticating
                            onTriggered: {
                                userIcon.rotation = (userIcon.rotation + 45) % 360;
                            }
                        }

                        onTextChanged: {
                            if (userIcon.text === Icons.user) {
                                userIcon.rotation = 0;
                            }
                        }
                    }

                    // Text field
                    TextField {
                        id: passwordInput
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        placeholderText: login.username
                        placeholderTextColor: Qt.rgba(passwordFieldBg.item.r, passwordFieldBg.item.g, passwordFieldBg.item.b, 0.5)
                        font.family: Config.theme.font
                        font.pixelSize: login.px(Styling.fontSize(0))
                        renderType: TextInput.CurveRendering
                        color: passwordFieldBg.item
                        background: null
                        echoMode: TextInput.Password
                        inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                        verticalAlignment: TextInput.AlignVCenter
                        enabled: !login.authenticating && login.interactive

                        Behavior on color {
                            enabled: login.animate && Config.animDuration > 0
                            ColorAnimation {
                                duration: Config.animDuration
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on placeholderTextColor {
                            enabled: login.animate && Config.animDuration > 0
                            ColorAnimation {
                                duration: Config.animDuration
                                easing.type: Easing.OutQuad
                            }
                        }

                        onAccepted: {
                            if (passwordInput.text.trim() === "")
                                return;

                            const password = passwordInput.text;
                            passwordInput.clear();
                            login.submitted(password);
                        }
                    }
                }
            }
        }

        SequentialAnimation {
            id: wrongPasswordAnim
            ScriptAction {
                script: {
                    passwordInputBox.showError = true;
                }
            }
            NumberAnimation {
                target: passwordInputBox
                property: "shakeOffset"
                to: 10
                duration: 50
                easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                target: passwordInputBox
                property: "shakeOffset"
                to: -10
                duration: 100
                easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                target: passwordInputBox
                property: "shakeOffset"
                to: 10
                duration: 100
                easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                target: passwordInputBox
                property: "shakeOffset"
                to: 0
                duration: 50
                easing.type: Easing.InOutQuad
            }
            ScriptAction {
                script: {
                    passwordInput.text = "";
                    login.rejectionFinished();
                    passwordInputBox.showError = false;
                }
            }
        }
    }
}
