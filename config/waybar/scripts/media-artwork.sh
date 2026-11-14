#!/usr/bin/bash
# media-artwork.sh — cache MPRIS album art locally and print the cached path.
#
#   media-artwork.sh URL      print a local 256×256 PNG for URL (nothing if none)
#   media-artwork.sh          the art of the current player (via media-controls.sh)
#   media-artwork.sh prune    keep only the newest $KEEP cached images
#
# URLs come from mpris:artUrl: https:// (Spotify), file:// (Firefox, Chromium,
# VLC write temporary files) or data: (base64). Each image is downloaded and
# scaled once; later calls are a cache hit. file:// art is keyed by path, size
# and mtime because browsers reuse the same temp file name for new tracks.
# Used by the Dynamic Island (~/.config/quickshell/island).
set -uo pipefail

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/aether/island/art"
KEEP=150
mkdir -p "$CACHE"

prune() {
    find "$CACHE" -maxdepth 1 -type f -name '*.png' -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | tail -n +"$((KEEP + 1))" | cut -d' ' -f2- | xargs -r rm -f
    find "$CACHE" -maxdepth 1 -type f -name '.*' -mmin +10 -delete 2>/dev/null
}

url="${1:-}"
[ "$url" = prune ] && { prune; exit 0; }
if [ -z "$url" ]; then
    url="$("$(dirname "$(readlink -f "$0")")/media-controls.sh" meta '{{ mpris:artUrl }}' 2>/dev/null)"
fi
[ -n "$url" ] || exit 0

case "$url" in
    file://*)
        src="$(python3 -I -c 'import sys, urllib.parse; print(urllib.parse.unquote(urllib.parse.urlparse(sys.argv[1]).path))' "$url")"
        [ -f "$src" ] || exit 0
        key="$(printf '%s|%s' "$url" "$(stat -c '%s.%Y' "$src")" | md5sum | cut -c1-20)" ;;
    http://*|https://*|data:*)
        key="$(printf '%s' "$url" | md5sum | cut -c1-20)" ;;
    *) exit 0 ;;
esac

out="$CACHE/$key.png"
if [ -s "$out" ]; then echo "$out"; exit 0; fi

# One fetch per image even when several callers ask at once.
exec 9>"$CACHE/.$key.lock"
flock -w 10 9 || exit 0
if [ -s "$out" ]; then echo "$out"; exit 0; fi

tmp="$(mktemp -p "$CACHE" .dl.XXXXXX)"
trap 'rm -f "$tmp"' EXIT
case "$url" in
    file://*) cp -f "$src" "$tmp" ;;
    data:*) printf '%s' "${url#*,}" | base64 -d > "$tmp" 2>/dev/null ;;
    *) curl -fsSL --max-time 8 --max-filesize 15000000 -o "$tmp" "$url" 2>/dev/null ;;
esac
[ -s "$tmp" ] || exit 0

im="$(command -v magick || command -v convert || true)"
if [ -n "$im" ]; then
    "$im" "${tmp}[0]" -auto-orient -thumbnail '256x256^' -gravity center -extent 256x256 \
        -strip "PNG32:$out.part" 2>/dev/null && mv -f "$out.part" "$out"
    rm -f "$out.part"
else
    cp -f "$tmp" "$out"   # Qt scales it; only the cache step is lost
fi
[ -s "$out" ] && echo "$out"
# Prune now and then rather than on every call.
[ $((RANDOM % 20)) -eq 0 ] && prune
exit 0
