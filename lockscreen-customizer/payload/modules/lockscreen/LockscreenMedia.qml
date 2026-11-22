pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.widgets.dashboard.widgets

Item {
    id: root

    required property var settings
    property bool sample: false
    property real renderScale: 1

    readonly property real designWidth: player.coverLayout ? 400 : player.ribbonLayout ? 370 : player.outlineLayout ? 330 : 350
    readonly property real designHeight: player.unscaledHeight
    width: designWidth * renderScale
    height: designHeight * renderScale

    LockPlayer {
        id: player
        width: root.width
        renderScale: root.renderScale
        sample: root.sample
        artworkBackground: root.settings.mediaArtwork
        variant: root.settings.mediaStyle === "bg" ? "bg" : "pane"
        compact: root.settings.mediaStyle === "compact"
        visualStyle: root.settings.mediaStyle
    }
}
