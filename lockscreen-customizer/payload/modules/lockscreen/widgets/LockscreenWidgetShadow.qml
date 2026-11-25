import QtQuick
import QtQuick.Effects

Loader {
    id: shadow

    required property Item foreground
    required property real renderScale

    anchors.fill: foreground
    z: -1

    sourceComponent: MultiEffect {
        source: shadow.foreground
        blurEnabled: true
        blur: 0.55
        blurMax: Math.max(4, Math.round(14 * shadow.renderScale))
        colorization: 1
        colorizationColor: "black"
        brightness: -1
        opacity: 0.78
        transform: Translate { y: 4 * shadow.renderScale }
    }
}
