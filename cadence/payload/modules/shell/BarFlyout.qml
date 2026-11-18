pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import qs.modules.components
import qs.modules.corners
import qs.modules.theme
import qs.modules.globals
import qs.config

// Generic frame-attached bar popout.
//
// Same construction as BluetoothFlyout: drawn inside UnifiedShellPanel with the
// frame's own "bg" fill plus concave fillets, so it reads as the frame bulging
// out around the button instead of a window floating beside it. The difference
// is that this one carries no content of its own — the bar widget that opens it
// hands its contents over as a Component (through GlobalStates) and this
// instantiates them. One instance per screen, one flyout open shell-wide.
//
// Only used while "contain bar" is on. With it off there is no frame to merge
// into, so BarPopout falls back to the floating BarPopup pill instead.
Item {
    id: root

    required property ShellScreen targetScreen
    // Thickness of the frame band on the bar's side. The panel starts at its
    // inner edge so the two fills touch with no seam.
    required property int frameInset
    required property string barPosition

    // Handed to UnifiedShellPanel's input mask.
    property alias hitbox: unionArea

    readonly property bool active: GlobalStates.barFlyoutOpen && GlobalStates.barFlyoutScreenName === root.targetScreen.name

    readonly property bool barAtLeft: barPosition === "left"
    readonly property bool barAtRight: barPosition === "right"
    readonly property bool barAtTop: barPosition === "top"
    readonly property bool barAtBottom: barPosition === "bottom"
    readonly property bool barVertical: barAtLeft || barAtRight

    // Concave corners that flare the panel back into the frame, and the rounding
    // on the far side. Matched to the frame's own inner radius.
    readonly property int filletSize: Styling.radius(4)
    readonly property int panelRadius: Styling.radius(4)
    readonly property int fillet: filletSize

    // Collapsed, the panel is the size of the bar button it grows out of.
    readonly property int buttonSize: 36
    readonly property int contentPadding: GlobalStates.barFlyoutPadding

    // Natural size of whatever the owning widget handed over. Read off the
    // loaded item rather than declared here, so every widget keeps sizing its
    // popout the way it always did.
    readonly property int rawContentWidth: contentLoader.item?.implicitWidth ?? 0
    readonly property int rawContentHeight: contentLoader.item?.implicitHeight ?? 0

    // How far the panel may reach away from the bar, and how far it may run
    // along it. The along-axis limit leaves room for both flares.
    readonly property int maxAcross: Math.max(120, (barVertical ? root.width : root.height) - frameInset - 24)
    readonly property int maxAlong: Math.max(120, (barVertical ? root.height : root.width) - endMargin * 2)

    readonly property int wantWidth: rawContentWidth + contentPadding * 2
    readonly property int wantHeight: rawContentHeight + contentPadding * 2

    readonly property int openWidth: Math.min(wantWidth, barVertical ? maxAcross : maxAlong)
    readonly property int openHeight: Math.min(wantHeight, barVertical ? maxAlong : maxAcross)

    // Collapses along the axis it grows out of, keeping the button's size on the
    // other, so it looks like it retracts into the button.
    readonly property int shutWidth: barVertical ? 0 : buttonSize
    readonly property int shutHeight: barVertical ? buttonSize : 0

    property real panelW: active ? openWidth : shutWidth
    property real panelH: active ? openHeight : shutHeight

    // The notch's signature: overshoot on the way out, settle on the way back in.
    // This also carries size changes when one widget's flyout replaces another's,
    // so switching buttons morphs rather than cuts.
    Behavior on panelW {
        enabled: Config.animDuration > 0
        NumberAnimation {
            duration: Config.animDuration
            easing.type: root.active ? Easing.OutBack : Easing.OutQuart
            easing.overshoot: root.active ? 1.2 : 1.0
        }
    }

    Behavior on panelH {
        enabled: Config.animDuration > 0
        NumberAnimation {
            duration: Config.animDuration
            easing.type: root.active ? Easing.OutBack : Easing.OutQuart
            easing.overshoot: root.active ? 1.2 : 1.0
        }
    }

    // How far the panel keeps from the END of the bar. The frame has a band
    // and a rounded inner corner there, and the panel flares back into the
    // frame with a fillet of its own: closer than band + corner + fillet and
    // the two curves run into each other (a tall popout on a vertical bar's
    // last button used to end 28 px from the screen edge, on top of the
    // corner). A little air on top of that, so they read as two shapes.
    readonly property int endBand: (Config.bar?.frameEnabled ?? false) ? (Config.bar?.frameThickness ?? 6) : 0
    readonly property int endMargin: Math.max(fillet + 40, endBand + Styling.radius(4) + fillet + 12)

    // Centred on the button the way the floating pill is, then clamped so the
    // panel can't run off the end of the bar.
    readonly property real anchorPos: {
        const extent = barVertical ? panelH : panelW;
        const along = barVertical ? root.height : root.width;
        const raw = GlobalStates.barFlyoutAnchor - extent / 2;
        // Margin along the bar's own axis — frameInset is the thickness of the
        // perpendicular band and means nothing in this direction.
        const margin = root.endMargin;
        // Whole pixels: `extent / 2` is fractional for any odd-sized panel, and
        // an off-grid panel rasterises its contents' rounded corners unevenly.
        return Math.round(Math.max(margin, Math.min(raw, Math.max(margin, along - margin - extent))));
    }

    readonly property real panelX: {
        if (barAtLeft)
            return frameInset;
        if (barAtRight)
            return root.width - frameInset - panelW;
        return anchorPos;
    }

    readonly property real panelY: {
        if (barAtTop)
            return frameInset;
        if (barAtBottom)
            return root.height - frameInset - panelH;
        return anchorPos;
    }

    // Collapsed size is the button's, not zero, so `panelH > 0` can't decide
    // this — hold the item alive for the length of the close animation instead.
    property bool renderVisible: false
    visible: renderVisible

    onActiveChanged: {
        if (active) {
            hideTimer.stop();
            renderVisible = true;
        } else {
            hideTimer.restart();
        }
    }

    Timer {
        id: hideTimer
        interval: Config.animDuration > 0 ? Config.animDuration + 60 : 60
        onTriggered: root.renderVisible = false
    }

    // Union of the panel and its two fillets — everything the mask carves from.
    Item {
        id: unionArea

        x: root.barVertical ? root.panelX : root.panelX - root.fillet
        y: root.barVertical ? root.panelY - root.fillet : root.panelY
        width: root.panelW + (root.barVertical ? 0 : root.fillet * 2)
        height: root.panelH + (root.barVertical ? root.fillet * 2 : 0)

        // Local origin of the panel rect inside the union.
        readonly property real px: root.barVertical ? 0 : root.fillet
        readonly property real py: root.barVertical ? root.fillet : 0

        // The flares hug the edge the panel is attached along, which is the far
        // edge for a right or bottom bar rather than the near one.
        readonly property real flareCross: {
            if (root.barVertical)
                return root.barAtLeft ? 0 : root.panelW - root.fillet;
            return root.barAtTop ? 0 : root.panelH - root.fillet;
        }
        // Along the bar's axis: the leading flare sits before the panel, the
        // trailing one just past its far end.
        readonly property real trailAlong: root.barVertical ? py + root.panelH : px + root.panelW

        // Swallows clicks so they don't fall through to the panel's
        // close-on-click-outside backdrop.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onWheel: wheel => wheel.accepted = true
        }

        // Literally continuous with the frame, so it takes the same Background
        // variant — anything else would show a seam where they meet. The
        // silhouette comes from the mask (square against the frame, flared
        // corners), so no radius here: a rounded StyledRect underneath would
        // fight it.
        StyledRect {
            id: panelFill
            anchors.fill: parent
            variant: "bg"
            radius: 0
            enableBorder: false
            enableShadow: false

            layer.enabled: true
            layer.smooth: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: panelMask
                maskThresholdMin: 0.5
                maskThresholdMax: 1.0
                maskSpreadAtMin: 1.0
            }
        }

        // Silhouette: panel body plus the two concave flares back into the frame.
        Item {
            id: panelMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            layer.smooth: true

            Rectangle {
                x: unionArea.px
                y: unionArea.py
                width: root.panelW
                height: root.panelH
                color: "white"

                // The edge meeting the frame stays square so the two fills merge.
                topLeftRadius: (root.barAtRight || root.barAtBottom) ? root.panelRadius : 0
                topRightRadius: (root.barAtLeft || root.barAtBottom) ? root.panelRadius : 0
                bottomLeftRadius: (root.barAtRight || root.barAtTop) ? root.panelRadius : 0
                bottomRightRadius: (root.barAtLeft || root.barAtTop) ? root.panelRadius : 0
            }

            // Leading flare (above the panel for a vertical bar, left of it otherwise)
            RoundCorner {
                x: root.barVertical ? unionArea.flareCross : 0
                y: root.barVertical ? 0 : unionArea.flareCross
                // Size is held constant rather than animated or toggled with
                // `visible`: RoundCorner paints through a Canvas, and both of
                // those leave it stale — blank after a live bar-position change
                // until a shell restart.
                size: root.filletSize
                width: root.filletSize
                height: root.filletSize
                color: "white"
                corner: {
                    if (root.barAtLeft)
                        return RoundCorner.CornerEnum.BottomLeft;
                    if (root.barAtRight)
                        return RoundCorner.CornerEnum.BottomRight;
                    if (root.barAtTop)
                        return RoundCorner.CornerEnum.TopRight;
                    return RoundCorner.CornerEnum.BottomRight;
                }
            }

            // Trailing flare (below the panel for a vertical bar, right of it otherwise)
            RoundCorner {
                x: root.barVertical ? unionArea.flareCross : unionArea.trailAlong
                y: root.barVertical ? unionArea.trailAlong : unionArea.flareCross
                size: root.filletSize
                width: root.filletSize
                height: root.filletSize
                color: "white"
                corner: {
                    if (root.barAtLeft)
                        return RoundCorner.CornerEnum.TopLeft;
                    if (root.barAtRight)
                        return RoundCorner.CornerEnum.TopRight;
                    if (root.barAtTop)
                        return RoundCorner.CornerEnum.TopLeft;
                    return RoundCorner.CornerEnum.BottomLeft;
                }
            }
        }

        // ── Contents ───────────────────────────────────────────────────────
        // Mirrors NotchAnimationBehavior so they settle like the notch's views.
        Item {
            id: contentRoot

            x: unionArea.px
            y: unionArea.py
            width: root.panelW
            height: root.panelH
            clip: true

            scale: root.active ? 1.0 : 0.8
            opacity: root.active ? 1.0 : 0.0
            visible: opacity > 0

            Behavior on scale {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.2
                }
            }

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: Easing.OutQuart
                }
            }

            // Only scrolls when the content genuinely doesn't fit — the clamp
            // above is the only thing that ever makes that happen, so on a
            // normal screen this is an inert wrapper.
            Flickable {
                anchors.fill: parent
                anchors.margins: root.contentPadding
                clip: true
                contentWidth: Math.max(width, root.rawContentWidth)
                contentHeight: Math.max(height, root.rawContentHeight)
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height || contentWidth > width

                Loader {
                    id: contentLoader
                    // Kept alive through the close animation, so the panel still
                    // has something to draw while it retracts.
                    active: root.active || root.renderVisible
                    sourceComponent: GlobalStates.barFlyoutContent
                    // Pinned to the natural size rather than the animating one,
                    // so text doesn't reflow (and the size doesn't thrash)
                    // mid-expand.
                    width: root.rawContentWidth
                    height: root.rawContentHeight
                }
            }
        }
    }
}
