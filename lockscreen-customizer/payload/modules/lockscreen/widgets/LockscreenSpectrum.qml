pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property int consumers: 0
    readonly property int bandCount: 192
    property var bands: []

    function receiveFrame(line) {
        if (!/^(?:\d+;)*\d+$/.test(line))
            return;
        const values = line.split(";");
        if (values.length !== bandCount)
            return;
        const next = values.map(value => Math.min(1, Number(value) / 1000));
        // An empty array represents silence without repainting on every idle frame.
        if (next.some(value => value > 0))
            bands = next;
        else if (bands.length)
            bands = [];
    }

    readonly property Process analyzer: Process {
        running: root.consumers > 0
        command: ["python3", decodeURIComponent(Qt.resolvedUrl("../../../scripts/lockscreen_spectrum.py").toString().replace(/^file:\/\//, ""))]
        stdout: SplitParser {
            onRead: line => root.receiveFrame(line)
        }
        onExited: root.bands = []
    }
}
