pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Read the mod manager’s window dimensions before the Settings window opens.
Singleton {
    id: root

    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ambxst"
    property var values: ({})
    property var legacyValues: ({})

    readonly property int settingsFloatWidth: integer("settingsFloatWidth", 41, 20, 100)
    readonly property int settingsFloatHeight: integer("settingsFloatHeight", 66, 20, 100)

    function integer(key: string, fallback: int, minimum: int, maximum: int): int {
        const value = root.values[key];
        return Number.isInteger(value) && value >= minimum && value <= maximum ? value : fallback;
    }

    function readObject(view): var {
        const text = view.text();
        if (!view.loaded)
            return {};
        try {
            const object = JSON.parse(text);
            if (object && typeof object === "object" && !Array.isArray(object))
                return object;
        } catch (error) {
            console.warn("CadenceSettings: could not read settings:", error);
        }
        return null;
    }

    function load(): void {
        const saved = root.readObject(modFile);
        root.legacyValues = Object.assign({}, root.readObject(originalLegacyFile) ?? {},
                                          root.readObject(legacyFile) ?? {});
        const originalSizes = root.readObject(originalModFile) ?? {};
        if (saved === null)
            return;

        const merged = Object.assign({}, saved);
        const keys = ["settingsFloatWidth", "settingsFloatHeight"];
        let migrated = false;
        for (const key of keys) {
            if (merged[key] !== undefined)
                continue;

            const value = originalSizes[key] ?? root.legacyValues[key];
            if (typeof value !== "number" || value < 20)
                continue;

            merged[key] = Math.min(100, Math.round(value));
            migrated = true;
        }
        root.values = merged;

        if (migrated) {
            // The manager normally creates this directory on the first save.
            // Start the migration only after the directory exists.
            ensureModDir.running = true;
        }
    }

    function markUpdatesHandedOver(): void {
        if (root.legacyValues.modUpdatesHandedOver === true)
            return;
        root.legacyValues = Object.assign({}, root.legacyValues, { modUpdatesHandedOver: true });
        legacyFile.setText(JSON.stringify(root.legacyValues, null, 2) + "\n");
    }

    FileView {
        id: modFile
        path: root.configDir + "/mods/mnojz.cadence.json"
        blockLoading: true
        atomicWrites: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            if (!ensureModDir.running)
                root.values = root.readObject(modFile) ?? {};
        }
    }

    FileView {
        id: legacyFile
        path: root.configDir + "/cadence.json"
        blockLoading: true
        atomicWrites: true
        printErrors: false
    }

    FileView {
        id: originalModFile
        path: root.configDir + "/mods/drpezzer.roadie.json"
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: originalLegacyFile
        path: root.configDir + "/roadie.json"
        blockLoading: true
        printErrors: false
    }

    Process {
        id: ensureModDir
        command: ["mkdir", "-p", root.configDir + "/mods"]
        onExited: code => {
            if (code !== 0)
                return;
            // Keep any values the mod manager saved while the directory was created.
            modFile.reload();
            const current = root.readObject(modFile);
            if (current === null)
                return;
            root.values = Object.assign({}, root.values, current);
            modFile.setText(JSON.stringify(root.values, null, 2) + "\n");
        }
    }

    Component.onCompleted: root.load()
}
