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
    readonly property color actionPrimary: ShellTheme.Colors.primary
    readonly property color onActionPrimary: ShellTheme.Colors.overPrimary
    readonly property color danger: ShellTheme.Colors.red
    readonly property color secondaryAction: alpha(ShellTheme.Colors.overBackground, 0.08)
    readonly property color scrim: alpha(ShellTheme.Colors.scrim, 0.4)
    readonly property color shadow: alpha(ShellTheme.Colors.shadow, 0.6)
    readonly property color error: text
    readonly property color logBackground: Qt.tint(background, alpha(ShellTheme.Colors.shadow, 0.12))
    readonly property color logText: alpha(text, 0.85)
    readonly property color logCommand: ShellTheme.Colors.blue
    readonly property color logSuccess: ShellTheme.Colors.green
    readonly property color logWarning: ShellTheme.Colors.yellow
    readonly property color logError: ShellTheme.Colors.red
    readonly property color logValue: ShellTheme.Colors.cyan
    readonly property int unit: 8
    readonly property int radius: 14
    readonly property int rowRadius: 8
    readonly property int chipRadius: 6
    readonly property int keyRadius: 4
    readonly property int searchSize: 16
    readonly property real nameSize: 13.5
    readonly property int metaSize: 12
    readonly property int logSize: 14
    // About 75% of the former 96-column, 11px log canvas.
    readonly property int logColumns: 56
    readonly property int smallSize: 11
    readonly property int repositoryBadgeWidth: 56
    readonly property int infoTitleSize: 18
    readonly property int infoValueSize: 14
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
        case "sync":
            return ShellTheme.Icons.sync;
        case "install":
            return "\ue20c";
        case "uninstall":
            return ShellTheme.Icons.trash;
        case "info":
            return ShellTheme.Icons.info;
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
    function repositoryLabel(repository) {
        const repo = String(repository ?? "local").toLowerCase();
        const abbreviations = {
            "multilib": "multi",
            "chaotic-aur": "chaot",
            "core-testing": "cor-t",
            "extra-testing": "ext-t",
            "multilib-testing": "mul-t",
            "core-staging": "cor-s",
            "extra-staging": "ext-s",
            "multilib-staging": "mul-s",
            "installed": "local",
            "repo": "local"
        };
        return abbreviations[repo] ?? repo.slice(0, 5);
    }
    function repositoryColor(repository) {
        const repo = String(repository ?? "local").toLowerCase();
        if (repo === "core" || repo.startsWith("core-"))
            return ShellTheme.Colors.green;
        if (repo === "extra" || repo.startsWith("extra-"))
            return ShellTheme.Colors.blue;
        if (repo === "aur")
            return ShellTheme.Colors.yellow;
        if (repo === "multilib" || repo.startsWith("multilib-"))
            return ShellTheme.Colors.magenta;
        if (repo === "chaotic-aur")
            return ShellTheme.Colors.cyan;
        if (repo === "local" || repo === "installed" || repo === "repo")
            return ShellTheme.Colors.tertiary;
        const palette = [ShellTheme.Colors.red, ShellTheme.Colors.cyan, ShellTheme.Colors.tertiary, ShellTheme.Colors.magenta];
        let hash = 0;
        for (let i = 0; i < repo.length; ++i)
            hash = (hash * 31 + repo.charCodeAt(i)) >>> 0;
        return palette[hash % palette.length];
    }
    readonly property string logFont: {
        const families = Qt.fontFamilies();
        const preferred = ["JetBrainsMono Nerd Font Mono", "JetBrainsMono Nerd Font", "JetBrainsMono NFM", "FiraCode Nerd Font Mono", "Hack Nerd Font Mono", "CaskaydiaMono Nerd Font Mono"];
        for (const family of preferred) {
            const installed = families.find(name => name.toLowerCase() === family.toLowerCase());
            if (installed)
                return installed;
        }
        return families.find(name => /nerd font mono|\bNFM$/i.test(name)) || families.find(name => /nerd font/i.test(name)) || Config.theme.monoFont || "monospace";
    }
    readonly property string mono: Config.theme.monoFont
}
