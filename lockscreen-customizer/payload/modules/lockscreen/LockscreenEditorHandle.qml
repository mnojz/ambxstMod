pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.theme
import "LockscreenPlacement.js" as Placement

Item {
    id: root
    required property Item widget
    required property string title
    required property bool selected
    required property var siblings
    property real guideX: -1
    property real guideY: -1
    property bool toolsAvailable: true
    signal toolsRequested()
    signal select()
    signal done(real x, real y, real width)

    property rect original
    property rect draft
    property bool moving: false
    readonly property real targetWidth: widget.baseWidth * widget.baseScale
    readonly property real targetHeight: widget.baseHeight * widget.baseScale

    x: moving ? draft.x : widget.baseX
    y: moving ? draft.y : widget.baseY
    width: moving ? draft.width : targetWidth
    height: moving ? draft.height : targetHeight

    function begin() {
        original = Qt.rect(widget.baseX, widget.baseY, targetWidth, targetHeight);
        draft = original;
        guideX = -1;
        guideY = -1;
        moving = true;
        select();
    }

    function move(dx, dy) {
        const maximumX = Math.max(0, parent.width - original.width);
        const maximumY = Math.max(0, parent.height - original.height);
        const x = Math.max(0, Math.min(maximumX, original.x + dx));
        const y = Math.max(0, Math.min(maximumY, original.y + dy));
        const snappedX = Placement.snap(x, [0, original.width / 2, original.width],
            Placement.alignmentGuides(parent.width, siblings, true), 0, maximumX);
        const snappedY = Placement.snap(y, [0, original.height / 2, original.height],
            Placement.alignmentGuides(parent.height, siblings, false), 0, maximumY);
        guideX = snappedX.guide;
        guideY = snappedY.guide;
        draft = Qt.rect(snappedX.position, snappedY.position, original.width, original.height);
    }

    function resize(dx, dy, grip) {
        const signX = grip < 4 ? (grip % 2 === 0 ? -1 : 1) : grip === 6 ? -1 : grip === 7 ? 1 : 0;
        const signY = grip < 4 ? (grip < 2 ? -1 : 1) : grip === 4 ? -1 : grip === 5 ? 1 : 0;
        const centerX = original.x + original.width / 2;
        const centerY = original.y + original.height / 2;
        const anchorX = centerX - signX * original.width / 2;
        const anchorY = centerY - signY * original.height / 2;
        const horizontal = signX < 0 ? anchorX : signX > 0 ? parent.width - anchorX
            : 2 * Math.min(centerX, parent.width - centerX);
        const vertical = signY < 0 ? anchorY : signY > 0 ? parent.height - anchorY
            : 2 * Math.min(centerY, parent.height - centerY);
        const ratio = Math.max(0.01, original.height / Math.max(1, original.width));
        const maximum = Math.min(horizontal, vertical / ratio);
        const projected = (signX * dx + signY * dy * ratio) / ((signX ? 1 : 0) + (signY ? ratio * ratio : 0));
        const minimum = Math.min(36, maximum);
        let width = Math.max(minimum, Math.min(maximum, original.width + projected));

        const xRange = [anchorX + signX * minimum, anchorX + signX * maximum];
        const yRange = [anchorY + signY * minimum * ratio, anchorY + signY * maximum * ratio];
        const snappedX = signX ? Placement.snap(anchorX + signX * width, [0],
            Placement.alignmentGuides(parent.width, siblings, true), Math.min(...xRange), Math.max(...xRange)) : null;
        const snappedY = signY ? Placement.snap(anchorY + signY * width * ratio, [0],
            Placement.alignmentGuides(parent.height, siblings, false), Math.min(...yRange), Math.max(...yRange)) : null;

        guideX = -1;
        guideY = -1;
        const hasX = snappedX && snappedX.guide >= 0;
        const hasY = snappedY && snappedY.guide >= 0;
        if (hasX && (!hasY || snappedX.distance <= snappedY.distance / ratio)) {
            width = Math.abs(snappedX.position - anchorX);
            guideX = snappedX.guide;
        } else if (hasY) {
            width = Math.abs(snappedY.position - anchorY) / ratio;
            guideY = snappedY.guide;
        }

        const height = width * ratio;
        draft = Qt.rect(anchorX - (1 - signX) * width / 2, anchorY - (1 - signY) * height / 2, width, height);
    }

    function finish() {
        if (!moving)
            return;
        if (draft !== original)
            done(x, y, width);
        moving = false;
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.SizeAllCursor
        onClicked: root.select()
    }

    DragHandler {
        target: null
        onActiveChanged: active ? root.begin() : root.finish()
        onActiveTranslationChanged: if (active) root.move(activeTranslation.x, activeTranslation.y)
    }

    Rectangle {
        visible: root.moving && root.guideX >= 0
        x: root.guideX - root.x
        y: -root.y
        width: 2
        height: root.parent.height
        color: Colors.primary
    }

    Rectangle {
        visible: root.moving && root.guideY >= 0
        x: -root.x
        y: root.guideY - root.y
        width: root.parent.width
        height: 2
        color: Colors.primary
    }

    Canvas {
        anchors.fill: parent
        anchors.margins: -9
        visible: root.selected
        antialiasing: true

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()
        readonly property color stroke: Colors.primary
        onStrokeChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            const left = 2;
            const top = 2;
            const right = width - 2;
            const bottom = height - 2;
            const radius = Math.min(24, (width - 4) / 5, (height - 4) / 5);
            const grip = radius + 8;
            const centerX = width / 2;
            const centerY = height / 2;
            const edgeX = Math.min(20, Math.max(0, centerX - grip - 7));
            const edgeY = Math.min(20, Math.max(0, centerY - grip - 7));

            ctx.reset();
            ctx.strokeStyle = stroke;
            ctx.lineWidth = 2;
            ctx.setLineDash([3, 5]);
            ctx.beginPath();
            ctx.roundedRect(6, 6, width - 12, height - 12, Math.max(0, radius - 4), Math.max(0, radius - 4));
            ctx.stroke();

            ctx.setLineDash([]);
            ctx.lineCap = "round";
            ctx.beginPath();
            ctx.moveTo(left, top + grip);
            ctx.lineTo(left, top + radius);
            ctx.quadraticCurveTo(left, top, left + radius, top);
            ctx.lineTo(left + grip, top);
            ctx.moveTo(right - grip, top);
            ctx.lineTo(right - radius, top);
            ctx.quadraticCurveTo(right, top, right, top + radius);
            ctx.lineTo(right, top + grip);
            ctx.moveTo(left, bottom - grip);
            ctx.lineTo(left, bottom - radius);
            ctx.quadraticCurveTo(left, bottom, left + radius, bottom);
            ctx.lineTo(left + grip, bottom);
            ctx.moveTo(right - grip, bottom);
            ctx.lineTo(right - radius, bottom);
            ctx.quadraticCurveTo(right, bottom, right, bottom - radius);
            ctx.lineTo(right, bottom - grip);
            if (edgeX > 0) {
                ctx.moveTo(centerX - edgeX, top);
                ctx.lineTo(centerX + edgeX, top);
                ctx.moveTo(centerX - edgeX, bottom);
                ctx.lineTo(centerX + edgeX, bottom);
            }
            if (edgeY > 0) {
                ctx.moveTo(left, centerY - edgeY);
                ctx.lineTo(left, centerY + edgeY);
                ctx.moveTo(right, centerY - edgeY);
                ctx.lineTo(right, centerY + edgeY);
            }
            ctx.stroke();
        }
    }

    Repeater {
        model: root.selected ? 8 : 0
        delegate: Item {
            id: grip
            required property int index
            readonly property bool hasTools: root.toolsAvailable && index === 3
            readonly property bool corner: index < 4
            readonly property bool horizontalEdge: index === 4 || index === 5
            readonly property bool verticalEdge: index === 6 || index === 7
            readonly property real centerX: corner ? (index % 2 === 0 ? 0 : root.width)
                : verticalEdge ? (index === 6 ? -6 : root.width + 6) : root.width / 2
            readonly property real centerY: corner ? (index < 2 ? 0 : root.height)
                : horizontalEdge ? (index === 4 ? -6 : root.height + 6) : root.height / 2

            width: corner ? 36 : horizontalEdge ? Math.min(45, root.width / 3) : 20
            height: corner ? 36 : verticalEdge ? Math.min(45, root.height / 3) : 20
            x: centerX - (hasTools ? width - 4 : width / 2)
            y: centerY - (hasTools ? height - 4 : height / 2)

            activeFocusOnTab: hasTools
            Accessible.role: Accessible.Button
            Accessible.ignored: !hasTools
            Accessible.name: "Tools for " + root.title
            Accessible.onPressAction: if (hasTools) root.toolsRequested()
            Keys.onReturnPressed: if (hasTools) root.toolsRequested()
            Keys.onSpacePressed: if (hasTools) root.toolsRequested()

            Rectangle {
                visible: grip.hasTools
                anchors.centerIn: parent
                width: 26
                height: width
                radius: width / 2
                antialiasing: true
                color: Colors.primary
                border.width: toolHover.hovered || grip.activeFocus ? 1 : 0
                border.color: Colors.overPrimary

                Text {
                    anchors.centerIn: parent
                    text: "\uf0ad" // Wrench
                    font.family: "Symbols Nerd Font Mono"
                    font.pixelSize: 14
                    renderType: Text.CurveRendering
                    color: Colors.overPrimary
                }

                HoverHandler {
                    id: toolHover
                    enabled: grip.hasTools
                }

                TapHandler {
                    enabled: grip.hasTools
                    gesturePolicy: TapHandler.DragThreshold
                    onTapped: root.toolsRequested()
                }
            }

            HoverHandler {
                cursorShape: toolHover.hovered ? Qt.PointingHandCursor
                    : horizontalEdge ? Qt.SizeVerCursor : verticalEdge ? Qt.SizeHorCursor
                    : index === 0 || index === 3 ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
            }

            DragHandler {
                target: null
                grabPermissions: PointerHandler.CanTakeOverFromAnything
                onActiveChanged: active ? root.begin() : root.finish()
                onActiveTranslationChanged: if (active) root.resize(activeTranslation.x, activeTranslation.y, index)
            }
        }
    }

    Rectangle {
        anchors.bottom: parent.top
        anchors.bottomMargin: 12
        anchors.horizontalCenter: parent.horizontalCenter
        width: caption.implicitWidth + 12
        height: caption.implicitHeight + 4
        radius: 5
        color: root.selected ? Colors.primary : Colors.surfaceContainerHighest

        Text {
            id: caption
            anchors.centerIn: parent
            text: root.title
            color: root.selected ? Colors.overPrimary : Colors.overSurface
        }
    }
}
