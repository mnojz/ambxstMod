# Display Mode Switcher

ID: `mnojz.displaymode`. Tested with Ambxst 1.3.15, Hyprland 0.57.2 (Lua), and Quickshell 0.3.2. No Python launcher, extra shell instance, daemon, or ArchSetup dependency.

Install from this directory using the normal manager:

```sh
ambxst mods install /home/manoj/Projects/ambxstMod/display-mode-switcher
ambxst mods enable mnojz.displaymode
ambxst reload
ambxst run displaymode
```

Add this to your Hyprland Lua configuration, alongside your other bindings:

```lua
hl.bind("SUPER + P", hl.dsp.exec_cmd("/usr/local/bin/ambxst run displaymode"), { locked = true })
```

The verified installed command routes through the Ambxst daemon's `ui.command` stream to `GlobalShortcuts` and the single shell-owned menu. It does not select an arbitrary Quickshell instance. No keybinding files are modified by installation. The optional `displaymode.toggle` Quickshell IPC target must be addressed using the actual Ambxst shell PID, not an unqualified `qs ipc` call.

The menu opens even with no external display. The first shortcut press selects the current arrangement; subsequent presses cycle Laptop only → Mirror → Extend → External only. Each press restarts a one-second timer. After one second without a press, the menu closes and applies the selected mode. An already-current mode needs no update. Selecting an external mode without a connected external output reports “No external display connected” and leaves displays unchanged. Missing internal panels produce an accurate notification.

The compact menu contains only four equal buttons with native vector icons above centered bold labels. Accent fill indicates the applied mode; the accent outline indicates the pending selection. Click or Enter/Space applies immediately. Left/Right and Tab/Shift+Tab navigate and restart the timer; Escape and outside clicks cancel without applying. With multiple external outputs, right-click a button or press the Menu key to select the target from the same shell's context menu. Its open state pauses the timeout. The `locked` binding option allows subsequent shortcut presses while the layer has exclusive keyboard focus; the mod ignores shortcut requests on the lockscreen.

Laptop only disables all external outputs; the other modes enable the selected external target before disabling other external outputs. Discovery uses `hyprctl monitors all -j`, including disabled connected outputs, and identifies eDP/LVDS/DSI internal connectors dynamically.

Runtime Lua monitor updates preserve unrelated monitor settings. The backend pins the existing internal position when enabling it, uses transformed logical width for Extend, clears mirroring explicitly, and selects a supported mode only to reactivate an inactive output. Bounded state polling verifies each operation. Concurrent apply requests cancel the older transaction and ask for a retry after it drains; stale completions cannot proceed to disable outputs. Per-process watchdogs and per-delay timer instances are owned by the mod and destroyed with it. Notifications replace a single key.

While loaded, the mod polls every two seconds and restores the internal panel if it is disabled and no external output is usable. Disable/uninstall/reload destroys the panel, keyboard exclusivity, timers, and process objects. Display arrangements persist in the compositor; the mod does not reset rules at startup. Reloaded enabled instances resume recovery checks. Once disabled/uninstalled, unplug recovery is no longer provided: return to Laptop only before disabling if you need recovery without this mod. No external recovery daemon is installed.

```sh
ambxst mods disable mnojz.displaymode
ambxst reload
# optional:
ambxst mods remove mnojz.displaymode
```

## Existing ArchSetup power.lua integration

The inspected `~/.config/hypr/modules/power.lua` selects active eDP or falls back to the first active output. Its `apply_mode` sends `position="auto", scale=1`, including on monitor.added and AC changes. That can move the internal output, break fractional scaling, or change an external output's mode when the internal panel is disabled. This project does not edit it.

Small recommended change there: remove the fallback to `monitors[1]` (return nil when no active internal connector is found), and change the refresh update to `hl.monitor({output=profile.name, mode=target_mode})`, omitting position and scale. Partial specs are supported by the installed Lua API. Keep its power polling and notifications. This prevents later power transitions from overriding the chosen geometry; the mod cannot prevent another module from changing runtime rules.

## Verification

Run `node tests/policy.test.cjs` for focused policy tests. `node tests/live.cjs` is an explicit opt-in real compositor test: it creates DM-SMOKE, tests Extend/Mirror/Extend/Laptop only/Extend, and removes it in finally. It never requests external-only or disables the physical panel. Do not run it with a real external monitor you need to retain, because Laptop only disables all external outputs.

See [VERIFICATION.md](VERIFICATION.md) for measured results and remaining hardware checks. [menu.png](menu.png) is a crop captured by grim from the actual installed composed shell with a temporary virtual external output.
