# Shared helpers for the AetherOS install scripts. Sourced, never executed.
#
#   aether_targets      every path under $HOME that AetherOS links/owns
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

# Paths relative to $HOME, one per line. Helpers and systemd units are
# enumerated from the repository so a new one is picked up everywhere.
aether_targets_rel() {
    local f
    cat <<'LIST'
.config/hypr
.config/quickshell/aether-shell
.config/kitty
.zshrc
.config/gtk-3.0/settings.ini
.config/gtk-3.0/gtk.css
.config/gtk-4.0/settings.ini
.config/gtk-4.0/gtk.css
.config/aether-shell/wallpapers
LIST
    for f in "$AETHER_COMMON_REPO"/system/systemd/*.service "$AETHER_COMMON_REPO"/system/systemd/*.timer; do
        [ -f "$f" ] && echo ".config/systemd/user/$(basename "$f")"
    done
    for f in "$AETHER_COMMON_REPO"/scripts/bin/*; do
        [ -f "$f" ] && echo ".local/bin/$(basename "$f")"
    done
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
