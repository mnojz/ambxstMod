pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.theme

StyledRect {
    id: root

    required property string title
    required property string subtitle
    required property string glyph
    required property bool checked
    property alias leadingActions: headerLeadingActions.data
    signal toggled(bool checked)

    Layout.fillWidth: true
    Layout.preferredHeight: 52
    variant: "common"
    enableShadow: false
    radius: Styling.radius(0)

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 10

        RowLayout {
            id: headerLeadingActions
            visible: children.length > 0 && children[0].visible
        }

        Text {
            text: root.glyph
            font.family: Icons.font
            font.pixelSize: 22
            color: root.checked ? Styling.srItem("overprimary") : Colors.overSurfaceVariant
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
                text: root.title
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(0)
                font.bold: true
                color: Colors.overBackground
            }

            Text {
                Layout.fillWidth: true
                text: root.subtitle
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overSurfaceVariant
                elide: Text.ElideRight
            }
        }

        // Power switch. Driven straight off the service rather than a
        // two-way binding, so a state refresh can't re-trigger it.
        Item {
            id: powerToggle
            Layout.preferredWidth: 40
            Layout.preferredHeight: 20

            readonly property bool on: root.checked

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: powerToggle.on ? Styling.srItem("overprimary") : Colors.surfaceBright
                border.color: powerToggle.on ? Styling.srItem("overprimary") : Colors.outline
                border.width: 1

                Behavior on color {
                    enabled: Config.animDuration > 0
                    ColorAnimation {
                        duration: Config.animDuration / 2
                    }
                }

                Rectangle {
                    x: powerToggle.on ? parent.width - width - 2 : 2
                    y: 2
                    width: parent.height - 4
                    height: width
                    radius: width / 2
                    color: powerToggle.on ? Colors.background : Colors.overSurfaceVariant

                    Behavior on x {
                        enabled: Config.animDuration > 0
                        NumberAnimation {
                            duration: Config.animDuration / 2
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on color {
                        enabled: Config.animDuration > 0
                        ColorAnimation {
                            duration: Config.animDuration / 2
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggled(!powerToggle.on)
            }
        }
    }
}
