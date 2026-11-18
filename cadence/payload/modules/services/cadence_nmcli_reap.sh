#!/bin/sh
# Ambxst Cadence: end the `nmcli monitor` processes Ambxst's daemon leaves
# behind.
#
# The daemon starts one `nmcli monitor` per network subscriber and reads its
# output through a pipe. A reload restarts the daemon, which does not take
# that child with it: the monitor is handed to init, its pipe has no reader
# left, and because the daemon runs with SIGPIPE ignored (and the child
# inherits that) writing into the dead pipe does not end it either. One more
# stays behind per reload, until logout.
#
# Ended here are only processes that are all of:
#   - this user's, with the command line exactly `nmcli monitor`;
#   - handed to init / the user's systemd (their parent is gone);
#   - writing to a pipe no other process has open.
# A monitor someone else started and still reads -- a bar script, a terminal
# -- has a live parent or a reader, and is left alone. `--dry-run` only lists.
#
# Prints one line per process ended: `reaped <pid>`.
set -u

dry=0
[ "${1:-}" = "--dry-run" ] && dry=1

for pid in $(pgrep -u "$(id -u)" -x nmcli 2>/dev/null); do
    [ -r "/proc/$pid/cmdline" ] || continue
    [ "$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)" = "nmcli monitor " ] || continue

    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -n "$ppid" ] || continue
    if [ "$ppid" != 1 ]; then
        [ "$(ps -o comm= -p "$ppid" 2>/dev/null)" = "systemd" ] || continue
    fi

    out=$(readlink "/proc/$pid/fd/1" 2>/dev/null) || continue
    case "$out" in
        pipe:*) ;;
        *) continue ;;
    esac

    # Anyone else holding either end of that pipe? (Other users' processes
    # cannot be looked into; the orphan test above is what covers those.)
    others=$(ls -l /proc/[0-9]*/fd 2>/dev/null | awk -v want="-> $out" -v self="/proc/$pid/fd:" '
        /^\/proc\// { cur = $0; next }
        cur != self && index($0, want) { n++ }
        END { print n + 0 }')
    [ "$others" = 0 ] || continue

    if [ "$dry" = 1 ]; then
        echo "would reap $pid"
    elif kill "$pid" 2>/dev/null; then
        echo "reaped $pid"
    fi
done
exit 0
