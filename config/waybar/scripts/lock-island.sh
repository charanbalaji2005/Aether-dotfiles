#!/usr/bin/bash
# lock-island.sh — the Dynamic Island on the lock screen (hyprlock).
#
# Hyprlock cannot host other programs' windows (the Wayland session lock forbids
# it, by design), so the island there is a picture: this script renders the
# current track — black capsule, album art, title, artist, playing/paused mark —
# to a PNG and prints its path. hyprlock.conf shows it with an image widget that
# re-runs this every 2 s. Nothing playing: a transparent pixel (island hidden).
# Renders only when the track or play state changes; otherwise a cache hit.
set -uo pipefail

DIR="${XDG_CACHE_HOME:-$HOME/.cache}/aether/island"
HERE="$(dirname "$(readlink -f "$0")")"
mkdir -p "$DIR"
EMPTY="$DIR/lock-empty.png"
[ -s "$EMPTY" ] || magick -size 2x2 xc:none "PNG32:$EMPTY" 2>/dev/null

ctl() { "$HERE/media-controls.sh" "$@" 2>/dev/null; }

status="$(ctl status)"
case "$status" in Playing|Paused) ;; *) echo "$EMPTY"; exit 0 ;; esac
title="$(ctl meta '{{ title }}')"
[ -n "$title" ] || { echo "$EMPTY"; exit 0; }
artist="$(ctl meta '{{ artist }}')"
art="$("$HERE/media-artwork.sh" "$(ctl meta '{{ mpris:artUrl }}')")"

key="$(printf '%s|%s|%s|%s' "$status" "$title" "$artist" "$art" | md5sum | cut -c1-16)"
out="$DIR/lock-$key.png"
if [ -s "$out" ]; then echo "$out"; exit 0; fi

clip() { local s="$1" n="$2"; [ "${#s}" -gt "$n" ] && s="${s:0:$((n - 1))}…"; printf '%s' "$s"; }
# Drawn at 2× (840×128) and shown at 420×64 for crisp text.
W=840 H=128
args=(-size "${W}x${H}" xc:none -fill '#030304' -draw "roundrectangle 0,0 $((W - 1)),$((H - 1)) 64,64")
if [ -n "$art" ] && [ -s "$art" ]; then
    args+=( \( "$art" -resize 96x96^ -gravity center -extent 96x96 \
        \( -size 96x96 xc:none -fill white -draw 'roundrectangle 0,0 95,95 22,22' \) \
        -compose CopyOpacity -composite \) -gravity NorthWest -geometry +16+16 -compose Over -composite )
else
    args+=(-fill '#1c1c1f' -draw 'roundrectangle 16,16 111,111 22,22')
fi
args+=(-gravity NorthWest
    -font Noto-Sans-SemiBold -pointsize 28 -fill '#f5f5f7' -annotate +136+26 "$(clip "$title" 34)"
    -font Noto-Sans-Regular -pointsize 23 -fill '#f5f5f799' -annotate +136+70 "$(clip "$artist" 40)")
if [ "$status" = Playing ]; then   # a still waveform
    x=748; for h in 20 34 48 48 34 20; do
        args+=(-fill '#0a84ff' -draw "roundrectangle $x,$((64 - h / 2)) $((x + 7)),$((64 + h / 2)) 4,4"); x=$((x + 13))
    done
else                                # pause bars
    args+=(-fill '#f5f5f799' -draw 'roundrectangle 770,46 779,82 3,3' -draw 'roundrectangle 790,46 799,82 3,3')
fi

if magick "${args[@]}" "PNG32:$out.part" 2>/dev/null && mv -f "$out.part" "$out"; then
    find "$DIR" -maxdepth 1 -name 'lock-*.png' ! -name "lock-$key.png" ! -name 'lock-empty.png' -mmin +1 -delete 2>/dev/null
    echo "$out"
else
    rm -f "$out.part"; echo "$EMPTY"
fi
