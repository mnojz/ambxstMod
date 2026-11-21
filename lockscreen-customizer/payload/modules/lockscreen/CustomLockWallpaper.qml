pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import qs.config
import "LockscreenPlacement.js" as Placement

Item {
    id: root

    required property bool playing
    property bool miniature: false
    property url poster
    property var settings: Config.customLockscreen
    readonly property bool isVideo: settings.wallpaperMode === "video"
    readonly property var images: settings.wallpaperImages
    readonly property string videoUrl: isVideo ? Placement.localUrl(settings.wallpaperVideo) : ""
    readonly property bool gif: videoUrl.toLowerCase().endsWith(".gif")
    readonly property bool playMotion: playing && videoUrl !== ""
    readonly property bool motionReady: animated.status === Image.Ready || (videoLoader.item?.hasFrame ?? false)
    readonly property bool ready: still.status === Image.Ready || motionReady
    property int imageIndex: 0

    clip: true

    Image {
        id: still
        anchors.fill: parent
        source: root.isVideo ? (!root.motionReady ? root.poster : "") : Placement.localUrl(root.settings.wallpaperMode === "slideshow"
            ? root.images[root.imageIndex % Math.max(1, root.images.length)] : root.settings.wallpaperImage)
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(Math.max(1, width * Screen.devicePixelRatio), Math.max(1, height * Screen.devicePixelRatio))
    }

    Timer {
        interval: Math.max(5, Math.min(3600, root.settings.wallpaperInterval)) * 1000
        running: root.playing && !root.miniature && root.settings.wallpaperMode === "slideshow" && root.images.length > 1
        repeat: true
        onTriggered: root.imageIndex = (root.imageIndex + 1) % root.images.length
    }

    AnimatedImage {
        id: animated
        anchors.fill: parent
        source: root.gif && root.playMotion ? root.videoUrl : ""
        playing: root.playMotion
        cache: false
        fillMode: Image.PreserveAspectCrop
    }

    Loader {
        id: videoLoader
        anchors.fill: parent
        active: root.playMotion && !root.gif
        sourceComponent: Item {
            id: playback
            readonly property bool hasFrame: player.hasVideo && output.sourceRect.width > 0
                                             && player.mediaStatus !== MediaPlayer.InvalidMedia

            function playSource() {
                player.stop();
                player.source = root.videoUrl;
                if (root.videoUrl)
                    player.play();
            }

            Component.onCompleted: playSource()

            Connections {
                target: root
                function onVideoUrlChanged() {
                    playback.playSource();
                }
            }

            VideoOutput {
                id: output
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop
            }

            MediaPlayer {
                id: player
                videoOutput: output
                loops: MediaPlayer.Infinite
                activeAudioTrack: -1
            }
        }
    }
}
