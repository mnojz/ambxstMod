#!/usr/bin/env bash
# Lays out both fixed farewell messages and one long stress case
# the real FarewellQuote.qml at 14 screen sizes and 4 fonts, headless, and
# fails unless each one is a single line, inside the line width, not elided.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); pkg=$(cd "$here/../.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cp "$here/harness.qml" "$pkg/payload/modules/notch/FarewellQuote.qml" "$tmp/"
python3 - "$pkg/payload/modules/services/ShellFarewell.qml" "$tmp/quotes.json" <<'PY'
import re, json, sys
s = open(sys.argv[1]).read()
q = [{"text": message} for message in re.findall(r'readonly property string (?:shutdownMessage|rebootMessage): "([^"]+)"', s)]
assert len(q) == 2, "Expected the two fixed farewell messages"
q.append({"text": "A line longer than either fixed message to exercise fitting on a narrow display, even with a wide font and a much larger starting text size than the screen can accommodate."})
json.dump(q, open(sys.argv[2], "w"))
PY
qml=$(command -v qml6 || command -v qml || echo /usr/lib/qt6/bin/qml)
out=$(QT_FORCE_STDERR_LOGGING=1 QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen timeout 120 "$qml" "$tmp/harness.qml" 2>&1 | sed 's/^qml: //')
echo "$out" | grep -v '^  custom'
echo "$out" | grep -q '^ALL ONE LINE, NONE ELIDED$'
