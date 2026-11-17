pragma Singleton
import QtQuick
import qs.modules.theme as ShellTheme
import qs.config

QtObject {
    function alpha(color, opacity) {
        return Qt.rgba(color.r, color.g, color.b, opacity);
    }
    readonly property color background: ShellTheme.Colors.background
    readonly property color text: "#e6e8f0"
    readonly property color muted: "#9aa0b4"
    readonly property color border: alpha(ShellTheme.Colors.outline, 0.25)
    readonly property color subtle: alpha(text, 0.035)
    readonly property color hover: alpha(text, 0.055)
    readonly property color selected: Qt.rgba(1, 1, 1, 0.06)
    readonly property color accent: "#8aa4ff"
    readonly property color accentFill: alpha(accent, 0.12)
    readonly property color scrim: alpha(ShellTheme.Colors.scrim, 0.4)
    readonly property color shadow: alpha(ShellTheme.Colors.shadow, 0.6)
    readonly property color error: text
    readonly property int unit: 8
    readonly property int radius: 14
    readonly property int rowRadius: 8
    readonly property int chipRadius: 6
    readonly property int keyRadius: 4
    readonly property int searchSize: 16
    readonly property real nameSize: 13.5
    readonly property int metaSize: 12
    readonly property int smallSize: 11
    readonly property int duration: 140
    readonly property string font: {
        const families = Qt.fontFamilies();
        return families.includes("Inter") ? "Inter" : families.includes("Noto Sans") ? "Noto Sans" : "sans-serif";
    }
    readonly property string iconFont: ShellTheme.Icons.font
    function icon(name) {
        switch (name) {
        // Phosphor magnifying-glass; the host singleton only exports its +/- variants.
        case "search":
            return "\ue30c";
        case "refresh":
            return ShellTheme.Icons.sync;
        case "upgrade":
            return ShellTheme.Icons.arrowUp;
        case "chevron":
            return ShellTheme.Icons.caretDown;
        case "log":
            return ShellTheme.Icons.terminal;
        case "stop":
            return ShellTheme.Icons.stop;
        case "close":
            return ShellTheme.Icons.cancel;
        case "spinner":
            return ShellTheme.Icons.spinnerGap;
        case "key":
            return ShellTheme.Icons.shieldCheck;
        default:
            return ShellTheme.Icons.info;
        }
    }
    readonly property string mono: Config.theme.monoFont
}
