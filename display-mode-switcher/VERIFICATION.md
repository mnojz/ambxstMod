# Version 1.1.0 UI verification — 2026-11-14

- Installed/reloaded through the supported manager into generation 20261114T095944Z-b1a27ffe.
- With only the physical eDP-1 connected: first installed command creates exactly one chooser surface. Repeated commands cycle the pending outline and retain one continuous surface. It closes after one second without another command.
- Actual screenshot updated: compact 536 × 128 logical pixels, no header/close control/current caption, larger icons and lower labels. Mirror and Extend SVGs redrawn. Runtime inspection found no mod-specific QML errors.
- The active Super+P binding now uses `{ locked = true }` so it works during the menu's keyboard grab. Requests are ignored while the lockscreen is visible.
- 13 backend policy tests remain passing. `tests/ui_smoke.py` provides the opt-in installed-shell timeout regression check, restricted to no-external setups.
- Without an external display, selecting an external mode closes the chooser and reports the missing output without changing the panel.

The earlier hardware limitations below still apply. The old no-external closed-menu behavior is superseded by version 1.1.0.

# Version 1.0.0 verification — 2026-11-14

- Hyprland 0.57.2, Quickshell 0.3.2, Ambxst 1.3.15, base 5d71e924212ce2c0203e7448e0b1e3db52608640 verified locally.
- Manifest validated with jsonschema against the installed manifest.schema.json.
- 13 policy tests pass (`node tests/policy.test.cjs`): disabled discovery, numeric mirror IDs, logical geometry, safe ordering, failed activation, disconnect, stale callbacks, cancellation, multiple externals, mirror transitions, successful external-only ordering, and internal recovery.
- Real compositor smoke test passes Extend → Mirror → Extend → Laptop only → Extend with DM-SMOKE. Temporary virtual output removed in finally; physical panel stayed enabled.
- Installed using `/usr/local/bin/ambxst mods install`, composed alongside all seven existing enabled mods. Full-index patch preimages permit merge with other shell.qml insertions.
- Actual composed shell loaded successfully; `/usr/local/bin/ambxst run displaymode` opened one horizontal panel. Four packaged SVGs and labels render; `menu.png` captures the actual menu. No-external invocation keeps it closed. Normal and fractional logical geometry are covered by policy tests.
- Exact Super+P Lua binding registered successfully in the running compositor and appeared with modmask 64; removed immediately afterward. No user keybinding files changed. Wayland virtual-keyboard synthesis did not demonstrate the global shortcut firing; a physical projection-key press still needs manual acceptance.
- Disable/reload loaded a generation without the mod; re-enable/reload is checked through the supported manager. The manager's eight-second startup trial must finish before another package change.
- Qt 6 qmllint was run. Static analysis reports unresolved `qs.*` VFS imports and consequent unknown types; it cannot fully resolve Quickshell's runtime module scanner. Actual composed-shell loading and visual inspection provide the runtime validation. Initial QML incompatibilities were corrected before delivery.

Hardware limitations: only eDP-1 is physically connected. Physical HDMI mirroring, HDMI activation failure, physical disconnect during external-only, and external-only unplug recovery have policy coverage but remain unverified on hardware. The laptop panel was never disabled for preview or automation. Wayland-injected Right/Tab/Left/Escape navigation was exercised and Escape removed the only chooser surface (1 → 0). Physical pointer selection, Enter/Space application, outside clicks, and fractional-scale rendering still need manual acceptance. Power transitions can override geometry until the documented power.lua integration is applied.
