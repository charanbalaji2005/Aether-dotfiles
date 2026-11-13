# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# functions/components.sh — what can be installed. Sourced, never executed.
#
# One table is the single definition of every component:
#   id | interfaces | recommended | link groups | label
#     interfaces   classic, aether or both (classic = Waybar/Rofi desktop,
#                  aether = the Quickshell shell)
#     recommended  1: part of the Recommended preset
#     link groups  what setup-symlinks.sh --only deploys (scripts/lib/common.sh), - for none
# Packages per component: packages/fedora/components.tsv.
# Install/validate steps per component: install-scripts/<id>.sh, which may
# define comp_<id>_install and comp_<id>_validate (dashes become underscores).

AETHER_COMPONENTS='hyprland|both|1|hypr|Hyprland configuration — keys, rules, animations, idle and lock
waybar|classic|1|waybar|Waybar — macOS-inspired top bar
dynamic-island|classic|1|island|Dynamic Island — music player in the bar (Quickshell)
dock|classic|1|-|macOS Dock — magnifying dock with running-app dots
rofi|classic|1|rofi|Rofi Launchpad — apps, Wi-Fi, Bluetooth, clipboard and emoji menus
aether-shell|aether|1|shell-aether|Aether shell — the Quickshell desktop (panel, dock, island, centre)
terminal|both|1|kitty,tmux|Kitty terminal — themed from your wallpaper, with tmux
shell|both|1|zsh,bash|Zsh and shell configuration
themes|both|1|gtk|GTK themes and icons (adw-gtk3, Papirus)
wallpapers|both|1|wallpapers|Wallpapers — 22 bundled; your own are kept
fonts|both|1|-|Fonts — JetBrains Mono, Noto, Nerd Font icons
notifications|classic|1|swaync|Notifications — SwayNC centre and popups
bluetooth|both|1|-|Bluetooth — BlueZ and Blueman
audio|both|1|-|Audio — PipeWire, WirePlumber, volume and media keys
login-manager|both|0|-|Login manager theme — SDDM only (GDM is left alone)
apps|both|1|wlogout,wallust,fastfetch|Application configs — power menu, colours, fastfetch, files'

comp__row() { awk -F'|' -v id="$1" '$1 == id' <<< "$AETHER_COMPONENTS"; }
comp_exists() { [ -n "$(comp__row "$1")" ]; }
comp_label() { comp__row "$1" | cut -d'|' -f5; }
# The step name: "Installing <short label>" (the label up to its dash).
comp_step() { echo "Installing $(comp_label "$1" | sed 's/ — .*//')"; }
comp_groups() { comp__row "$1" | cut -d'|' -f4 | tr ',' ' ' | sed 's/^-$//'; }
comp_fn() {  # comp_fn ID HOOK -> function name, if that hook is defined
    local f="comp_${1//-/_}_$2"
    declare -F "$f" >/dev/null && echo "$f"
    return 0
}

# comp_list IFACE: every component available for that interface, in install order.
comp_list() {
    awk -F'|' -v i="$1" '$2 == "both" || $2 == i {print $1}' <<< "$AETHER_COMPONENTS"
}

# comp_preset NAME IFACE: recommended | all | minimal | none
comp_preset() {
    case "$1" in
        recommended) awk -F'|' -v i="$2" '($2 == "both" || $2 == i) && $3 == 1 {print $1}' <<< "$AETHER_COMPONENTS" ;;
        all) comp_list "$2" ;;
        minimal)
            if [ "$2" = aether ]; then printf '%s\n' hyprland aether-shell terminal shell fonts
            else printf '%s\n' hyprland waybar rofi notifications terminal shell fonts; fi ;;
        none) ;;
        *) return 1 ;;
    esac
}

# comp_normalize IFACE "a,b c": validated, de-duplicated, in install order.
# Unknown or interface-incompatible IDs are reported on stderr and fail.
comp_normalize() {
    local iface="$1" want=" ${2//,/ } " id bad="" out=()
    for id in $want; do
        comp_exists "$id" || { bad+=" $id"; continue; }
        comp_list "$iface" | grep -x "$id" >/dev/null || bad+=" $id(not for the $iface interface)"
    done
    [ -z "$bad" ] || { echo "Unknown component(s):$bad. Known: $(comp_list "$iface" | tr '\n' ' ')" >&2; return 1; }
    while IFS= read -r id; do [[ "$want" == *" $id "* ]] && out+=("$id"); done < <(comp_list "$iface")
    echo "${out[*]}"
}

# comp_packages ID: the package specs it needs ("a|b" alternatives, "?" optional).
comp_packages() {
    awk -F'\t' -v id="$1" '$0 !~ /^[[:space:]]*#/ && $1 == id {print $2}' "$REPO_DIR/packages/fedora/components.tsv"
}

# The selection saved by the last install (for updates and the menu).
comp_saved_file() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/aether-shell/components"; }
comp_saved() { cat "$(comp_saved_file)" 2>/dev/null || true; }
