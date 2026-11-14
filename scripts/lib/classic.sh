# Shared helpers for the AetherOS classic interface (Waybar/Rofi/SwayNC…).
# Sourced by scripts/bin/aether-*; never executed.
#
#   have <cmd>                 is a command on PATH
#   cstate_get <key> [default] read ~/.config/aether-shell/classic/state.conf
#   cstate_set <key> <value>   write it (atomic)
#   notify <summary> [body] [icon] [notify-send args…]
#   amenu <prompt> [rofi args…]  a themed rofi -dmenu reading stdin
#   need <cmd> <package>       exit with a desktop notification if <cmd> is missing
#   hypr_monitors              name width height scale focused, one monitor per line

# shellcheck shell=bash

# shellcheck disable=SC2034 # used by the scripts that source this file
CLASSIC_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Sibling helpers (aether-colors, aether-wall, …) are found even when
# ~/.local/bin isn't on PATH yet (first install, Waybar's minimal environment).
PATH="$CLASSIC_REPO/scripts/bin:$PATH"
CLASSIC_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/aether-shell/classic"
CLASSIC_STATE="$CLASSIC_DIR/state.conf"
# shellcheck disable=SC2034
CLASSIC_RUNTIME="${XDG_RUNTIME_DIR:-/tmp}/aether-classic-$(id -u)"
ROFI_THEMES="${XDG_CONFIG_HOME:-$HOME/.config}/rofi/themes"

have() { command -v "$1" >/dev/null 2>&1; }

cstate_get() {
    local v=""
    [ -f "$CLASSIC_STATE" ] && v="$(awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); val = $0 } END { print val }' "$CLASSIC_STATE")"
    printf '%s\n' "${v:-${2:-}}"
}

cstate_set() {
    local key="$1" value="$2" tmp
    case "$value" in *$'\n'*) echo "cstate_set: value for $key contains a newline" >&2; return 1 ;; esac
    mkdir -p "$CLASSIC_DIR"
    tmp="$(mktemp -p "$CLASSIC_DIR")"
    if [ -f "$CLASSIC_STATE" ]; then
        awk -F= -v k="$key" '$1 != k' "$CLASSIC_STATE" > "$tmp"
    else
        echo "# AetherOS classic interface state (written by aether-colors / aether-wall)" > "$tmp"
    fi
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
    mv "$tmp" "$CLASSIC_STATE"
}

notify() {
    local summary="$1" body="${2:-}" icon="${3:-}"
    shift $(( $# < 3 ? $# : 3 ))
    have notify-send || { printf '%s: %s\n' "$summary" "$body" >&2; return 0; }
    notify-send -a AetherOS ${icon:+-i "$icon"} "$@" "$summary" "$body" 2>/dev/null || true
}

need() {
    if ! have "$1"; then
        notify "$1 is not installed" "Install it with: sudo dnf install $2" dialog-warning -u critical
        echo "$1 is not installed (package: $2)" >&2
        exit 127
    fi
}

amenu() {
    local prompt="$1"; shift
    need rofi rofi-wayland
    rofi -dmenu -i -p "$prompt" -theme "$ROFI_THEMES/menu.rasi" "$@"
}

# One line per monitor: name width height scale focused(0/1) — logical size.
hypr_monitors() {
    hyprctl -j monitors 2>/dev/null | python3 -c 'import json, sys
for m in json.load(sys.stdin):
    s = float(m.get("scale") or 1)
    w, h = m["width"], m["height"]
    if m.get("transform", 0) % 2:
        w, h = h, w
    print(m["name"], round(w / s), round(h / s), s, int(bool(m.get("focused"))))'
}

in_hyprland() { [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && have hyprctl; }
