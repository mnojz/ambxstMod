#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ambxst_source=${AMBXST_SOURCE:-$HOME/.local/src/ambxst}
mods_config=${XDG_CONFIG_HOME:-$HOME/.config}/ambxst/mods.json
generations_root=${XDG_DATA_HOME:-$HOME/.local/share}/ambxst/mods/generations
tmp_dir=$(mktemp -d)
# py_compile and unittest both write __pycache__ next to the sources, so drop
# the caches on exit to keep the working tree free of build artifacts.
trap 'rm -rf "$tmp_dir"; find "$root" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null || true' EXIT

section() {
    printf '\n== %s ==\n' "$1"
}

section "Static syntax"
cd "$root"
python3 -m py_compile payload/scripts/ytd_helper.py payload/scripts/ytd_protocol.py
python3 -m json.tool ambxst.mod.json >/dev/null
bash -n scripts/install-desktop.sh
git diff --check -- . ':(exclude)patches/*.patch'
printf 'Python, JSON, shell, and diff checks passed.\n'

section "Unit tests"
python3 -B -m unittest discover -s tests -p 'test_*.py' -v
if ! command -v node >/dev/null 2>&1; then
    echo "node is required for the YtdHistory and YtdUrl JavaScript tests" >&2
    exit 1
fi
node --test tests/test_history.js
node --test tests/test_url.js

section "Patch applicability"
if [[ -d "$ambxst_source/.git" ]]; then
    git -C "$ambxst_source" apply --check --whitespace=error-all "$root/patches/bar.patch"
    printf 'Bar patch applies to %s.\n' "$ambxst_source"
else
    printf 'Skipped: Ambxst source checkout not found at %s.\n' "$ambxst_source"
fi

section "Installed generation"
if [[ ! -f "$mods_config" ]]; then
    echo "Ambxst mods state not found: $mods_config" >&2
    exit 1
fi
active_generation=$(python3 - "$mods_config" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle)["activeGeneration"])
PY
)
generation=$generations_root/$active_generation
[[ -f "$generation/shell.qml" ]] || {
    echo "Active generation not found: $generation" >&2
    exit 1
}
while read -r source_path target_path; do
    cmp "$root/$source_path" "$generation/$target_path"
done <<'MAP'
payload/modules/services/YtdService.qml modules/services/YtdService.qml
payload/modules/services/YtdI18n.qml modules/services/YtdI18n.qml
payload/modules/services/YtdHistory.js modules/services/YtdHistory.js
payload/modules/services/YtdUrl.js modules/services/YtdUrl.js
payload/modules/bar/YtdButton.qml modules/bar/YtdButton.qml
payload/scripts/ytd_helper.py modules/bar/ytd_helper.py
MAP
printf 'Active generation matches repository payload: %s.\n' "$active_generation"

smoke_log=$tmp_dir/smoke.log
set +e
timeout 10 qs -p "$generation/shell.qml" >"$smoke_log" 2>&1
smoke_status=$?
set -e
if [[ $smoke_status -ne 0 && $smoke_status -ne 124 ]]; then
    cat "$smoke_log" >&2
    echo "QuickShell smoke test exited unexpectedly: $smoke_status" >&2
    exit 1
fi
grep -q "Configuration Loaded" "$smoke_log"
if grep -q "Failed to load configuration" "$smoke_log"; then
    cat "$smoke_log" >&2
    exit 1
fi
printf 'Generated shell loaded successfully (timeout status %s is expected).\n' "$smoke_status"

section "Desktop integration"
desktop_entry=${XDG_DATA_HOME:-$HOME/.local/share}/applications/ytd-handler.desktop
if [[ -f "$desktop_entry" ]] && command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$desktop_entry"
fi
if command -v xdg-mime >/dev/null 2>&1; then
    handler=$(xdg-mime query default x-scheme-handler/ytd)
    [[ "$handler" == "ytd-handler.desktop" ]] || {
        echo "Unexpected ytd: handler: $handler" >&2
        exit 1
    }
fi
printf 'Desktop protocol integration is valid.\n'

printf '\nAll Ambxst YTD checks passed.\n'
