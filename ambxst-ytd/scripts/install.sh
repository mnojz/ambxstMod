#!/usr/bin/env bash
set -euo pipefail

mod_url=https://github.com/mnojz/ambxstMod/tree/main/ambxst-ytd
raw_url=https://raw.githubusercontent.com/mnojz/ambxstMod/main/ambxst-ytd

trap 'printf "\nSetup stopped. Fix the error above, then run the installer again.\n" >&2' ERR

if ((EUID == 0)); then
    printf 'Run this installer as your normal desktop user, without sudo.\n' >&2
    exit 1
fi

# Package names differ by distribution. Ambxst itself must already be set up.
ID= ID_LIKE=
if [[ -r /etc/os-release ]]; then
    source /etc/os-release
fi
family=unsupported
case " $ID $ID_LIKE " in
    *" arch "*) family=arch ;;
    *" debian "*|*" ubuntu "*) family=debian ;;
esac

package_for() {
    case "$1" in
        python3) [[ "$family" == arch ]] && printf python || printf python3 ;;
        yt_dlp|yt-dlp) printf yt-dlp ;;
        wl-paste) printf wl-clipboard ;;
        xdg-open|xdg-mime) printf xdg-utils ;;
        gio) [[ "$family" == arch ]] && printf glib2 || printf libglib2.0-bin ;;
        install|mktemp) printf coreutils ;;
        *) printf '%s' "$1" ;;
    esac
}

available() {
    if [[ "$1" == yt_dlp ]]; then
        command -v python3 >/dev/null 2>&1 && python3 -c 'import yt_dlp' >/dev/null 2>&1
    else
        command -v "$1" >/dev/null 2>&1
    fi
}

requirements=(ambxst qs python3 yt_dlp yt-dlp ffmpeg wl-paste xdg-open bash gio xdg-mime curl install mktemp)
check_requirements() {
    missing=()
    printf '\n%-35s %s\n' 'Required package / tool' 'Status'
    for tool in "${requirements[@]}"; do
        label=$(package_for "$tool")
        [[ "$tool" == yt_dlp ]] && label='yt-dlp (Python module)'
        if available "$tool"; then
            printf '[OK] %-30s Installed\n' "$label ($tool)"
        else
            printf '[--] %-30s Not installed\n' "$label ($tool)"
            missing+=("$tool")
        fi
    done
}

check_requirements
for tool in "${missing[@]}"; do
    if [[ "$tool" == ambxst || "$tool" == qs ]]; then
        printf '\nSet up Ambxst and QuickShell first, then rerun this installer.\n' >&2
        exit 1
    fi
done

if ((${#missing[@]})); then
    case "$family" in
        arch) manager=(pacman -S --needed) ;;
        debian) manager=(apt-get install) ;;
        *)
            printf '\nAutomatic package installation supports Arch, Debian, Ubuntu, and their derivatives.\n' >&2
            printf 'On this distribution, install the missing tools listed above, then retry.\n' >&2
            exit 1 ;;
    esac
    if ! command -v "${manager[0]}" >/dev/null 2>&1 || ! command -v sudo >/dev/null 2>&1; then
        printf 'Package installation requires %s and sudo.\n' "${manager[0]}" >&2
        exit 1
    fi
    packages=()
    for tool in "${missing[@]}"; do
        package=$(package_for "$tool")
        duplicate=false
        for existing in "${packages[@]}"; do
            [[ "$existing" != "$package" ]] || duplicate=true
        done
        "$duplicate" || packages+=("$package")
    done
    printf '\nPackages to install: %s\n' "${packages[*]}"
    printf 'Command:'
    printf ' %q' sudo "${manager[@]}" "${packages[@]}"
    printf '\nInstall these required packages and continue? [y/N] '
    answer=
    read -r answer || true
    case "$answer" in
        y|Y|yes|YES) ;;
        *) printf 'Cancelled. No packages or YTD files were installed.\n'; exit 0 ;;
    esac
    sudo "${manager[@]}" "${packages[@]}"
    hash -r
    printf '\nChecking requirements again…\n'
    check_requirements
    if ((${#missing[@]})); then
        printf '\nSome requirements are still unavailable. Setup stopped.\n' >&2
        printf 'If yt_dlp is missing, check whether python3 uses a custom Python environment.\n' >&2
        exit 1
    fi
fi

setup_dir=$(mktemp -d)
trap 'rm -rf -- "$setup_dir"' EXIT

printf 'Downloading desktop integration…\n'
for file in payload/scripts/ytd_protocol.py payload/assets/ytd.svg; do
    curl --fail --silent --show-error --location --retry 3 \
        --connect-timeout 15 --max-time 120 \
        "$raw_url/$file" -o "$setup_dir/${file##*/}"
done

printf 'Installing Ambxst YTD…\n'
ambxst mods install "$mod_url"

printf 'Setting up desktop links…\n'
data_dir=${XDG_DATA_HOME:-$HOME/.local/share}
bridge_path=$HOME/.local/bin/ytd.py
icon_path=$data_dir/icons/ytd.svg
desktop_path=$data_dir/applications/ytd-handler.desktop
install -d -m 0755 "$HOME/.local/bin" "$data_dir/icons" "$data_dir/applications"
install -m 0755 "$setup_dir/ytd_protocol.py" "$bridge_path"
install -m 0644 "$setup_dir/ytd.svg" "$icon_path"
python3 - "$bridge_path" "$icon_path" "$setup_dir/ytd-handler.desktop" <<'DESKTOP'
from pathlib import Path
import sys

bridge, icon, output = sys.argv[1:]
# Desktop entries have their own escaping rules, distinct from shell quoting.
def desktop_value(value):
    return value.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")

def exec_argument(value):
    value = value.replace("%", "%%")
    for char in ('\\', '"', '`', '$'):
        value = value.replace(char, "\\" + char)
    return desktop_value('"' + value + '"')

Path(output).write_text(
    "[Desktop Entry]\nName=YTD\nType=Application\n"
    + "Exec=/usr/bin/env python3 " + exec_argument(bridge) + " %u\n"
    + "StartupNotify=false\nMimeType=x-scheme-handler/ytd;\n"
    + "Icon=" + desktop_value(icon) + "\n",
    encoding="utf-8",
)
DESKTOP
install -m 0644 "$setup_dir/ytd-handler.desktop" "$desktop_path"
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$data_dir/applications"
fi
xdg-mime default ytd-handler.desktop x-scheme-handler/ytd
handler=$(xdg-mime query default x-scheme-handler/ytd)
if [[ "$handler" != ytd-handler.desktop ]]; then
    printf 'Could not register ytd: links. Run the installer again from your desktop session.\n' >&2
    exit 1
fi

printf 'Enabling the mod…\n'
ambxst mods enable mnojz.ambxstytd
printf 'Reloading Ambxst…\n'
ambxst reload

printf '\nAmbxst YTD is ready. Click the YTD button in your bar to start.\n'
