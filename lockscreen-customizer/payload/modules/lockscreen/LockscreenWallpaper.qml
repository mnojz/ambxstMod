pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.components
import qs.modules.globals
import qs.modules.theme
import "LockscreenPlacement.js" as Placement

Item {
    id: root

    required property var settings
    property var screen
    property bool miniature: false
    property real designScale: 1
    property url videoPoster
    property url preparedVideo
    property var videoCache
    property bool playbackEnabled: true

    readonly property var wallpaperManager: screen ? GlobalStates.wallpaperForScreen(screen.name) : GlobalStates.wallpaperManager
    readonly property bool customWallpaper: ["image", "slideshow", "video"].includes(settings.wallpaperMode)
    readonly property bool hasCustomBackground: customLoader.ready
    readonly property bool waitingForVideo: miniature && settings.wallpaperMode === "video"
        && Boolean(settings.wallpaperVideo) && !hasCustomBackground

    Item {
        id: backgroundLayer
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            color: Colors.background
        }
        clip: true
        readonly property real blurAmount: Math.max(0, Math.min(100, root.settings.wallpaperBlur)) / 100
        readonly property real blurSigma: 15 * blurAmount * root.designScale
        // As the blur broadens, the blurred image needs fewer pixels to retain its detail.
        readonly property real textureScale: Math.min(Screen.devicePixelRatio || 1, 8 / Math.max(1, blurSigma))
        readonly property size blurTextureSize: Qt.size(Math.max(1, Math.round(width * textureScale)),
                                                         Math.max(1, Math.round(height * textureScale)))

        layer.enabled: blurSigma > 0 && (!root.customWallpaper || customLoader.ready)
        layer.smooth: true
        layer.textureSize: blurTextureSize
        layer.effect: ShaderEffect {
            property var source
            readonly property vector2d texelStep: Qt.vector2d(0, 1 / backgroundLayer.blurTextureSize.height)
            readonly property real sigma: backgroundLayer.blurSigma * backgroundLayer.blurTextureSize.height / Math.max(1, height)
            fragmentShader: "wallpaper-gaussian.frag.qsb"
        }

        Item {
            anchors.fill: parent
            clip: true
            layer.enabled: backgroundLayer.layer.enabled
            layer.smooth: true
            layer.textureSize: backgroundLayer.blurTextureSize
            layer.effect: ShaderEffect {
                property var source
                readonly property vector2d texelStep: Qt.vector2d(1 / backgroundLayer.blurTextureSize.width, 0)
                readonly property real sigma: backgroundLayer.blurSigma * backgroundLayer.blurTextureSize.width / Math.max(1, width)
                fragmentShader: "wallpaper-gaussian.frag.qsb"
            }

            Loader {
                id: customLoader
                anchors.fill: parent
                z: 2
                active: root.customWallpaper
                readonly property bool ready: item?.ready ?? false

                layer.enabled: ready && root.settings.wallpaperTint
                layer.effect: ShaderEffect {
                    property var paletteTexture: tintPalette
                    property real paletteSize: wallpaperBackground.optimizedPalette.length
                    property real texWidth: customLoader.width
                    property real texHeight: customLoader.height
                    vertexShader: "../widgets/dashboard/wallpapers/palette.vert.qsb"
                    fragmentShader: "../widgets/dashboard/wallpapers/palette.frag.qsb"
                }

                sourceComponent: CustomLockWallpaper {
                    settings: root.settings
                    playing: root.playbackEnabled
                    miniature: root.miniature
                    poster: root.videoPoster
                    preparedVideo: root.preparedVideo
                    videoCache: root.videoCache
                }
            }

            TintedWallpaper {
                id: wallpaperBackground
                anchors.fill: parent
                z: 1
                radius: 0
                tintEnabled: root.settings.wallpaperTint
                source: {
                    if (root.customWallpaper)
                        return "";
                    const manager = root.wallpaperManager;
                    return Placement.fileUrl(manager?.effectiveWallpaper || manager?.currentWallpaper || "");
                }

                onSourceChanged: {
                    if (!root.miniature)
                        root.syncLockscreenVideo();
                }

                visible: !root.customWallpaper

            }

        }
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: Math.max(0, Math.min(100, root.settings.wallpaperDim ?? 0)) / 100
        visible: opacity > 0
    }

    ShaderEffectSource {
        id: tintPalette
        visible: false
        hideSource: true
        smooth: false
        sourceItem: Row {
            Repeater {
                model: customLoader.layer.enabled ? wallpaperBackground.optimizedPalette : []
                delegate: Rectangle {
                    required property string modelData
                    width: 1
                    height: 1
                    color: Colors[modelData]
                }
            }
        }
    }

    function syncLockscreenVideo() {
        if (!wallpaperBackground.isVideo)
            return;
        wallpaperBackground.videoPlayAt(wallpaperManager?.activeVideo?.positionMs ?? 0);
    }

    // Follow the background video while locked (seek to 0 on wallpaper sync)
    Connections {
        target: root.miniature ? null : GlobalStates
        function onVideoSyncTickChanged() {
            if (!wallpaperBackground.isVideo)
                return;
            wallpaperBackground.videoSeek(0);
            wallpaperBackground.videoPlay();
        }
    }

    // Soft drift correction against the background video
    Timer {
        interval: 15000
        running: !root.miniature && wallpaperBackground.isVideo
        repeat: true
        onTriggered: {
            const position = root.wallpaperManager?.activeVideo?.positionMs;
            if (position !== undefined && Math.abs(wallpaperBackground.videoPosition - position) > 1500)
                wallpaperBackground.videoSeek(position);
        }
    }
}
