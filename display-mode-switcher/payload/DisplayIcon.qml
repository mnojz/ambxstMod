import QtQuick
import QtQuick.Shapes

// CurveRenderer draws vector curves directly, without an intermediate image texture.
Item {
    id: root
    required property int mode
    required property color color
    implicitWidth: 50
    implicitHeight: 46

    function screenPath(x, y, w, h) {
        const r = 1.8;
        return `M ${x+r} ${y} H ${x+w-r} Q ${x+w} ${y} ${x+w} ${y+r} V ${y+h-r} Q ${x+w} ${y+h} ${x+w-r} ${y+h} H ${x+r} Q ${x} ${y+h} ${x} ${y+h-r} V ${y+r} Q ${x} ${y} ${x+r} ${y} Z`;
    }
    readonly property string outline: {
        switch (mode) {
        case 0:
            return screenPath(5, 3, 22, 20) + " M5 23 L2.5 27 Q2 29 4 29 H28 Q30 29 29.5 27 L27 23 M3 26 H29";
        case 1:
            return screenPath(2, 3, 19, 15) + screenPath(11, 10, 19, 15) + " M20.5 25 V29 M15.5 29 H25.5";
        case 2:
            return screenPath(2, 3, 12, 20) + screenPath(18, 3, 12, 20) + " M8 23 V29 M4 29 H12 M24 23 V29 M20 29 H28 M14 13 H18";
        default:
            return screenPath(2, 3, 28, 20) + " M16 23 V29 M9 29 H23";
        }
    }
    Shape {
        anchors.centerIn: parent
        width: 32
        height: 32
        scale: Math.min(root.width / 32, root.height / 32)
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.color
            strokeWidth: 1.65
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            PathSvg { path: root.outline }
        }
    }
}
