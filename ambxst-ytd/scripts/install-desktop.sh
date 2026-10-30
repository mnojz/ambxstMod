#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
home=${HOME:?HOME must be set}
data_home=${XDG_DATA_HOME:-$home/.local/share}
applications_dir=$data_home/applications
icons_dir=$data_home/icons
bridge=$home/.local/bin/ytd.py
icon=$icons_dir/ytd.svg

install -d -m 0755 "$home/.local/bin" "$applications_dir" "$icons_dir"
install -m 0755 "$project_dir/payload/scripts/ytd_protocol.py" "$bridge"
install -m 0644 "$project_dir/payload/assets/ytd.svg" "$icon"

desktop_tmp=$(mktemp)
trap 'rm -f "$desktop_tmp"' EXIT
python3 - "$project_dir/ytd-handler.desktop" "$desktop_tmp" "$bridge" "$icon" <<'PY'
from pathlib import Path
import sys

template, output, bridge, icon = map(Path, sys.argv[1:])
# The template is part of the project; only the two placeholders are dynamic.
text = template.read_text(encoding="utf-8")
text = text.replace("@YTD_BRIDGE@", str(bridge)).replace("@YTD_ICON@", str(icon))
output.write_text(text, encoding="utf-8")
PY
install -m 0644 "$desktop_tmp" "$applications_dir/ytd-handler.desktop"

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$applications_dir"
fi
if command -v xdg-mime >/dev/null 2>&1; then
    xdg-mime default ytd-handler.desktop x-scheme-handler/ytd
fi

printf 'Installed protocol bridge: %s\n' "$bridge"
printf 'Installed desktop entry:  %s\n' "$applications_dir/ytd-handler.desktop"
printf 'Installed icon:           %s\n' "$icon"
