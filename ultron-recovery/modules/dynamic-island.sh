# shellcheck shell=bash
# ULTRON RECOVERY — Dynamic Island: playerctl / MPRIS, media control and
# artwork scripts, the Quickshell island config, its artwork cache, whether it
# runs when enabled.

ISLAND_QML="$HOME/.config/quickshell/island/shell.qml"
ISLAND_SCRIPTS="$HOME/.config/waybar/scripts"
ISLAND_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/aether/island"
ISLAND_SCRIPT_LIST=(dynamic-island.sh media-controls.sh media-artwork.sh island-clock.sh lock-island.sh)

mod_island_paths() { printf '%s\n' "$HOME/.config/quickshell/island" "$ISLAND_SCRIPTS"; }
mod_island_deps()  { printf '%s\n' "playerctl:playerctl" "magick:ImageMagick" "curl:curl" "inotifywait:inotify-tools" "cava:cava" "qs:quickshell"; }

island_enabled() { ! grep -qx 'island=off' "$HOME/.config/aether-shell/classic/state.conf" 2>/dev/null; }
island_running() { pgrep -f -- '^[^ ]*qs .*-c island( |$)' >/dev/null 2>&1; }

mod_island_check() {
    local p0=${#UR_PROBLEMS[@]} s out players
    command -v playerctl >/dev/null 2>&1 || problem island "playerctl is not installed (sudo dnf install playerctl) — no media info"
    command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1 || problem island "ImageMagick missing — album art can't be cached or drawn on the lock screen"
    command -v inotifywait >/dev/null 2>&1 || problem island "inotify-tools missing — recording detection and the bar clock fall back to polling"
    if command -v playerctl >/dev/null 2>&1; then
        players="$(playerctl -l 2>/dev/null | tr '\n' ' ')"
        ui_info "MPRIS players: ${players:-none running}"
    fi
    if [ -L "$HOME/.config/quickshell/island" ] && [ ! -e "$HOME/.config/quickshell/island" ]; then problem island "island config link is broken"
    elif [ ! -f "$ISLAND_QML" ]; then problem island "island config ~/.config/quickshell/island/shell.qml is missing"
    else out="$(validate_qml "$ISLAND_QML" 2>&1)" || problem island "island QML syntax: $out"; fi
    for s in "${ISLAND_SCRIPT_LIST[@]}"; do
        if [ ! -f "$ISLAND_SCRIPTS/$s" ]; then problem island "script missing: $s"
        elif [ ! -x "$ISLAND_SCRIPTS/$s" ]; then problem island "script not executable: $ISLAND_SCRIPTS/$s"
        else out="$(validate_shell "$ISLAND_SCRIPTS/$s" 2>&1)" || problem island "script syntax error: $s"; fi
    done
    if [ -d "$ISLAND_CACHE" ]; then
        [ -w "$ISLAND_CACHE" ] || problem island "artwork cache not writable: $ISLAND_CACHE"
        local bad; bad="$(find "$ISLAND_CACHE" -maxdepth 2 -name '*.png' -size 0 2>/dev/null | wc -l)"
        [ "$bad" -gt 0 ] && problem island "$bad empty (corrupt) artwork file(s) in the cache"
    fi
    if det_hypr_running && island_enabled && grep -qs '^look=home' "$HOME/.config/aether-shell/classic/state.conf"; then
        island_running || problem island "the Dynamic Island is enabled but not running"
    fi
    [ "${#UR_PROBLEMS[@]}" -eq "$p0" ] && check_ok "Dynamic Island: playerctl, scripts, config and cache OK"
    return 0
}

mod_island_repair() {
    mkdir -p "$HOME/.config/quickshell" 2>/dev/null || true
    repair_link "$HOME/.config/quickshell/island" config/quickshell/island
    repair_deleted_tracked config/quickshell/island
    repair_deleted_tracked config/waybar/scripts
    local s
    for s in "${ISLAND_SCRIPT_LIST[@]}"; do
        [ -f "$ISLAND_SCRIPTS/$s" ] && [ ! -x "$ISLAND_SCRIPTS/$s" ] && change "make $s executable" chmod u+x -- "$ISLAND_SCRIPTS/$s"
    done
    if [ -d "$ISLAND_CACHE" ] && [ -n "$(find "$ISLAND_CACHE" -maxdepth 2 -name '*.png' -size 0 2>/dev/null)" ]; then
        change "remove empty artwork files from the cache (they are re-downloaded)" find "$ISLAND_CACHE" -maxdepth 2 -name '*.png' -size 0 -delete
    fi
    repair_full_restore island config/quickshell/island config/waybar/scripts
    if det_hypr_running && island_enabled && grep -qs '^look=home' "$HOME/.config/aether-shell/classic/state.conf" && ! island_running; then
        restart_component island
    fi
}
