pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.config
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.modules.theme

Item {
    id: root

    required property var bar
    property bool layerEnabled: true
    property real startRadius: 0
    property real endRadius: 0

    readonly property bool vertical: root.bar.orientation === "vertical"
    readonly property bool connected: NetworkService.ethernet || NetworkService.wifiStatus === "connected" || NetworkService.wifiStatus === "limited"
    readonly property string networkIcon: {
        if (NetworkService.ethernet)
            return Icons.ethernet;
        if (!NetworkService.wifiEnabled)
            return Icons.wifiOff;
        if (!root.connected)
            return Icons.wifiNone;
        return NetworkService.wifiIconForStrength(NetworkService.networkStrength);
    }

    onVisibleChanged: {
        if (!visible && networkPopup.isOpen)
            networkPopup.close();
    }

    Component.onDestruction: {
        if (GlobalStates.networkPopupOwner === root)
            GlobalStates.networkPopupOwner = null;
        if (networkPopup.isOpen)
            networkPopup.close();
    }

    StyledRect {
        id: buttonBg
        anchors.fill: parent
        variant: networkPopup.isOpen ? "primary" : "bg"
        enableShadow: root.layerEnabled

        topLeftRadius: root.startRadius
        topRightRadius: root.vertical ? root.startRadius : root.endRadius
        bottomLeftRadius: root.vertical ? root.endRadius : root.startRadius
        bottomRightRadius: root.endRadius

        Rectangle {
            anchors.fill: parent
            color: Styling.srItem("overprimary")
            opacity: !networkPopup.isOpen && hover.hovered ? 0.25 : 0
            radius: buttonBg.radius ?? 0

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation { duration: Config.animDuration / 2 }
            }
        }

        Text {
            anchors.centerIn: parent
            text: root.networkIcon
            font.family: Icons.font
            font.pixelSize: 18
            color: networkPopup.isOpen ? buttonBg.item : (root.connected ? Colors.primary : Colors.overSurfaceVariant)
        }

        HoverHandler { id: hover }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: event => {
                if (event.button === Qt.RightButton) {
                    networkPopup.close();
                    Quickshell.execDetached(["nm-connection-editor"]);
                } else {
                    networkPopup.toggle();
                }
            }
        }

        StyledToolTip {
            show: hover.hovered && !networkPopup.isOpen
            tooltipText: {
                if (NetworkService.ethernet)
                    return "Ethernet connected";
                if (root.connected)
                    return NetworkService.networkName;
                return NetworkService.wifiEnabled ? "Wi-Fi disconnected" : I18n.t("wifi.disabled");
            }
        }
    }

    BarPopout {
        id: networkPopup
        separatePanel: true
        anchorItem: buttonBg
        bar: root.bar
        popupPadding: 8

        onIsOpenChanged: {
            if (isOpen && !networkPopup.usePanel) {
                GlobalStates.networkPopupOwner = root;
            } else if (GlobalStates.networkPopupOwner === root) {
                GlobalStates.networkPopupOwner = null;
            }
        }

        NetworkFlyout {
            opened: networkPopup.isOpen
            maxContentHeight: Math.min(420, Math.max(120, (root.bar.screen?.height ?? 600) - 96))
            onSettingsRequested: {
                networkPopup.close();
                Quickshell.execDetached(["nm-connection-editor"]);
            }
        }
    }
}
