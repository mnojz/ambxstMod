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
import qs.modules.globals
import qs.config
import "../LockscreenCustomization.js" as Customization

Item {
    id: lockPlayer

    required property var settings
    property size frameSize: Qt.size(0, 0)
    readonly property var savedFrame: Customization.read(settings.mediaFrame)
    readonly property bool customFrame: frameSize.width > 0 || Object.keys(savedFrame).length > 0
    readonly property size designFrame: Customization.frameSize(savedFrame, naturalWidth, naturalHeight)
    readonly property real designWidth: designFrame.width
    readonly property real designHeight: designFrame.height
    readonly property var appearance: Customization.read(settings.mediaAppearance)
    opacity: (appearance.opacity ?? 100) / 100
    readonly property var partStyles: Customization.read(settings.mediaPartStyles)
    readonly property var layoutOptions: Customization.read(settings.mediaLayoutOptions)
    readonly property bool preferredArtworkAbove: layoutOptions.artPlacement === "above"
    readonly property bool artworkAbove: preferredArtworkAbove || (customFrame && stacksArtwork(width, height, renderScale))
    readonly property real artworkGap: px(gap)
    readonly property real gap: layoutOptions.gap ?? 16
    readonly property real padding: px(16)
    readonly property real contentWidth: Math.max(1, width - padding * 2)
    readonly property real contentHeight: Math.max(1, height - padding * 2)
    readonly property real metadataHeight: trackInfo.implicitHeight
    readonly property int buttonCount: (showTransport ? playInArtwork ? 2 : 3 : 0) + Number(showMode) + Number(showApp)
    readonly property real buttonWidth: px(buttonCount * 22 + Math.max(0, buttonCount - 1) * 8)
    readonly property real artSide: Math.max(1, Math.min(px(frontArtSize), contentHeight, contentWidth * 0.37,
        contentWidth - artworkGap - Math.max(px(72), buttonWidth)))
    readonly property bool separateProgress: artworkAbove || (customFrame && contentWidth
        - (hasFrontArtwork ? artSide + artworkGap : 0) < buttonWidth + px(34))
    readonly property real minimumContentHeight: (showHeading ? 15 : 0) + (showTitle ? 18 : 0) + (showArtist ? 18 : 0)
        + (buttonCount > 0 ? 26 : 0) + (showProgress ? 24 : 0) + (showTimes ? 18 : 0)
    readonly property int upperArtPercent: settings.mediaThumbnailRatio >= 0
        ? settings.mediaThumbnailRatio : layoutOptions.wideArtwork === false ? 46 : 75
    readonly property real upperArtSide: Math.max(1, Math.min(topArtworkSize(width, renderScale),
        contentHeight - artworkGap - metadataHeight))

    function stacksArtwork(frameWidth, frameHeight, scale) {
        return hasFrontArtwork && (layoutOptions.artPlacement ?? "auto") === "auto"
            && frameWidth < 310 * scale && frameHeight > frameWidth * 0.68;
    }

    function topArtworkSize(frameWidth, scale) {
        return Math.max(1, frameWidth - 32 * scale) * Math.max(0.2, Math.min(1, upperArtPercent / 100));
    }

    function heightForFrame(frameWidth, frameHeight, scale) {
        if (!hasFrontArtwork || (!preferredArtworkAbove && !stacksArtwork(frameWidth, frameHeight, scale)))
            return frameHeight;
        return Math.max(frameHeight, topArtworkSize(frameWidth, scale) + (minimumContentHeight + gap + 40) * scale);
    }
    readonly property bool artworkAfter: layoutOptions.artPlacement === "right"
    readonly property bool showTitle: mediaOption("title", true)
    readonly property bool showArtist: mediaOption("artist", !compact && !ribbonLayout)
    readonly property bool showHeading: mediaOption("heading", nowPlayingLayout)
    readonly property bool showProgress: mediaOption("progress", true)
    readonly property bool showTimes: mediaOption("times", false)
    readonly property bool showTransport: mediaOption("transport", true)
    readonly property bool showMode: mediaOption("mode", !compact && !ribbonLayout)
    readonly property bool showApp: mediaOption("app", true)
    readonly property bool playInArtwork: showTransport && hasFrontArtwork && layoutOptions.playButton !== "controls"
    readonly property int textAlignment: layoutOptions.textAlignment === "center" ? Text.AlignHCenter
        : layoutOptions.textAlignment === "right" ? Text.AlignRight : Text.AlignLeft

    function mediaOption(key, fallback) {
        const value = layoutOptions[key];
        return typeof value === "boolean" ? value : fallback;
    }

    function timestamp(value) {
        const seconds = Math.max(0, Math.floor(value));
        const remainder = String(seconds % 60).padStart(2, "0");
        return Math.floor(seconds / 60) + ":" + remainder;
    }
    readonly property var editableParts: ({ art: artwork, title: trackTitle,
        artist: trackArtist, controls: controls })

    function partColor(key, fallback) {
        return Customization.color(Customization.part(partStyles, key), fallback, Colors);
    }

    component MetadataText: Text {
        id: metadataText
        required property string partKey
        property int defaultWeight: Font.Normal
        readonly property var partStyle: Customization.part(lockPlayer.partStyles, partKey)
        readonly property real partOffsetX: Customization.partOffset(partStyle, "x", lockPlayer.renderScale, metadataText, lockPlayer)
        readonly property real partOffsetY: Customization.partOffset(partStyle, "y", lockPlayer.renderScale, metadataText, lockPlayer)
        transform: Translate { x: metadataText.partOffsetX; y: metadataText.partOffsetY }
        readonly property int pixelSize: Math.max(1, Math.round(lockPlayer.px(Config.theme.fontSize) * Customization.scale(partStyle)))
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.maximumWidth: implicitWidth
        Layout.alignment: lockPlayer.textAlignment === Text.AlignHCenter ? Qt.AlignHCenter
            : lockPlayer.textAlignment === Text.AlignRight ? Qt.AlignRight : Qt.AlignLeft
        textFormat: Text.PlainText
        color: Customization.color(partStyle, Colors.overBackground, Colors)
        font.pixelSize: pixelSize
        font.weight: partStyle.weight ?? defaultWeight
        font.family: partStyle.font || Config.theme.font
        font.letterSpacing: pixelSize * (partStyle.spacing ?? 0) / 100
        elide: Text.ElideRight
        renderType: Text.NativeRendering
    }
    readonly property real naturalWidth: coverLayout ? 400 : ribbonLayout ? 370 : outlineLayout ? 330 : 350
    width: frameSize.width || designWidth * renderScale

    readonly property bool stockBackground: appearance.fill !== "solid" && appearance.fill !== "none"
    readonly property bool artworkBackground: visible && stockBackground && settings.mediaArtwork
    property bool sample: false
    readonly property bool compact: visualStyle === "compact"
    property real renderScale: 1
    readonly property string visualStyle: settings.mediaStyle
    readonly property bool nowPlayingLayout: visualStyle === "pane"
    readonly property bool coverLayout: visualStyle === "cover"
    readonly property bool ribbonLayout: visualStyle === "ribbon"
    readonly property bool outlineLayout: visualStyle === "outline"
    readonly property bool hasFrontArtwork: mediaOption("artwork", !ribbonLayout && !outlineLayout)
    readonly property real baseHeight: coverLayout ? 142 : nowPlayingLayout ? 112 : ribbonLayout ? 66 : compact ? 76 : 96
    readonly property real naturalHeight: heightForFrame(naturalWidth,
        Math.max(baseHeight + (showTimes ? 18 : 0),
            32 + minimumContentHeight - (showProgress && !preferredArtworkAbove && buttonCount > 0 ? 24 : 0)), 1)
    readonly property real thumbnailRatio: settings.mediaThumbnailRatio >= 0
        ? Math.max(20, Math.min(100, settings.mediaThumbnailRatio)) / 100
        : Math.min(1, (coverLayout ? 104 : compact ? 44 : 64) / (baseHeight - 32))
    readonly property real frontArtSize: (baseHeight - 32)
        * Math.min(1, thumbnailRatio * Customization.scale(Customization.part(partStyles, "art")))
    readonly property url artworkSource: MprisController.activePlayer?.trackArtUrl || wallpaperPath

    function px(value) {
        return value * renderScale;
    }
    readonly property bool isPlaying: MprisController.activePlayer?.playbackState === MprisPlaybackState.Playing
    readonly property real position: MprisController.activePlayer?.position ?? 0.0
    readonly property real length: MprisController.activePlayer?.length ?? 1.0
    readonly property string wallpaperPath: {
        const manager = GlobalStates.wallpaperManager;
        const frame = manager?.getLockscreenFramePath(manager.currentWallpaper);
        return frame ? "file://" + frame : "";
    }

    function cyclePlaybackMode() {
        const choices = [{ shuffle: false, loop: MprisLoopState.None }];
        if (MprisController.shuffleSupported)
            choices.push({ shuffle: true, loop: MprisLoopState.None });
        if (MprisController.loopSupported)
            choices.push({ shuffle: false, loop: MprisLoopState.Playlist }, { shuffle: false, loop: MprisLoopState.Track });
        const current = choices.findIndex(mode => mode.shuffle === MprisController.hasShuffle
            && (mode.shuffle || mode.loop === MprisController.loopState));
        const next = choices[(current + 1) % choices.length];
        if (next.shuffle !== MprisController.hasShuffle)
            MprisController.setShuffle(next.shuffle);
        if (next.loop !== MprisController.loopState)
            MprisController.setLoopState(next.loop);
    }

    visible: sample || MprisController.activePlayer !== null
    height: frameSize.height || designHeight * renderScale
    readonly property real radius: Number.isFinite(appearance.radius) ? Math.min(width / 2, height / 2, px(appearance.radius))
        : settings.mediaRadius >= 0 ? Math.min(width / 2, height / 2, px(settings.mediaRadius))
        : outlineLayout || coverLayout ? px(14) : Math.min(width, height, px(baseHeight)) / 2 * (Config.roundness / 16)
    WidgetAppearance {
        widget: lockPlayer
        style: lockPlayer.appearance
        renderScale: lockPlayer.renderScale
    }

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
            visible: lockPlayer.stockBackground && !lockPlayer.outlineLayout
            variant: lockPlayer.visualStyle === "bg" ? "bg" : "pane"
            radius: lockPlayer.radius
            animateRadius: false
            backgroundOpacity: lockPlayer.artworkBackground && lockPlayerBgArt.status === Image.Ready ? 0 : 1
        }

        Rectangle {
            anchors.fill: parent
            visible: lockPlayer.stockBackground && lockPlayer.outlineLayout
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
                visible: opacity > 0
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
            running: !lockPlayer.sample && lockPlayer.isPlaying && lockPlayer.visible && (lockPlayer.showTimes || lockPlayer.showProgress)
            interval: 1000
            repeat: true
            onTriggered: MprisController.activePlayer?.positionChanged()
        }

        Basic.Slider {
            id: seek
            Layout.minimumWidth: lockPlayer.px(20)
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
                    color: lockPlayer.partColor("controls", Colors.primary)
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
                color: lockPlayer.partColor("controls", Colors.primary)
            }
        }

        GridLayout {
            enabled: !lockPlayer.sample
            anchors.fill: parent
            anchors.margins: lockPlayer.padding
            columns: lockPlayer.hasFrontArtwork && !lockPlayer.artworkAbove ? 2 : 1
            columnSpacing: lockPlayer.artworkGap
            rowSpacing: columnSpacing

            Item {
                id: artwork
                readonly property var partStyle: Customization.part(lockPlayer.partStyles, "art")
                readonly property real partOffsetX: Customization.partOffset(partStyle, "x", lockPlayer.renderScale, artwork, lockPlayer)
                readonly property real partOffsetY: Customization.partOffset(partStyle, "y", lockPlayer.renderScale, artwork, lockPlayer)
                transform: Translate { x: artwork.partOffsetX; y: artwork.partOffsetY }
                visible: lockPlayer.hasFrontArtwork
                Layout.row: 0
                Layout.column: !lockPlayer.artworkAbove && lockPlayer.artworkAfter ? 1 : 0
                Layout.preferredWidth: lockPlayer.artworkAbove ? lockPlayer.upperArtSide : lockPlayer.artSide
                Layout.preferredHeight: Layout.preferredWidth
                Layout.alignment: lockPlayer.artworkAbove ? Qt.AlignHCenter : Qt.AlignVCenter

                ClippingRectangle {
                    anchors.fill: parent
                    readonly property real artworkRadius: lockPlayer.settings.mediaThumbnailRadius >= 0
                        ? lockPlayer.px(lockPlayer.settings.mediaThumbnailRadius)
                        : lockPlayer.coverLayout || lockPlayer.nowPlayingLayout ? lockPlayer.px(12)
                        : (height / 2) * (Config.roundness / 16)
                    radius: Math.min(width / 2, height / 2, artworkRadius)
                    color: lockPlayer.partColor("art", Colors.surfaceContainerHighest)
                    contentUnderBorder: true
                    border.color: lockPlayer.partColor("art", "transparent")
                    border.width: Customization.part(lockPlayer.partStyles, "art").color ? lockPlayer.px(2) : 0
                    clip: true
                    antialiasing: true

                    Image {
                        mipmap: true
                        id: albumArt
                        readonly property int targetPixels: 32 * Math.max(1, Math.ceil(Math.max(width, height) * (Screen.devicePixelRatio || 1) / 32))
                        sourceSize: Qt.size(targetPixels, targetPixels)
                        anchors.fill: parent
                        source: lockPlayer.visible && lockPlayer.hasFrontArtwork ? lockPlayer.artworkSource : ""
                        fillMode: lockPlayer.layoutOptions.fitArtwork ? Image.PreserveAspectFit : Image.PreserveAspectCrop
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
                    visible: lockPlayer.playInArtwork && MprisController.canTogglePlaying

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
                    enabled: lockPlayer.playInArtwork
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    enabled: lockPlayer.playInArtwork && MprisController.canTogglePlaying
                    onClicked: MprisController.togglePlaying()
                }
            }

            // Track information and controls
            ColumnLayout {
                id: trackInfo
                Layout.row: lockPlayer.artworkAbove && lockPlayer.hasFrontArtwork ? 1 : 0
                Layout.column: lockPlayer.hasFrontArtwork && !lockPlayer.artworkAbove && !lockPlayer.artworkAfter ? 1 : 0
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: lockPlayer.px(4)

                // Title and artist
                ColumnLayout {
                    visible: lockPlayer.showHeading || lockPlayer.showTitle || (lockPlayer.showArtist && trackArtist.text !== "")
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        visible: lockPlayer.showHeading
                        Layout.fillWidth: true
                        horizontalAlignment: lockPlayer.textAlignment
                        text: "NOW PLAYING"
                        color: Colors.primaryFixed
                        font.family: Config.theme.font
                        font.pixelSize: Math.max(1, Math.round(lockPlayer.px(10)))
                        font.weight: Font.DemiBold
                        renderType: Text.NativeRendering
                        elide: Text.ElideRight
                    }

                    MetadataText {
                        id: trackTitle
                        visible: lockPlayer.showTitle
                        partKey: "title"
                        defaultWeight: Font.Bold
                        text: MprisController.activePlayer?.trackTitle ?? "Track title"
                    }

                    MetadataText {
                        id: trackArtist
                        partKey: "artist"
                        text: MprisController.activePlayer?.trackArtist ?? (lockPlayer.sample ? "Artist" : "")
                        visible: lockPlayer.showArtist && text !== ""
                        opacity: 0.7
                    }
                }

                ColumnLayout {
                    id: controls
                    readonly property var partStyle: Customization.part(lockPlayer.partStyles, "controls")
                    readonly property real partOffsetX: Customization.partOffset(partStyle, "x", lockPlayer.renderScale, controls, lockPlayer)
                    readonly property real partOffsetY: Customization.partOffset(partStyle, "y", lockPlayer.renderScale, controls, lockPlayer)
                    transform: Translate { x: controls.partOffsetX; y: controls.partOffsetY }
                    visible: lockPlayer.showProgress || lockPlayer.showTransport || lockPlayer.showMode || lockPlayer.showApp || lockPlayer.showTimes
                    Layout.fillWidth: true
                    spacing: lockPlayer.px(2)

                    RowLayout {
                        Layout.fillWidth: lockPlayer.showProgress && !lockPlayer.separateProgress
                        Layout.alignment: lockPlayer.artworkAbove ? Qt.AlignHCenter : Qt.AlignLeft
                        visible: (lockPlayer.showProgress && !lockPlayer.separateProgress) || lockPlayer.showTransport
                            || lockPlayer.showMode || lockPlayer.showApp
                        spacing: lockPlayer.px(8)

                        MediaButton {
                            visible: lockPlayer.showTransport && !lockPlayer.playInArtwork
                            renderScale: lockPlayer.renderScale
                            text: lockPlayer.isPlaying ? Icons.pause : Icons.play
                            idleColor: lockPlayer.partColor("controls", Colors.primaryFixed)
                            actionable: MprisController.canTogglePlaying
                            onActivated: MprisController.togglePlaying()
                        }

                        MediaButton {
                            renderScale: lockPlayer.renderScale
                            idleColor: lockPlayer.partColor("controls", Colors.overBackground)
                            visible: lockPlayer.showTransport
                            text: Icons.previous
                            actionable: MprisController.canGoPrevious
                            onActivated: MprisController.previous()
                        }

                        LayoutItemProxy {
                            target: seek
                            visible: lockPlayer.showProgress && !lockPlayer.separateProgress
                            Layout.fillWidth: true
                            Layout.minimumWidth: lockPlayer.px(20)
                        }

                        MediaButton {
                            renderScale: lockPlayer.renderScale
                            idleColor: lockPlayer.partColor("controls", Colors.overBackground)
                            visible: lockPlayer.showTransport
                            text: Icons.next
                            actionable: MprisController.canGoNext
                            onActivated: MprisController.next()
                        }

                        MediaButton {
                            visible: lockPlayer.showMode
                            renderScale: lockPlayer.renderScale
                            actionable: MprisController.shuffleSupported || MprisController.loopSupported
                            idleColor: lockPlayer.partColor("controls", Colors.overBackground)
                            opacity: actionable && (MprisController.hasShuffle || MprisController.loopState !== MprisLoopState.None) ? 1 : 0.3
                            text: {
                                if (MprisController.hasShuffle)
                                    return Icons.shuffle;
                                switch (MprisController.loopState) {
                                case MprisLoopState.Track: return Icons.repeatOnce;
                                case MprisLoopState.Playlist: return Icons.repeat;
                                default: return Icons.shuffle;
                                }
                            }
                            onActivated: lockPlayer.cyclePlaybackMode()
                        }

                        MediaPlayerSelector {
                            visible: lockPlayer.showApp
                            renderScale: lockPlayer.renderScale
                            idleColor: lockPlayer.partColor("controls", Colors.overBackground)
                        }
                    }

                    LayoutItemProxy {
                        target: seek
                        visible: lockPlayer.showProgress && lockPlayer.separateProgress
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        visible: lockPlayer.showTimes
                        Layout.fillWidth: true

                        Text {
                            Layout.fillWidth: true
                            text: lockPlayer.timestamp(lockPlayer.sample && !MprisController.activePlayer ? 90 : lockPlayer.position)
                            color: lockPlayer.partColor("controls", Colors.overBackground)
                            font.pixelSize: Math.max(1, Math.round(lockPlayer.px(Config.theme.fontSize - 2)))
                            renderType: Text.NativeRendering
                        }

                        Text {
                            text: lockPlayer.timestamp(lockPlayer.sample && !MprisController.activePlayer ? 214 : lockPlayer.length)
                            color: lockPlayer.partColor("controls", Colors.overBackground)
                            font.pixelSize: Math.max(1, Math.round(lockPlayer.px(Config.theme.fontSize - 2)))
                            renderType: Text.NativeRendering
                        }
                    }
                }
            }
        }
    }
}
