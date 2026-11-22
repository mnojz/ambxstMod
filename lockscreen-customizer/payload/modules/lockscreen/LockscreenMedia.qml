pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Widgets
import Quickshell.Services.Mpris
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.modules.widgets.dashboard.widgets
import qs.modules.globals
import qs.config

Item {
    id: lockPlayer

    required property var settings
    readonly property real designWidth: coverLayout ? 400 : ribbonLayout ? 370 : outlineLayout ? 330 : 350
    width: designWidth * renderScale

    readonly property bool artworkBackground: settings.mediaArtwork
    property bool sample: false
    readonly property bool compact: visualStyle === "compact"
    property real renderScale: 1
    readonly property string visualStyle: settings.mediaStyle
    readonly property bool nowPlayingLayout: visualStyle === "pane"
    readonly property bool coverLayout: visualStyle === "cover"
    readonly property bool ribbonLayout: visualStyle === "ribbon"
    readonly property bool outlineLayout: visualStyle === "outline"
    readonly property bool hasFrontArtwork: !ribbonLayout && !outlineLayout
    readonly property real designHeight: coverLayout ? 142 : nowPlayingLayout ? 112 : ribbonLayout ? 66 : compact ? 76 : 96
    readonly property real thumbnailRatio: settings.mediaThumbnailRatio >= 0
        ? Math.max(20, Math.min(100, settings.mediaThumbnailRatio)) / 100
        : (coverLayout ? 104 : compact ? 44 : 64) / (designHeight - 32)
    readonly property real frontArtSize: (designHeight - 32) * thumbnailRatio
    readonly property url artworkSource: MprisController.activePlayer?.trackArtUrl || wallpaperPath

    function px(value) {
        return value * renderScale;
    }
    property bool isPlaying: MprisController.activePlayer?.playbackState === MprisPlaybackState.Playing
    readonly property real position: MprisController.activePlayer?.position ?? 0.0
    readonly property real length: MprisController.activePlayer?.length ?? 1.0
    property string wallpaperPath: {
        if (!GlobalStates.wallpaperManager) return "";
        let path = GlobalStates.wallpaperManager.currentWallpaper;
        let frame = GlobalStates.wallpaperManager.getLockscreenFramePath(path);
        return frame ? "file://" + frame : "";
    }

    visible: sample || MprisController.activePlayer !== null
    height: designHeight * renderScale
    readonly property real radius: settings.mediaRadius >= 0 ? Math.min(height / 2, px(settings.mediaRadius))
        : outlineLayout || coverLayout ? px(14) : (height / 2) * (Config.roundness / 16)
    LockscreenWidgetShadow {
        active: lockPlayer.settings.mediaShadow === true
        foreground: foreground
        renderScale: lockPlayer.renderScale
    }

    Item {
        id: foreground
        anchors.fill: parent

        StyledRect {
            anchors.fill: parent
            visible: !lockPlayer.outlineLayout
            variant: lockPlayer.visualStyle === "bg" ? "bg" : "pane"
            radius: lockPlayer.radius
            animateRadius: false
            backgroundOpacity: lockPlayer.artworkBackground && lockPlayerBgArt.status === Image.Ready ? 0 : 1
        }

        Rectangle {
            anchors.fill: parent
            visible: lockPlayer.outlineLayout
            radius: lockPlayer.radius
            color: "transparent"
            border.color: Colors.primary
            border.width: lockPlayer.px(1)
            antialiasing: true
        }

        ClippingRectangle {
            visible: lockPlayer.artworkBackground
            anchors.fill: parent
            radius: lockPlayer.radius
            color: "transparent"

            Image {
                mipmap: true
                id: lockPlayerBgArt
                readonly property int targetPixels: 64 * Math.max(1, Math.ceil(Math.max(width, height) * (Screen.devicePixelRatio || 1) / 64))
                sourceSize: Qt.size(targetPixels, targetPixels)
                anchors.fill: parent
                source: !lockPlayer.artworkBackground ? "" : lockPlayer.artworkSource
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                retainWhileLoading: true
                visible: false
            }

            MultiEffect {
                anchors.fill: parent
                source: lockPlayerBgArt
                // Only enable blur when there's content to blur (saves GPU)
                blurEnabled: visible
                blurMax: 32
                blur: 0.75
                opacity: lockPlayerBgArt.status === Image.Ready ? 1 : 0
                Behavior on opacity {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                }
            }

            StyledRect {
                anchors.fill: parent
                variant: "internalbg"
                opacity: lockPlayerBgArt.status === Image.Ready ? 0.5 : 0
                radius: lockPlayer.radius
            }
        }

        Timer {
            running: !lockPlayer.sample && lockPlayer.isPlaying && lockPlayer.visible
            interval: 1000
            repeat: true
            onTriggered: MprisController.activePlayer?.positionChanged()
        }

        RowLayout {
            id: contentLayout
            enabled: !lockPlayer.sample
            anchors.fill: parent
            anchors.margins: lockPlayer.px(16)
            anchors.rightMargin: lockPlayer.px(28)
            spacing: lockPlayer.px(16)

            // Album artwork with playback control
            Item {
                visible: lockPlayer.hasFrontArtwork
                Layout.preferredWidth: lockPlayer.px(lockPlayer.frontArtSize)
                Layout.preferredHeight: lockPlayer.px(lockPlayer.frontArtSize)
                Layout.alignment: Qt.AlignVCenter

                ClippingRectangle {
                    id: artworkContainer
                    anchors.fill: parent
                    radius: lockPlayer.settings.mediaThumbnailRadius >= 0
                        ? Math.min(height / 2, lockPlayer.px(lockPlayer.settings.mediaThumbnailRadius))
                        : lockPlayer.coverLayout || lockPlayer.nowPlayingLayout ? lockPlayer.px(12)
                        : (height / 2) * (Config.roundness / 16)
                    color: Colors.surfaceContainerHighest
                    clip: true
                    antialiasing: true

                    Image {
                        mipmap: true
                        id: albumArt
                        readonly property int targetPixels: 32 * Math.max(1, Math.ceil(width * (Screen.devicePixelRatio || 1) / 32))
                        sourceSize: Qt.size(targetPixels, targetPixels)
                        anchors.fill: parent
                        source: lockPlayer.artworkSource
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                        retainWhileLoading: true
                    }

                    Text {
                        renderType: Text.NativeRendering
                        anchors.centerIn: parent
                        visible: albumArt.status !== Image.Ready
                        text: Icons.play
                        font.family: Icons.font
                        font.pixelSize: Math.max(1, Math.round(lockPlayer.px(24)))
                        color: Colors.primaryFixed
                    }

                    StyledRect {
                        anchors.fill: parent
                        variant: "internalbg"
                        opacity: playPauseHover.hovered ? 0.5 : 0.0

                        Behavior on opacity {
                            enabled: Config.animDuration > 0
                            NumberAnimation {
                                duration: Config.animDuration
                                easing.type: Easing.OutQuart
                            }
                        }
                    }
                }

                // Playback control over the album artwork
                Text {
                    renderType: Text.NativeRendering
                    anchors.centerIn: parent
                    text: lockPlayer.isPlaying ? Icons.pause : Icons.play
                    textFormat: Text.PlainText
                    color: Styling.srItem("overprimary")
                    font.pixelSize: Math.max(1, Math.round(lockPlayer.px(24)))
                    font.family: Icons.font
                    opacity: playPauseHover.hovered ? 1.0 : 0.0
                    visible: MprisController.canTogglePlaying

                    Behavior on opacity {
                        enabled: Config.animDuration > 0
                        NumberAnimation {
                            duration: Config.animDuration / 2
                            easing.type: Easing.OutQuart
                        }
                    }
                }

                HoverHandler {
                    id: playPauseHover
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    enabled: MprisController.canTogglePlaying
                    onClicked: MprisController.togglePlaying()
                }
            }

            // Track information and controls
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: lockPlayer.px(4)

                // Title and artist
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        visible: lockPlayer.nowPlayingLayout
                        Layout.fillWidth: true
                        text: "NOW PLAYING"
                        color: Colors.primaryFixed
                        font.family: Config.theme.font
                        font.pixelSize: Math.max(1, Math.round(lockPlayer.px(10)))
                        font.weight: Font.DemiBold
                        renderType: Text.NativeRendering
                        elide: Text.ElideRight
                    }

                    Text {
                        renderType: Text.NativeRendering
                        Layout.fillWidth: true
                        text: MprisController.activePlayer?.trackTitle ?? "Track title"
                        textFormat: Text.PlainText
                        color: Colors.overBackground
                        font.pixelSize: Math.max(1, Math.round(lockPlayer.px(Config.theme.fontSize)))
                        font.weight: Font.Bold
                        font.family: Config.theme.font
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                        maximumLineCount: 1
                    }

                    Text {
                        renderType: Text.NativeRendering
                        Layout.fillWidth: true
                        text: MprisController.activePlayer?.trackArtist ?? (lockPlayer.sample ? "Artist" : "")
                        textFormat: Text.PlainText
                        color: Colors.overBackground
                        font.pixelSize: Math.max(1, Math.round(lockPlayer.px(Config.theme.fontSize)))
                        font.family: Config.theme.font
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                        maximumLineCount: 1
                        visible: !lockPlayer.compact && !lockPlayer.ribbonLayout && text !== ""
                        opacity: 0.7
                    }
                }

                // Controls
                RowLayout {
                    Layout.fillWidth: true
                    spacing: lockPlayer.px(8)

                    Text {
                        visible: !lockPlayer.hasFrontArtwork
                        text: lockPlayer.isPlaying ? Icons.pause : Icons.play
                        font.family: Icons.font
                        font.pixelSize: Math.max(1, Math.round(lockPlayer.px(21)))
                        color: Colors.primaryFixed
                        renderType: Text.NativeRendering

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: MprisController.canTogglePlaying
                            onClicked: MprisController.togglePlaying()
                        }
                    }

                    Text {
                        renderType: Text.NativeRendering
                        id: previousBtn
                        text: Icons.previous
                        textFormat: Text.PlainText
                        color: previousHover.hovered ? Styling.srItem("overprimary") : Colors.overBackground
                        font.pixelSize: Math.max(1, Math.round(lockPlayer.px(20)))
                        font.family: Icons.font
                        opacity: MprisController.canGoPrevious ? 1.0 : 0.3

                        Behavior on color {
                            enabled: Config.animDuration > 0
                            ColorAnimation {
                                duration: Config.animDuration
                                easing.type: Easing.OutQuart
                            }
                        }

                        HoverHandler {
                            id: previousHover
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: MprisController.canGoPrevious
                            onClicked: MprisController.previous()
                        }
                    }

                    Basic.Slider {
                        id: seek
                        Layout.fillWidth: true
                        Layout.preferredHeight: lockPlayer.px(22)
                        Accessible.name: "Playback position"
                        padding: 0
                        enabled: MprisController.activePlayer?.canSeek ?? false

                        Binding on value {
                            when: !seek.pressed
                            value: lockPlayer.sample && !MprisController.activePlayer ? 0.42
                                : lockPlayer.length > 0 ? Math.min(1, lockPlayer.position / lockPlayer.length) : 0
                            restoreMode: Binding.RestoreNone
                        }

                        onMoved: {
                            const player = MprisController.activePlayer;
                            if (player?.canSeek)
                                player.position = value * lockPlayer.length;
                        }

                        background: Rectangle {
                            y: (seek.height - height) / 2
                            width: seek.width
                            height: lockPlayer.px(4)
                            radius: height / 2
                            antialiasing: true
                            color: Colors.surfaceBright

                            Rectangle {
                                width: parent.width * seek.visualPosition
                                height: parent.height
                                radius: height / 2
                                antialiasing: true
                                color: Colors.primary
                            }
                        }

                        handle: Rectangle {
                            x: (seek.width - width) * seek.visualPosition
                            y: (seek.height - height) / 2
                            width: lockPlayer.px(9)
                            height: width
                            radius: width / 2
                            antialiasing: true
                            visible: seek.enabled && (seek.hovered || seek.pressed || seek.visualFocus)
                            color: Colors.primary
                        }
                    }

                    Text {
                        renderType: Text.NativeRendering
                        id: nextBtn
                        text: Icons.next
                        textFormat: Text.PlainText
                        color: nextHover.hovered ? Styling.srItem("overprimary") : Colors.overBackground
                        font.pixelSize: Math.max(1, Math.round(lockPlayer.px(20)))
                        font.family: Icons.font
                        opacity: MprisController.canGoNext ? 1.0 : 0.3

                        Behavior on color {
                            enabled: Config.animDuration > 0
                            ColorAnimation {
                                duration: Config.animDuration
                                easing.type: Easing.OutQuart
                            }
                        }

                        HoverHandler {
                            id: nextHover
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: MprisController.canGoNext
                            onClicked: MprisController.next()
                        }
                    }

                    Text {
                        renderType: Text.NativeRendering
                        id: modeBtn
                        visible: !lockPlayer.compact && !lockPlayer.ribbonLayout
                        text: {
                            if (MprisController.hasShuffle)
                                return Icons.shuffle;
                            switch (MprisController.loopState) {
                            case MprisLoopState.Track:
                                return Icons.repeatOnce;
                            case MprisLoopState.Playlist:
                                return Icons.repeat;
                            default:
                                return Icons.shuffle;
                            }
                        }
                        textFormat: Text.PlainText
                        color: modeHover.hovered ? Styling.srItem("overprimary") : Colors.overBackground
                        font.pixelSize: Math.max(1, Math.round(lockPlayer.px(20)))
                        font.family: Icons.font
                        opacity: {
                            if (!(MprisController.shuffleSupported || MprisController.loopSupported))
                                return 0.3;
                            if (!MprisController.hasShuffle && MprisController.loopState === MprisLoopState.None)
                                return 0.3;
                            return 1.0;
                        }

                        Behavior on color {
                            enabled: Config.animDuration > 0
                            ColorAnimation {
                                duration: Config.animDuration
                                easing.type: Easing.OutQuart
                            }
                        }

                        HoverHandler {
                            id: modeHover
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: MprisController.shuffleSupported || MprisController.loopSupported
                            onClicked: {
                                if (MprisController.hasShuffle) {
                                    MprisController.setShuffle(false);
                                    MprisController.setLoopState(MprisLoopState.Playlist);
                                } else if (MprisController.loopState === MprisLoopState.Playlist) {
                                    MprisController.setLoopState(MprisLoopState.Track);
                                } else if (MprisController.loopState === MprisLoopState.Track) {
                                    MprisController.setLoopState(MprisLoopState.None);
                                } else {
                                    MprisController.setShuffle(true);
                                }
                            }
                        }
                    }

                    Text {
                        renderType: Text.NativeRendering
                        id: playerIcon
                        text: {
                            if (!MprisController.activePlayer)
                                return Icons.player;
                            const dbusName = (MprisController.activePlayer.dbusName || "").toLowerCase();
                            const desktopEntry = (MprisController.activePlayer.desktopEntry || "").toLowerCase();
                            const identity = (MprisController.activePlayer.identity || "").toLowerCase();

                            if (dbusName.includes("spotify") || desktopEntry.includes("spotify") || identity.includes("spotify"))
                                return Icons.spotify;
                            if (dbusName.includes("chromium") || dbusName.includes("chrome") || desktopEntry.includes("chromium") || desktopEntry.includes("chrome"))
                                return Icons.chromium;
                            if (dbusName.includes("firefox") || desktopEntry.includes("firefox"))
                                return Icons.firefox;
                            if (dbusName.includes("telegram") || desktopEntry.includes("telegram") || identity.includes("telegram"))
                                return Icons.telegram;
                            return Icons.player;
                        }
                        textFormat: Text.PlainText
                        color: playerIconHover.hovered ? Styling.srItem("overprimary") : Colors.overBackground
                        font.pixelSize: Math.max(1, Math.round(lockPlayer.px(20)))
                        font.family: Icons.font
                        opacity: MprisController.activePlayer ? 1.0 : 0.3

                        Behavior on color {
                            enabled: Config.animDuration > 0
                            ColorAnimation {
                                duration: Config.animDuration
                                easing.type: Easing.OutQuart
                            }
                        }

                        HoverHandler {
                            id: playerIconHover
                        }

                        Timer {
                            id: pressAndHoldTimer
                            interval: 1000
                            repeat: false
                            onTriggered: {
                                playersMenu.updateMenuItems();
                                playersMenu.popup(playerIcon);
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onPressed: mouse => {
                                if (mouse.button === Qt.LeftButton) {
                                    pressAndHoldTimer.start();
                                }
                            }
                            onReleased: {
                                pressAndHoldTimer.stop();
                            }
                            onClicked: mouse => {
                                if (mouse.button === Qt.LeftButton) {
                                    MprisController.cyclePlayer(1);
                                } else if (mouse.button === Qt.RightButton) {
                                    playersMenu.updateMenuItems();
                                    playersMenu.popup(playerIcon);
                                }
                            }
                        }

                        OptionsMenu {
                            id: playersMenu

                            function getPlayerIcon(player) {
                                if (!player)
                                    return Icons.player;
                                const dbusName = (player.dbusName || "").toLowerCase();
                                const desktopEntry = (player.desktopEntry || "").toLowerCase();
                                const identity = (player.identity || "").toLowerCase();

                                if (dbusName.includes("spotify") || desktopEntry.includes("spotify") || identity.includes("spotify"))
                                    return Icons.spotify;
                                if (dbusName.includes("chromium") || dbusName.includes("chrome") || desktopEntry.includes("chromium") || desktopEntry.includes("chrome"))
                                    return Icons.chromium;
                                if (dbusName.includes("firefox") || desktopEntry.includes("firefox"))
                                    return Icons.firefox;
                                if (dbusName.includes("telegram") || desktopEntry.includes("telegram") || identity.includes("telegram"))
                                    return Icons.telegram;
                                return Icons.player;
                            }

                            function updateMenuItems() {
                                const players = MprisController.filteredPlayers;
                                const menuItems = [];

                                for (let i = 0; i < players.length; i++) {
                                    const player = players[i];
                                    const isActive = player === MprisController.activePlayer;

                                    menuItems.push({
                                        text: player.trackTitle || player.identity || "Unknown Player",
                                        icon: getPlayerIcon(player),
                                        highlightColor: Styling.srItem("overprimary"),
                                        textColor: Colors.overPrimary,
                                        onTriggered: () => {
                                            MprisController.setActivePlayer(player);
                                            playersMenu.close();
                                        }
                                    });
                                }

                                playersMenu.items = menuItems;
                            }
                        }
                    }
                }
            }
        }
    }
}
