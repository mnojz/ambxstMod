pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

Flickable {
    id: root
    property var pkg: null
    property var details: ({})
    property string error: ""
    property bool showDependencies: false
    readonly property string packageName: pkg?.name ?? ""
    readonly property string repository: value("Repository") || pkg?.repo || "local"
    readonly property var dependencies: {
        const text = value("Depends On");
        return text ? text.split(/\s+/).filter(Boolean) : [];
    }
    function value(key) {
        const text = String(details[key] ?? "").trim();
        return text === "None" || text === "Unknown" ? "" : text;
    }
    function facts() {
        return [
            {
                label: "Version",
                value: value("Version") || pkg?.version || ""
            },
            {
                label: "Repository",
                value: repository
            },
            {
                label: "Installed size",
                value: value("Installed Size")
            },
            {
                label: "Download size",
                value: value("Download Size")
            },
            {
                label: "License",
                value: value("Licenses")
            }
        ].filter(fact => fact.value);
    }
    readonly property string website: /^https?:\/\//i.test(value("URL")) ? value("URL") : ""
    onPackageNameChanged: {
        contentY = 0;
        showDependencies = false;
    }
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    contentWidth: width
    contentHeight: body.implicitHeight + 24
    ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AlwaysOff
    }

    component InfoText: Text {
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: Theme.infoValueSize
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }
    component InfoButton: Button {
        id: button
        implicitWidth: implicitContentWidth + 16
        implicitHeight: 30
        leftPadding: 8
        rightPadding: 8
        topPadding: 4
        bottomPadding: 4
        hoverEnabled: true
        background: Rectangle {
            radius: Theme.chipRadius
            color: button.hovered ? Theme.hover : "transparent"
        }
        contentItem: InfoText {
            text: button.text
            font.pixelSize: Theme.metaSize
            color: button.hovered ? Theme.text : Theme.muted
            verticalAlignment: Text.AlignVCenter
        }
    }
    ColumnLayout {
        id: body
        x: 12
        y: 12
        width: Math.max(0, root.width - 24)
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            InfoText {
                Layout.fillWidth: true
                text: root.packageName || "Package information"
                font.pixelSize: Theme.infoTitleSize
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }
            InfoText {
                visible: !!root.pkg
                text: root.pkg?.installed ? "Installed" : "Not installed"
                font.pixelSize: Theme.metaSize
                color: root.pkg?.installed ? Theme.repositoryColor(root.repository) : Theme.muted
            }
        }
        TextEdit {
            objectName: "packageDescription"
            Layout.fillWidth: true
            Layout.preferredHeight: contentHeight
            visible: !!text
            text: root.value("Description") || root.pkg?.description || ""
            readOnly: true
            selectByMouse: true
            textFormat: TextEdit.PlainText
            wrapMode: TextEdit.Wrap
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.infoValueSize
        }
        InfoText {
            Layout.fillWidth: true
            visible: !root.pkg || !!root.error || !Object.keys(root.details).length
            text: !root.pkg ? "Select a package to see its details." : root.error || "Loading package information…"
            color: root.error ? Theme.danger : Theme.muted
            font.pixelSize: Theme.metaSize
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.border
        }
        GridLayout {
            objectName: "packageFacts"
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 24
            rowSpacing: 12
            Repeater {
                model: root.pkg ? root.facts() : []
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: Math.max(0, (body.width - 24) / 2)
                    spacing: 3
                    InfoText {
                        Layout.fillWidth: true
                        text: modelData.label
                        font.pixelSize: Theme.metaSize
                        color: Theme.muted
                    }
                    TextEdit {
                        Layout.fillWidth: true
                        Layout.preferredHeight: contentHeight
                        text: modelData.value
                        readOnly: true
                        selectByMouse: true
                        textFormat: TextEdit.PlainText
                        wrapMode: TextEdit.Wrap
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.infoValueSize
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            visible: root.dependencies.length > 0 || !!root.website
            spacing: 8
            InfoButton {
                objectName: "dependenciesButton"
                visible: root.dependencies.length > 0
                text: (root.showDependencies ? "Hide dependencies" : "Dependencies") + " · " + root.dependencies.length
                onClicked: root.showDependencies = !root.showDependencies
            }
            Item {
                Layout.fillWidth: true
            }
            InfoButton {
                visible: !!root.website
                text: "Project website"
                ToolTip.visible: hovered
                ToolTip.text: root.website
                onClicked: Qt.openUrlExternally(root.website)
            }
        }
        Flow {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            visible: root.showDependencies
            spacing: 6
            Repeater {
                model: root.showDependencies ? root.dependencies : []
                delegate: Rectangle {
                    required property string modelData
                    width: Math.min(body.width, dependencyText.implicitWidth + 16)
                    height: 26
                    radius: Theme.keyRadius
                    color: Theme.subtle
                    InfoText {
                        id: dependencyText
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        text: modelData
                        font.pixelSize: Theme.metaSize
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }
}
