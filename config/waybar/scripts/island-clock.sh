#!/usr/bin/bash
# island-clock.sh — Waybar's date and time, placed around the Dynamic Island.
#
#   island-clock.sh center   shown in the bar's centre when the island is off
#   island-clock.sh side     shown beside the tray when the island is on
#
# Follows Settings → Island → Dynamic Island (island=on|off in the classic
# state file): on, the centre belongs to the island and the date and time sit
# on the right; off (or the island not running), they are in the centre. A
# custom module with empty text is hidden by Waybar. Event-driven: wakes on a
# settings change, at each minute, and at least every 10 s.
set -uo pipefail

WHERE="${1:-center}"
CSTATE="${XDG_CONFIG_HOME:-$HOME/.config}/aether-shell/classic/state.conf"

fmt() {  # follows aether-settings → Island → 24-hour clock
    if grep -qx 'island_clock=12' "$CSTATE" 2>/dev/null; then echo '%a %d %b  %-I:%M %p'
    else echo '%a %d %b  %H:%M'; fi
}
island_up() { pgrep -f -- "^[^ ]*qs .*-c island( |$)" >/dev/null 2>&1; }

last=""
while true; do
    on=0
    grep -qx 'island=off' "$CSTATE" 2>/dev/null || { island_up && on=1; }
    if { [ "$WHERE" = center ] && [ "$on" = 0 ]; } || { [ "$WHERE" = side ] && [ "$on" = 1 ]; }; then
        printf -v now "%($(fmt))T" -1
        printf -v tip '%(%A, %d %B %Y)T' -1
        line="{\"text\": \"$now\", \"class\": \"shown\", \"tooltip\": \"$tip\"}"
    else
        line='{"text": "", "class": "hidden"}'
    fi
    [ "$line" != "$last" ] && { printf '%s\n' "$line"; last="$line"; }
    # Wake on a settings change, at the next minute, or after 10 s at most
    # (also notices the island starting or stopping).
    printf -v sec '%(%S)T' -1
    wait_s=$((61 - 10#$sec)); [ "$wait_s" -gt 10 ] && wait_s=10
    inotifywait -qq -t "$wait_s" -e close_write,moved_to,create "$(dirname "$CSTATE")" >/dev/null 2>&1
    [ $? -eq 1 ] && sleep 1   # inotifywait missing or failing: poll gently
done
