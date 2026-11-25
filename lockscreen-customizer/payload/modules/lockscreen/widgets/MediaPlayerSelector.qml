pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.modules.components
import qs.modules.services
import qs.modules.theme

MediaButton {
    id: root

    // The shell's app icons contain trusted font markup. Player metadata stays plain.
    textFormat: Text.RichText
    text: iconFor(MprisController.activePlayer)
    actionable: MprisController.activePlayer !== null
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    enableHold: true

    function iconFor(player) {
        const app = [player?.dbusName, player?.desktopEntry, player?.identity].join(" ").toLowerCase();
        if (app.includes("spotify"))
            return Icons.spotify;
        if (app.includes("chromium") || app.includes("chrome"))
            return Icons.chromium;
        if (app.includes("firefox"))
            return Icons.firefox;
        if (app.includes("telegram"))
            return Icons.telegram;
        return Icons.player;
    }

    function openPlayers() {
        playersMenu.items = MprisController.filteredPlayers.map(player => ({
            text: player.identity || "Media player",
            icon: iconFor(player),
            onTriggered: () => {
                MprisController.setActivePlayer(player);
                playersMenu.close();
            }
        }));
        playersMenu.popup(root);
    }

    onActivated: button => {
        if (button === Qt.LeftButton)
            MprisController.cyclePlayer(1);
        else
            openPlayers();
    }
    onHeld: openPlayers()

    OptionsMenu {
        id: playersMenu
        popupType: Popup.Item
    }
}
