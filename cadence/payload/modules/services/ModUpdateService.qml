pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.globals
import qs.modules.services

// Ambxst Cadence (mnojz.cadence): a desktop notification when Ambxst's own
// mod updater finds new versions.
//
// Since Ambxst 1.3.11 the mod manager checks, schedules, reviews and installs
// mod updates itself (Settings > Mods). Cadence announces available updates
// outside the Settings window. Nothing in this file checks or installs anything. It
// watches ModsService.updates (pushed by the daemon after every check, manual
// or scheduled) and notifies once per new version found. Turn on "Scheduled
// checks" in Settings > Mods for checks to happen without opening the panel.
Singleton {
    id: root

    readonly property string cacheFile: Quickshell.env("HOME") + "/.cache/ambxst/cadence_mod_update_notify.json"
    readonly property int modsSection: 10

    // "<id>@<version>/<revision>" of every update already announced, so a
    // status push, a reload or a later check never repeats a notification.
    property var announced: ({})
    property bool cacheLoaded: false

    readonly property var available: {
        const u = ModsService.updates ?? {};
        const list = u.known ?? u.items ?? [];
        return list.filter(item => item && item.state === "available");
    }

    function keyOf(item) {
        return item.id + "@" + (item.toVersion ?? "") + "/" + (item.revision ?? "");
    }

    function nameOf(id) {
        const mod = (ModsService.mods ?? []).find(m => m.id === id);
        return mod?.name ?? id;
    }

    onAvailableChanged: Qt.callLater(root.announce)
    onCacheLoadedChanged: Qt.callLater(root.announce)

    // ── legacy updater migration ───────────────────────────────

    // The original package had its own "check automatically" / "install
    // automatically" switches and interval. Whoever had them on gets Ambxst's
    // scheduled checks (and automatic installs) on instead, once; after that
    // Settings > Mods owns them.
    Connections {
        target: ModsService
        function onLoadedChanged() { Qt.callLater(root.handOver); }
    }
    Component.onCompleted: Qt.callLater(root.handOver)

    function handOver() {
        if (!ModsService.loaded || CadenceSettings.legacyValues.modUpdatesHandedOver === true)
            return;
        const old = CadenceSettings.legacyValues;
        if (old.modAutoCheck === true) {
            if (!ModsService.periodicChecks)
                ModsService.setPeriodicChecks(true);
            // Ambxst offers 1, 6, 24 or 168 hours; take the nearest.
            const hours = Number(old.modCheckHours ?? 6);
            const choices = [1, 6, 24, 168];
            const nearest = choices.reduce((a, b) => Math.abs(b - hours) < Math.abs(a - hours) ? b : a);
            if (ModsService.updateIntervalHours !== nearest)
                ModsService.setUpdateInterval(nearest);
            if (old.modAutoInstall === true && !ModsService.autoUpdate)
                ModsService.setUpdatePolicy("", "on");
            console.log("[Cadence] mod update checks handed to Ambxst: scheduled every", nearest, "h"
                + (old.modAutoInstall === true ? ", automatic installs on" : ""));
        }
        CadenceSettings.markUpdatesHandedOver();
    }

    function announce() {
        if (!root.cacheLoaded || !ModsService.loaded)
            return;
        const current = {};
        const fresh = [];
        for (const item of root.available) {
            const key = root.keyOf(item);
            current[key] = true;
            if (!root.announced[key])
                fresh.push(item);
        }
        // Forget what is no longer offered (installed or withdrawn), so the
        // file stays small; a version is only ever announced once anyway.
        const changed = fresh.length > 0
            || Object.keys(root.announced).some(key => !current[key]);
        root.announced = current;
        if (changed)
            root.saveCache();
        if (fresh.length > 0)
            root.notify(fresh);
    }

    // ── cache ──────────────────────────────────────────────────────────

    FileView {
        id: cacheView
        path: root.cacheFile
        printErrors: false
        onLoaded: {
            try {
                const data = JSON.parse(text() || "{}");
                root.announced = data.announced ?? {};
            } catch (e) {
                console.log("[Cadence] mod update cache unreadable:", e);
            }
            root.cacheLoaded = true;
        }
        onLoadFailed: root.cacheLoaded = true
    }

    function saveCache() {
        cacheView.setText(JSON.stringify({ announced: root.announced }));
    }

    // ── notification ───────────────────────────────────────────────────

    // Settings opens on an index into its sidebar, which the mod manager now
    // orders (mod pages can be moved). Rebuild that order the way SettingsTab
    // does and look the Mods page up by its section id.
    function modsPanelIndex() {
        const sections = [0, 1, 2, 3, 4, 5, 6, 7, 8, root.modsSection];
        for (const mod of ModsService.mods ?? []) {
            if (!mod.enabled || !mod.hasSettingsMenu)
                continue;
            const own = (mod.settingsSections ?? []).length > 0 ? mod.settingsSections : [mod.settingsSection];
            for (const section of own)
                if (section !== undefined && sections.indexOf(section) < 0)
                    sections.push(section);
        }
        sections.push(9);
        const ordered = ModsService.orderSettingsSections(sections.map(section => ({ section: section })));
        const index = ordered.findIndex(item => item.section === root.modsSection);
        return index >= 0 ? index : 9;
    }

    function openModsPanel() {
        const index = root.modsPanelIndex();
        if (!GlobalStates.settingsWindowVisible)
            GlobalShortcuts.toggleSettings();
        GlobalStates.settingsCurrentTab = index;
    }

    function notify(items) {
        const names = items.map(item => root.nameOf(item.id)
            + (item.toVersion && item.toVersion !== item.fromVersion ? " " + item.toVersion : " (new revision)"));
        Notifications.notifyInternal({
            summary: items.length === 1 ? "Mod update available" : items.length + " mod updates available",
            body: names.join(", ") + "\nReview and install in Settings > Mods.",
            appName: "Ambxst Mods",
            appIcon: "system-software-update",
            urgency: "normal",
            replaceKey: "ambxst-mod-updates",
            actions: [{ identifier: "open", text: "Open Mods" }],
            actionHandlers: {
                "open": function () { root.openModsPanel(); }
            }
        });
    }

    // For tests and reports: `cadence updateState`.
    function report() {
        return {
            enabled: true,
            available: root.available.map(root.keyOf),
            announced: Object.keys(root.announced),
            periodicChecks: ModsService.periodicChecks,
            updateIntervalHours: ModsService.updateIntervalHours,
            autoUpdate: ModsService.autoUpdate,
            modsPanelIndex: root.modsPanelIndex()
        };
    }
}
