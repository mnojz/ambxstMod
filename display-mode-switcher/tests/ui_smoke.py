"""Opt-in test of the installed UI. Requires a running shell and no external output."""
import json
import subprocess
import time


def run(*args):
    return subprocess.check_output(args, text=True)


def surfaces():
    layers = json.loads(run('hyprctl', 'layers', '-j'))
    return sum(layer['namespace'] == 'ambxst:displaymode'
               for monitor in layers.values() for layer in monitor['levels']['3'])


outputs = json.loads(run('hyprctl', 'monitors', 'all', '-j'))
if any(not monitor['name'].startswith(('eDP', 'LVDS', 'DSI')) for monitor in outputs):
    raise SystemExit('Disconnect external outputs before running this UI test.')
if surfaces():
    raise SystemExit('Close the chooser before running this UI test.')

run('/usr/local/bin/ambxst', 'run', 'displaymode')
time.sleep(0.2)
assert surfaces() == 1, 'Menu must open without an external display'
# Keep cycling for longer than the original timeout; there must be no gaps.
for _ in range(6):
    run('/usr/local/bin/ambxst', 'run', 'displaymode')
    time.sleep(0.25)
    assert surfaces() == 1, 'Rapid presses must preserve exactly one surface'
time.sleep(1.1)
assert surfaces() == 0, 'Menu must disappear after the last press'
print('Installed UI: no-external opening, continuous cycling, timeout PASS')
