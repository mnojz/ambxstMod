pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.modules.theme
import qs.config

// BarPopout: the two forms a bar widget's popout can take, behind one handle.
//
// With "contain bar" off the bar is a row of floating pills, so a popout is a
// pill too — a BarPopup window offset from the bar, exactly as before.
//
// With it on the bar is part of the frame, and a window floating next to it
// reads as a separate object stuck to a solid band. Attached, the popout is
// instead drawn inside UnifiedShellPanel's own surface (see BarFlyout), where it
// shares the frame's fill and flares back into it with concave corners — the
// frame bulging out around the button rather than something sitting on top of
// it. That surface belongs to the shell panel, not to the bar widget, so the
// contents are handed over as a Component and instantiated there.
//
// Either way the widget declares its contents once, as a child of this:
//
//     BarPopout {
//         id: thingPopout
//         anchorItem: buttonBg
//         bar: root.bar
//         popupPadding: 16
//
//         Item {
//             implicitWidth: 220
//             implicitHeight: 132
//             ...
//         }
//     }
//
// The contents must declare their own implicitWidth/implicitHeight — that is
// what both hosts size themselves from — and are laid out at exactly that size.
Item {
    id: root

    // The bar button the popout belongs to; supplies the position it grows from.
    required property Item anchorItem
    // The bar panel, for orientation and screen.
    required property var bar

    // Gap between the popout's edge and its contents.
    property int popupPadding: 8
    // Same, attached. Popouts that draw their own cards edge-to-edge want less
    // than the floating pill gives them.
    property int flyoutPadding: popupPadding
    // StyledRect variant for the floating pill's background. Attached, the fill
    // is always the frame's own, or the seam would show.
    property string variant: "popup"
    // Floating pill only: its distance from the bar, and whether its shadow
    // margins let pointer input through (a drag from the bar has to be able
    // to cross them without breaking its grab). Attached, there is no gap and
    // no margin, so neither means anything.
    property int visualMargin: 8
    property bool clickThroughMargins: false
    // Windows (a nested tray menu, say) that must not clear the floating
    // pill's focus grab while they are open. The attached form has no grab —
    // the panel's backdrop closes it — so nested popups leave it alone anyway.
    property list<var> extraGrabWindows: []
    // A nested popup opened from inside the contents, for hosts that track
    // one (the tray registers its per-icon menus here).
    property var activeChildMenu: null
    // Floating pill only: its mutual-exclusion group (see BarPopup). Attached
    // there is one flyout shell-wide, which is the same thing.
    property string groupId: "bar"
    // False keeps the floating pill whatever the bar settings are: a popout
    // opened from INSIDE another one (a tray icon's menu in the overflow
    // popout) has no flyout to be, the one there is holds its parent.
    property bool allowAttached: true
    property bool separatePanel: false
    readonly property bool usePanel: separatePanel && Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") !== ""
    // The floating pill's window, for a host that lists it as a nested popup
    // (extraGrabWindows wants the window, not this handle).
    readonly property var pillWindow: pill

    // Contents, instantiated by whichever host is in use.
    default property Component content

    // A handle, not a visual — everything it owns is drawn elsewhere.
    width: 0
    height: 0

    readonly property bool vertical: root.bar?.orientation === "vertical"
    readonly property string screenName: root.bar?.screen?.name ?? ""

    // Attached needs a frame to merge into; without one there is nothing to
    // bulge out of and the pill is the only sensible form.
    readonly property bool attached: !root.usePanel && root.allowAttached && (Config.bar?.containBar ?? false) && (Config.bar?.frameEnabled ?? false)

    // Only one flyout exists shell-wide, so ours is open only while it is ours.
    readonly property bool flyoutOpen: GlobalStates.barFlyoutOpen && GlobalStates.barFlyoutOwner === root

    // Logical open state, as BarPopup reports it: set on intent, not when the
    // animation finishes.
    readonly property bool isOpen: root.attached ? root.flyoutOpen : (root.usePanel ? (panelLoader.item?.isOpen ?? false) : pill.isOpen)

    // Corner radius for contents that run edge to edge, so they nest inside the
    // host without the gap pinching at the corners. A rounded child inset by p
    // from a rounded parent of radius R only keeps an even gap all the way round
    // when its own radius is R - p; give it the parent's radius instead and the
    // ring narrows by nearly half diagonally, which reads as a wobbly border.
    // The two hosts round differently, hence the split — see BarFlyout's
    // panelRadius and BarPopup's background.
    readonly property real contentRadius: root.attached ? Math.max(0, Styling.radius(4) - root.flyoutPadding) : Math.max(0, Styling.radius(8) - root.popupPadding)

    // Where the popout should sprout from: the centre of the button along the
    // bar axis, in panel coordinates. Read at click time — mapToItem isn't a
    // bindable dependency, so as a property binding this would silently go stale.
    // Rounded, because this ends up as the panel's own position: a bar widget
    // sized from text metrics has a fractional height, and half a pixel of it
    // lands the whole panel off-grid. Everything drawn inside then rasterises
    // asymmetrically — rounded corners pick up a flat lip at one end and lose
    // their last row at the other.
    function currentAnchor(): real {
        const p = root.anchorItem.mapToItem(null, 0, 0);
        return Math.round(root.vertical ? p.y + root.anchorItem.height / 2 : p.x + root.anchorItem.width / 2);
    }

    function open(): void {
        if (root.attached)
            GlobalStates.openBarFlyout(root, root.content, root.screenName, root.currentAnchor(), root.flyoutPadding);
        else if (root.usePanel)
            panelLoader.item?.open();
        else
            pill.open();
    }

    function close(): void {
        if (root.attached) {
            if (root.flyoutOpen)
                GlobalStates.closeBarFlyout();
        } else if (root.usePanel) {
            panelLoader.item?.close();
        } else {
            pill.close();
        }
    }

    function toggle(): void {
        if (root.isOpen)
            root.close();
        else
            root.open();
    }

    // Re-assert the floating pill's focus grab after a nested popup took it
    // over and closed. Nothing to do attached.
    function refreshFocusGrab(): void {
        if (!root.attached)
            pill.refreshFocusGrab();
    }

    // Toggling "contain bar" swaps which host owns the contents underneath an
    // open popout, which would otherwise leave the abandoned one on screen.
    onAttachedChanged: {
        if (root.flyoutOpen)
            GlobalStates.closeBarFlyout();
        pill.close();
    }

    // Explicitly into `data`: the default property is the contents, so a plain
    // child here would be swallowed as those instead.
    data: [
        BarPopup {
            id: pill
            anchorItem: root.anchorItem
            bar: root.bar
            popupPadding: root.popupPadding
            visualMargin: root.visualMargin
            clickThroughMargins: root.clickThroughMargins
            extraGrabWindows: root.extraGrabWindows
            variant: root.variant
            groupId: root.groupId

            contentWidth: (pillContent.item?.implicitWidth ?? 0) + root.popupPadding * 2
            contentHeight: (pillContent.item?.implicitHeight ?? 0) + root.popupPadding * 2

            Loader {
                id: pillContent
                anchors.fill: parent
                // Attached, the contents belong to BarFlyout instead; two live
                // copies would mean two of everything behind them — two polling
                // timers, two pomodoros.
                active: !root.attached && !root.usePanel
                sourceComponent: root.content
            }
        },
        Loader {
            id: panelLoader
            active: root.usePanel
            sourceComponent: CadencePanelPopup {
                anchorItem: root.anchorItem
                bar: root.bar
                popupContent: root.content
                groupId: root.groupId
                variant: root.variant
                popupPadding: root.popupPadding
                visualMargin: root.visualMargin
            }
        }
    ]
}
