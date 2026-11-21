.pragma library

var available = [
    { id: "poweroff", label: "Power off", icon: "shutdown", command: ["systemctl", "poweroff"] },
    { id: "reboot", label: "Restart", icon: "reboot", command: ["systemctl", "reboot"] }
];

function toggle(shortcuts, id) {
    const existing = shortcuts.find(shortcut => shortcut?.id === id);
    if (existing) {
        return shortcuts.map(shortcut => shortcut === existing
            ? Object.assign({}, shortcut, { enabled: existing.enabled === false }) : shortcut);
    }

    const slot = [0, 0.08].find(x => !shortcuts.some(shortcut =>
        shortcut?.enabled !== false && available.some(action => action.id === shortcut?.id) && shortcut?.x === x));
    return [...shortcuts, { id, x: slot ?? 0, y: 0.08, scale: 100, enabled: true }];
}
