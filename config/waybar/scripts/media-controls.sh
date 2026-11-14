#!/usr/bin/bash
# media-controls.sh — playerctl with a sensible choice of player.
#
#   media-controls.sh play-pause | play | pause | next | previous | stop
#   media-controls.sh seek +10 | -10      seconds, relative
#   media-controls.sh player              the chosen player's name
#   media-controls.sh status              Playing | Paused | Stopped (empty: no player)
#   media-controls.sh meta FORMAT         playerctl metadata --format FORMAT
#   media-controls.sh raise               focus the player's window (if it supports it)
#
# Plain `playerctl` controls the first player it finds, so a paused browser tab
# can swallow the play key while Spotify is the one you are listening to. This
# picks the player that is playing, else the one that played last, else the
# first paused one. Works with Spotify, Firefox, Chromium, VLC, mpv and any
# other MPRIS player.
set -uo pipefail

command -v playerctl >/dev/null || { echo "playerctl is not installed (sudo dnf install playerctl)" >&2; exit 127; }

LAST="${XDG_RUNTIME_DIR:-/tmp}/island-media-last-player"

pick() {
    local p st paused="" last=""
    [ -s "$LAST" ] && last="$(cat "$LAST")"
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        st="$(playerctl -p "$p" status 2>/dev/null)"
        case "$st" in
            Playing) printf '%s\n' "$p" > "$LAST"; echo "$p"; return 0 ;;
            Paused) if [ "$p" = "$last" ]; then paused="$p"; elif [ -z "$paused" ]; then paused="$p"; fi ;;
        esac
    done < <(playerctl -l 2>/dev/null)
    [ -n "$paused" ] && echo "$paused"
}

p="$(pick)"
cmd="${1:-}"
case "$cmd" in
    player) echo "$p" ;;
    status) [ -n "$p" ] && playerctl -p "$p" status 2>/dev/null ;;
    meta)
        fmt="${2:-}"; [ -n "$fmt" ] || fmt='{{ artist }} - {{ title }}'
        [ -n "$p" ] && playerctl -p "$p" metadata --format "$fmt" 2>/dev/null ;;
    play-pause|play|pause|next|previous|stop)
        [ -n "$p" ] || exit 0
        playerctl -p "$p" "$cmd" ;;
    seek)
        [ -n "$p" ] || exit 0
        d="${2:-+10}"
        case "$d" in -*) playerctl -p "$p" position "${d#-}-" ;; *) playerctl -p "$p" position "${d#+}+" ;; esac ;;
    raise)
        [ -n "$p" ] || exit 0
        busctl --user call "org.mpris.MediaPlayer2.$p" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2 Raise >/dev/null 2>&1 || true ;;
    *) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
