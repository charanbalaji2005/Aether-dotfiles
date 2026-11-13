# Shared helpers for the AetherOS install scripts. Sourced, never executed.
#
#   aether_targets      every path under $HOME that AetherOS links/owns
#   aether_group_targets_rel GROUP   the paths of one link group (partial installs)
#   aether_state_dir    ~/.local/state/aether (logs, manifest, install state)
#   manifest_add        append a record to the install manifest
#
# The target list is the single definition used by setup-symlinks.sh,
# backup.sh, uninstall.sh and restore.sh — previously each kept its own copy
# and they had drifted apart.

# shellcheck shell=bash

AETHER_COMMON_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

aether_state_dir() {
    echo "${XDG_STATE_HOME:-$HOME/.local/state}/aether"
}

aether_manifest() {
    echo "$(aether_state_dir)/manifest.tsv"
}

# Link groups: the unit a partial install deploys. Every component of the
# installer (functions/components.sh) maps onto one or more of these.
AETHER_LINK_GROUPS="bin systemd hypr shell-aether island kitty tmux zsh bash waybar rofi swaync wlogout wallust fastfetch gtk wallpapers"

# aether_group_targets_rel GROUP: the paths (relative to $HOME) a group owns.
# Helpers and systemd units are enumerated from the repository so a new one
# is picked up everywhere.
aether_group_targets_rel() {
    local f
    case "$1" in
        hypr) echo ".config/hypr" ;;
        shell-aether) echo ".config/quickshell/aether-shell" ;;
        island) echo ".config/quickshell/island" ;;
        kitty|tmux|waybar|rofi|swaync|wlogout|wallust|fastfetch) echo ".config/$1" ;;
        zsh) echo ".zshrc" ;;
        bash) echo ".bashrc.d/aether.bash" ;;
        gtk) printf '%s\n' .config/gtk-3.0/settings.ini .config/gtk-3.0/gtk.css .config/gtk-4.0/settings.ini .config/gtk-4.0/gtk.css ;;
        wallpapers) echo ".config/aether-shell/wallpapers" ;;
        systemd)
            for f in "$AETHER_COMMON_REPO"/system/systemd/*.service "$AETHER_COMMON_REPO"/system/systemd/*.timer; do
                [ -f "$f" ] && echo ".config/systemd/user/$(basename "$f")"
            done
            for f in "$AETHER_COMMON_REPO"/system/systemd/*.service.d/*.conf; do
                [ -f "$f" ] && echo ".config/systemd/user/$(basename "$(dirname "$f")")/$(basename "$f")"
            done ;;
        bin)
            for f in "$AETHER_COMMON_REPO"/scripts/bin/*; do
                [ -f "$f" ] && echo ".local/bin/$(basename "$f")"
            done ;;
        *) return 1 ;;
    esac
}

# Paths relative to $HOME, one per line: every group.
aether_targets_rel() {
    local g
    for g in $AETHER_LINK_GROUPS; do aether_group_targets_rel "$g"; done
}

# The groups chosen at install time (setup-symlinks.sh --only records them),
# so an update or `aether repair` re-links exactly those. Empty: all groups.
aether_groups_file() {
    echo "${XDG_CONFIG_HOME:-$HOME/.config}/aether-shell/link-groups"
}

aether_targets() {
    local rel
    while IFS= read -r rel; do echo "$HOME/$rel"; done < <(aether_targets_rel)
}

# manifest_add <kind> <path> <detail>
#   link    <dest>  <source>       a symlink AetherOS created
#   backup  <dest>  <moved-to>     something that was in the way and was moved aside
#   file    <path>  -              a regular file AetherOS created
manifest_add() {
    local m
    m="$(aether_manifest)"
    mkdir -p "$(dirname "$m")"
    printf '%s\t%s\t%s\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$1" "$2" "$3" >> "$m"
}
