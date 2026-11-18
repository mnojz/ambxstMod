pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

GridLayout {
    id: root

    required property var bar
    required property bool layerEnabled
    required property real radius
    property bool vertical: false

    readonly property int buttonSize: 36

    columns: vertical ? 1 : 3
    columnSpacing: 4
    rowSpacing: 4

    NetworkIndicator {
        bar: root.bar
        layerEnabled: root.layerEnabled
        startRadius: root.radius
        endRadius: root.radius
        Layout.preferredWidth: root.buttonSize
        Layout.preferredHeight: root.buttonSize
    }

    BluetoothIndicator {
        bar: root.bar
        layerEnabled: root.layerEnabled
        startRadius: root.radius
        endRadius: root.radius
        Layout.preferredWidth: root.buttonSize
        Layout.preferredHeight: root.buttonSize
    }

    BluetoothBatteryIndicator {
        bar: root.bar
        layerEnabled: root.layerEnabled
        startRadius: root.radius
        endRadius: root.radius
        Layout.preferredWidth: root.buttonSize
        Layout.preferredHeight: root.buttonSize
    }
}
