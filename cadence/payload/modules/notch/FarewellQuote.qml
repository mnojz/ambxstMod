import QtQuick

// Ambxst Cadence (mnojz.cadence): the line the farewell shows.
//
// Always ONE line, whatever the screen: the quote is set at a size that suits
// the screen (2.6% of its height, less on a narrow or upright one) and, if it
// would not fit in 86% of the width at that size, at the largest size that
// does. It never wraps; a line so long it would need less than 6 px is elided.
// Pure on purpose -- no shell imports -- so it can be laid out in a test
// harness at any screen size.
Item {
    id: root

    property string quote: ""
    property color quoteColor: "white"
    property string fontFamily: ""
    // 0 = hidden, 1 = fully up (fade plus a short rise).
    property real reveal: 0

    readonly property real basePixelSize: Math.max(14, Math.round(Math.min(root.height * 0.026, root.width * 0.03)))
    readonly property real lineWidth: Math.round(root.width * 0.86)
    // What the fit settled on, for layout tests.
    readonly property real fittedPixelSize: quoteText.fontInfo.pixelSize
    readonly property int quoteLineCount: quoteText.lineCount
    readonly property real quoteContentWidth: quoteText.contentWidth
    readonly property bool quoteTruncated: quoteText.truncated

    Text {
        anchors.centerIn: parent
        width: root.lineWidth
        opacity: root.reveal
        transform: Translate {
            y: (1 - root.reveal) * 14
        }
        id: quoteText
        text: root.quote
        color: root.quoteColor
        font.family: root.fontFamily
        font.pixelSize: root.basePixelSize
        font.weight: Font.Medium
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: 6
        wrapMode: Text.NoWrap
        maximumLineCount: 1
        elide: Text.ElideRight
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
    }
}
