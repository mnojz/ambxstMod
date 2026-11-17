pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."
import "ActivityParser.js" as ActivityParser

Rectangle {
    id: root
    signal clearRequested
    property string logs: ""
    property var transaction: ({})
    readonly property bool removing: transaction.operation === "remove"
    readonly property bool updating: transaction.operation === "upgrade"
    readonly property color transactionColor: removing ? Theme.logError : updating ? Theme.logCommand : Theme.logSuccess
    property string displayText: ""
    property int columns: Theme.logColumns
    property int lineCount: 0
    property bool followTail: true
    property bool rawOutput: false
    property var entries: []
    radius: Theme.rowRadius
    color: Theme.logBackground
    function refreshText() {
        displayText = ActivityParser.cleanOutput(logs).replace(/\r\n?/g, "\n");
        const readingPosition = feed.contentY;
        const next = ActivityParser.parse(displayText, transaction);
        // Update existing rows so a progress tick does not recreate its bar.
        for (let i = 0; i < next.length; i++) {
            if (i >= activityModel.count)
                activityModel.append(next[i]);
            else if (JSON.stringify(entries[i]) !== JSON.stringify(next[i]))
                activityModel.set(i, next[i]);
        }
        if (activityModel.count > next.length)
            activityModel.remove(next.length, activityModel.count - next.length);
        entries = next;
        if (!followTail && !rawOutput)
            Qt.callLater(() => feed.contentY = Math.max(feed.originY, Math.min(readingPosition, feed.originY + Math.max(0, feed.contentHeight - feed.height))));
        const lines = displayText.split("\n");
        columns = lines.reduce((longest, line) => Math.max(longest, line.replace(/\t/g, "        ").length), Theme.logColumns);
        lineCount = displayText ? lines.length - (displayText.endsWith("\n") ? 1 : 0) : 0;
        Qt.callLater(scrollToTail);
    }
    function scheduleRefresh() {
        if (visible && !renderDelay.running)
            renderDelay.start();
    }
    function escapeHtml(text) {
        return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
    }
    function span(text, color, bold) {
        return '<span style="color:' + color.toString() + (bold ? ';font-weight:700' : '') + '">' + escapeHtml(text) + '</span>';
    }
    function highlight(line) {
        if (/(?:^\s*(?:error|fatal|exception|traceback)\b|\b(?:error|fatal):|\b(?:failed|failure|not found|could not)\b)/i.test(line))
            return span(line, Theme.logError, false);
        if (/\b(warning|warn|deprecated)\b/i.test(line))
            return span(line, Theme.logWarning, false);
        if (/\b(successfully|completed|finished|up.to.date)\b/i.test(line))
            return span(line, root.transactionColor, false);
        if (/^\s*(::|==>|->)/.test(line))
            return span(line, Theme.logCommand, true);
        const token = /https?:\/\/[^\s]+|(?:\.?\.?\/)[^\s]+|"[^"]*"|'[^']*'|--[a-zA-Z][\w-]*(?:=[^\s]+)?|\b\d+(?:\.\d+)?(?:%|\/\d+|\b)|^\s*[$+>]\s*/g;
        let html = "", end = 0, match;
        while ((match = token.exec(line)) !== null) {
            html += escapeHtml(line.slice(end, match.index));
            const value = match[0];
            const color = /^['"]/.test(value) ? Theme.logWarning : /^--/.test(value) ? root.transactionColor : /^\s*[$+>]/.test(value) ? Theme.logCommand : Theme.logValue;
            html += span(value, color, false);
            end = token.lastIndex;
        }
        return html + escapeHtml(line.slice(end));
    }
    function activityTone(row) {
        if (row.kind === "error")
            return Theme.logError;
        if (row.kind === "warning")
            return Theme.logWarning;
        if (row.kind !== "note") {
            if (row.action === "remove")
                return Theme.logError;
            if (row.action === "upgrade")
                return Theme.logCommand;
            if (row.action === "install" && ["start", "progress", "success", "done"].includes(row.kind))
                return Theme.logSuccess;
        }
        if (row.kind === "success" || row.kind === "done")
            return Theme.logSuccess;
        if (row.kind === "progress")
            return Theme.logValue;
        if (["command", "build", "start"].includes(row.kind))
            return Theme.logCommand;
        return Theme.logText;
    }
    function activityIcon(row) {
        if (row.kind === "error")
            return "close";
        if (row.kind === "warning")
            return "warning";
        if (row.kind === "build")
            return "build";
        if (row.kind === "success")
            return row.action === "remove" ? "uninstall" : row.action === "upgrade" ? "sync" : "key";
        if (row.kind === "package" || row.kind === "progress")
            return row.action === "remove" ? "uninstall" : row.action === "upgrade" ? "sync" : "install";
        if (row.kind === "command" || row.kind === "build")
            return "log";
        return "info";
    }
    function formattedText() {
        const family = Theme.logFont.replace(/["'<>]/g, "");
        const lines = displayText ? displayText.split("\n").map(highlight).join("\n") : escapeHtml("Logs appear when an operation starts.");
        return '<pre style="margin:0;font-family:\'' + family + '\';">' + lines + '</pre>';
    }
    function scrollToTail() {
        if (followTail && visible) {
            if (rawOutput)
                view.contentY = Math.max(0, view.contentHeight - view.height);
            else if (feed.count)
                feed.positionViewAtEnd();
        }
    }
    onRawOutputChanged: Qt.callLater(scrollToTail)
    onLogsChanged: Qt.callLater(scheduleRefresh)
    onTransactionChanged: Qt.callLater(scheduleRefresh)
    onVisibleChanged: {
        if (visible)
            Qt.callLater(refreshText);
    }
    Component.onCompleted: {
        if (visible)
            refreshText();
    }
    Timer {
        id: renderDelay
        interval: 80
        onTriggered: root.refreshText()
    }
    RowLayout {
        id: heading
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 12
        anchors.rightMargin: 8
        height: 34
        spacing: 8
        Text {
            text: root.rawOutput ? "Raw output" : "Activity"
            color: Theme.muted
            font.family: Theme.logFont
            font.pixelSize: Theme.metaSize
            font.weight: Font.Medium
        }
        Item {
            Layout.fillWidth: true
        }
        Text {
            text: root.rawOutput ? root.lineCount + " lines" : root.entries.length + " events"
            color: Theme.muted
            font.family: Theme.logFont
            font.pixelSize: Theme.smallSize
        }
        LogButton {
            objectName: "rawLogButton"
            text: root.rawOutput ? "Activity" : "Raw"
            ToolTip.text: root.rawOutput ? "Show readable activity" : "Show original output for troubleshooting"
            onClicked: root.rawOutput = !root.rawOutput
        }
        LogButton {
            objectName: "followLogButton"
            text: root.followTail ? "Following" : "Follow tail"
            ToolTip.text: "Follow new activity"
            onClicked: {
                root.followTail = !root.followTail;
                root.scrollToTail();
            }
        }
        Button {
            id: clearButton
            objectName: "clearLogButton"
            implicitWidth: 28
            implicitHeight: 28
            padding: 6
            focusPolicy: Qt.NoFocus
            hoverEnabled: true
            enabled: !!root.logs.trim() || root.entries.length > 0
            opacity: enabled ? 1 : 0.35
            Accessible.name: "Clear logs"
            ToolTip.visible: hovered
            ToolTip.text: "Clear logs"
            ToolTip.delay: 400
            onClicked: {
                root.clearRequested();
                root.followTail = true;
                view.contentX = 0;
                root.refreshText();
            }
            background: Rectangle {
                radius: Theme.keyRadius
                color: clearButton.hovered && clearButton.enabled ? Theme.hover : "transparent"
            }
            contentItem: Text {
                text: Theme.logIcon("uninstall")
                font.family: Theme.logFont
                font.pixelSize: 16
                color: clearButton.hovered ? Theme.text : Theme.muted
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
    component LogButton: Button {
        id: button
        implicitHeight: 28
        implicitWidth: implicitContentWidth + 16
        leftPadding: 8
        rightPadding: 8
        hoverEnabled: true
        ToolTip.visible: hovered
        background: Rectangle {
            radius: Theme.keyRadius
            color: button.hovered ? Theme.hover : "transparent"
        }
        contentItem: Text {
            text: button.text
            font.family: Theme.logFont
            font.pixelSize: Theme.metaSize
            color: button.hovered ? Theme.text : Theme.muted
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
        }
    }
    ListModel {
        id: activityModel
    }
    ListView {
        id: feed
        objectName: "activityFeed"
        visible: !root.rawOutput
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: heading.bottom
        anchors.bottom: parent.bottom
        anchors.margins: 8
        anchors.topMargin: 0
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        spacing: 0
        model: activityModel
        section.property: "group"
        section.criteria: ViewSection.FullString
        section.labelPositioning: ViewSection.InlineLabels | ViewSection.CurrentLabelAtStart
        section.delegate: Rectangle {
            required property string section
            objectName: "activitySection"
            width: feed.width
            height: section ? 24 : 0
            color: Theme.logBackground
            Text {
                anchors.fill: parent
                anchors.leftMargin: 8
                text: parent.section
                color: Theme.logCommand
                font.family: Theme.logFont
                font.pixelSize: Theme.metaSize
                font.weight: Font.Medium
                verticalAlignment: Text.AlignVCenter
            }
        }
        onContentHeightChanged: Qt.callLater(root.scrollToTail)
        onHeightChanged: Qt.callLater(root.scrollToTail)
        onMovementEnded: root.followTail = atYEnd
        delegate: Item {
            id: eventRow
            objectName: "activityRow"
            required property var model
            readonly property var modelData: model
            readonly property color tone: root.activityTone(modelData)
            width: feed.width
            height: eventLayout.implicitHeight + 6
            RowLayout {
                id: eventLayout
                x: 8
                y: 3
                width: Math.max(0, parent.width - 16)
                spacing: 8
                Text {
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: 18
                    visible: !["note", "start", "done"].includes(eventRow.modelData.kind)
                    text: Theme.logIcon(root.activityIcon(eventRow.modelData))
                    font.family: Theme.logFont
                    font.pixelSize: 16
                    color: eventRow.tone
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        TextEdit {
                            Layout.fillWidth: true
                            Layout.preferredHeight: contentHeight
                            text: eventRow.modelData.kind === "note" ? root.highlight(eventRow.modelData.title) : root.span(eventRow.modelData.title, eventRow.tone, ["start", "done"].includes(eventRow.modelData.kind))
                            textFormat: TextEdit.RichText
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.Wrap
                            font.family: Theme.logFont
                            font.pixelSize: eventRow.modelData.kind === "done" ? Theme.logCompletionSize : eventRow.modelData.kind === "start" ? 18 : Theme.logSize
                            font.weight: ["start", "done"].includes(eventRow.modelData.kind) ? Font.Bold : Font.Normal
                            color: eventRow.tone
                            selectionColor: Theme.actionPrimary
                            selectedTextColor: Theme.onActionPrimary
                        }
                        Text {
                            objectName: "activityProgressLabel"
                            visible: !!eventRow.modelData.progressLabel
                            text: eventRow.modelData.progressLabel
                            color: eventRow.tone
                            font.family: Theme.logFont
                            font.pixelSize: Theme.metaSize
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !!eventRow.modelData.detail
                        text: eventRow.modelData.detail
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        font.family: Theme.logFont
                        font.pixelSize: Theme.metaSize
                        color: Theme.muted
                    }
                    Rectangle {
                        id: bar
                        objectName: "activityProgressBar"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 5
                        visible: eventRow.modelData.kind === "progress" || eventRow.modelData.kind === "build"
                        radius: 2.5
                        color: Theme.secondaryAction
                        clip: true
                        Rectangle {
                            id: fill
                            height: parent.height
                            radius: parent.radius
                            width: eventRow.modelData.progress >= 0 ? parent.width * eventRow.modelData.progress : parent.width * 0.25
                            color: eventRow.tone
                            Behavior on width {
                                NumberAnimation {
                                    duration: Theme.duration
                                }
                            }
                            NumberAnimation on x {
                                from: -fill.width
                                to: bar.width
                                duration: 1100
                                loops: Animation.Infinite
                                onRunningChanged: {
                                    if (!running)
                                        fill.x = 0;
                                }
                                running: bar.visible && root.visible && eventRow.modelData.progress < 0
                            }
                        }
                    }
                }
                Text {
                    visible: eventRow.modelData.count > 1 && eventRow.modelData.kind !== "build"
                    text: "×" + eventRow.modelData.count
                    font.family: Theme.logFont
                    font.pixelSize: Theme.metaSize
                    color: Theme.muted
                }
            }
        }
        Text {
            anchors.centerIn: parent
            visible: feed.count === 0
            text: "Package activity will appear here."
            color: Theme.muted
            font.family: Theme.logFont
            font.pixelSize: Theme.metaSize
        }
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AlwaysOff
        }
    }

    Flickable {
        id: view
        visible: root.rawOutput
        objectName: "logView"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: heading.bottom
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.AutoFlickDirection
        contentWidth: Math.max(width, metrics.advanceWidth("M") * root.columns + 24)
        contentHeight: Math.max(height, output.contentHeight + 8)
        onContentHeightChanged: Qt.callLater(root.scrollToTail)
        onHeightChanged: Qt.callLater(root.scrollToTail)
        onMovementEnded: root.followTail = contentY >= contentHeight - height - 24
        FontMetrics {
            id: metrics
            font: output.font
        }
        TextEdit {
            id: output
            objectName: "logText"
            x: 12
            width: Math.max(0, view.contentWidth - 24)
            height: Math.max(view.height - 8, contentHeight)
            text: root.formattedText()
            textFormat: TextEdit.RichText
            wrapMode: TextEdit.NoWrap
            readOnly: true
            selectByMouse: true
            color: Theme.logText
            selectedTextColor: Theme.onActionPrimary
            selectionColor: Theme.actionPrimary
            font.family: Theme.logFont
            font.pixelSize: Theme.logSize
            tabStopDistance: metrics.advanceWidth("M") * 8
        }
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AlwaysOff
        }
        ScrollBar.horizontal: ScrollBar {
            policy: ScrollBar.AlwaysOff
        }
        WheelHandler {
            target: null
            acceptedModifiers: Qt.ShiftModifier
            onWheel: event => {
                const delta = event.pixelDelta.x || event.pixelDelta.y || event.angleDelta.x / 2 || event.angleDelta.y / 2;
                view.contentX = Math.max(0, Math.min(view.contentWidth - view.width, view.contentX - delta));
                event.accepted = true;
            }
        }
    }
}
