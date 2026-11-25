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
        return value * renderScale;
    }
    signal submitted(string password)
    signal rejectionFinished()

    readonly property real designWidth: 350
    width: designWidth * renderScale
    readonly property bool profileLayout: settings.loginStyle === "pane"
    readonly property bool titleCard: settings.loginStyle === "card"
    readonly property bool lineLayout: settings.loginStyle === "line"
    readonly property bool badgeLayout: settings.loginStyle === "badge"
    readonly property bool portraitAbove: profileLayout && settings.loginAvatar
    readonly property bool minimalBackground: profileLayout || lineLayout || settings.loginStyle === "plain"
    readonly property real designHeight: portraitAbove ? 188 : titleCard ? 112 : lineLayout ? (settings.loginAvatar ? 80 : 62) : settings.loginAvatar ? 96 : 72
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

    LockscreenWidgetShadow {
        active: login.settings.loginShadow === true
        foreground: passwordInputBox
        renderScale: login.renderScale
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
            animateRadius: false
            visible: !login.minimalBackground
            variant: login.titleCard ? "pane" : "bg"
            antialiasing: true
            radius: login.titleCard || login.badgeLayout ? login.px(14) : Config.roundness > 0 ? (height / 2) * (Config.roundness / 16) : 0
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
                x: login.portraitAbove ? (parent.width - width) / 2 : login.badgeLayout ? parent.width - width : 0
                y: login.portraitAbove ? login.px(4) : login.titleCard ? login.px(43) : (parent.height - height) / 2
                radius: Config.roundness > 0 ? (height / 2) * (Config.roundness / 16) : 0
                color: "transparent"
                clip: true
                antialiasing: true

                Image {
                    id: userAvatar
                    mipmap: true
                    anchors.fill: parent
                    readonly property int targetPixels: 32 * Math.max(1, Math.ceil(width * (Screen.devicePixelRatio || 1) * 1.25 / 32))
                    sourceSize: Qt.size(targetPixels, targetPixels)
                    source: login.settings.loginAvatar ? `file://${Quickshell.env("HOME")}/.face.icon` : ""
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    retainWhileLoading: true
                    asynchronous: true
                    visible: status === Image.Ready
                }

                // Fallback icon if image not found
                Text {
                    anchors.centerIn: parent
                    text: Icons.user
                    renderType: Text.NativeRendering
                    font.family: Icons.font
                    font.pixelSize: Math.max(1, Math.round(login.px(login.portraitAbove ? 48 : 32)))
                    color: Colors.overSurface
                    visible: userAvatar.status !== Image.Ready
                }
            }

            Text {
                visible: login.titleCard
                anchors.horizontalCenter: parent.horizontalCenter
                y: login.px(11)
                text: "Sign in"
                font.family: Config.theme.font
                font.pixelSize: Math.max(1, Math.round(login.px(21)))
                font.weight: Font.DemiBold
                color: Colors.primaryFixed
                renderType: Text.NativeRendering
            }

            // Password field
            Item {
                id: passwordFieldBg
                readonly property bool avatarInRow: login.settings.loginAvatar && !login.portraitAbove
                width: parent.width - (avatarInRow ? avatarContainer.width + login.px(12) : 0)
                height: login.px(login.lineLayout ? 42 : 48)
                x: avatarInRow && !login.badgeLayout ? avatarContainer.width + login.px(12) : 0
                y: login.portraitAbove ? avatarContainer.y + avatarContainer.height + login.px(16)
                    : login.titleCard ? login.px(49) : (parent.height - height) / 2
                readonly property color item: fieldSurface.item

                StyledRect {
                    id: fieldSurface
                    anchors.fill: parent
                    antialiasing: true
                    animateRadius: false
                    backgroundOpacity: login.lineLayout && !passwordInputBox.showError ? 0 : -1
                    enableBorder: !login.lineLayout
                    variant: passwordInputBox.showError ? "error" : "common"
                    radius: Config.roundness > 0 ? (height / 2) * (Config.roundness / 16) : 0
                }

                Rectangle {
                    visible: login.lineLayout
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: login.px(2)
                    color: passwordInputBox.showError ? Colors.error : Colors.primary
                    antialiasing: true
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: login.px(16)
                    anchors.rightMargin: login.px(32)
                    spacing: login.px(8)

                    // User icon / Spinner
                    Text {
                        id: userIcon
                        visible: !login.lineLayout || login.authenticating
                        renderType: Text.NativeRendering
                        text: login.authenticating ? Icons.circleNotch : Icons.user
                        font.family: Icons.font
                        font.pixelSize: Math.max(1, Math.round(login.px(24)))
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
                        Layout.fillHeight: true
                        leftPadding: login.px(6)
                        rightPadding: login.px(6)
                        topPadding: 0
                        bottomPadding: 0
                        placeholderText: login.username
                        placeholderTextColor: Qt.rgba(passwordFieldBg.item.r, passwordFieldBg.item.g, passwordFieldBg.item.b, 0.5)
                        font.family: Config.theme.font
                        font.pixelSize: Math.max(1, Math.round(login.px(Styling.fontSize(length || preeditText ? 0 : 1))))
                        renderType: TextInput.NativeRendering
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
                            if (passwordInput.length === 0)
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
