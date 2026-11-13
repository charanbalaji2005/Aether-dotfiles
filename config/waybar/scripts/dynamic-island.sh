#!/usr/bin/bash
# dynamic-island.sh — run the Dynamic Island (a Quickshell layer at the top centre).
#
#   dynamic-island.sh start | stop | restart | status
#   dynamic-island.sh toggle | expand | collapse | peek    (open/close the island)
#   dynamic-island.sh info                                 its current state (JSON)
#   dynamic-island.sh log                                  follow its log
#
# Waybar draws the rest of the bar; the island is Quickshell because Waybar
# cannot animate its own size, draw a seekable progress bar or a live waveform.
# Its config is ~/.config/quickshell/island/shell.qml. aether-waybar starts and
# stops it together with Waybar for looks that have an island (islands/NAME.jsonc)
# when island_engine is "quickshell" (the default; "waybar" keeps the old island).
# Only one island runs per session (qs --no-duplicate).
set -uo pipefail

CFG="island"
QS="$(command -v qs || command -v quickshell || true)"
SHELL_QML="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/$CFG/shell.qml"

running() { [ -n "$QS" ] && "$QS" list -c "$CFG" 2>/dev/null | grep -q '^Instance'; }

start() {
    [ -n "$QS" ] || { echo "dynamic-island: Quickshell is not installed" >&2; return 127; }
    [ -f "$SHELL_QML" ] || { echo "dynamic-island: $SHELL_QML not found" >&2; return 1; }
    running && return 0
    "$QS" -n -d -c "$CFG" --log-rules 'qt.qpa.wayland.textinput.warning=false' >/dev/null 2>&1
}

stop() {
    [ -n "$QS" ] || return 0
    "$QS" kill -c "$CFG" >/dev/null 2>&1 || true
    local _i; for _i in $(seq 1 20); do running || return 0; sleep 0.1; done
    pkill -f -- "-c $CFG( |$)" 2>/dev/null || true
}

ipc() { running && "$QS" ipc -c "$CFG" call island "$1" 2>/dev/null; }

case "${1:-}" in
    start) start ;;
    stop) stop ;;
    restart) stop; start ;;
    status) if running; then echo running; else echo stopped; exit 1; fi ;;
    toggle|expand|collapse|peek) ipc "$1" >/dev/null ;;
    info) ipc info ;;
    log) [ -n "$QS" ] && exec "$QS" log -c "$CFG" -f ;;
    *) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
