# shellcheck shell=bash
# ULTRON RECOVERY — Hyprland: config parse (Hyprland's own verifier), sourced
# files, autostart commands and duplicates, keybinding clashes, links, perms.

HYPR_DIR="$HOME/.config/hypr"

mod_hyprland_paths() { echo "$HYPR_DIR"; }
mod_hyprland_deps()  { printf '%s\n' "Hyprland:hyprland" "hyprctl:hyprland" "hyprlock:hyprlock" "hypridle:hypridle"; }

# Every config file reachable from hyprland.conf through `source =` (inside $HOME).
hypr_conf_files() {
    local -A seen=()
    local queue=("$HYPR_DIR/hyprland.conf") f line path
    while [ "${#queue[@]}" -gt 0 ]; do
        f="${queue[0]}"; queue=("${queue[@]:1}")
        [ -f "$f" ] && [ -z "${seen[$f]:-}" ] || continue
        seen[$f]=1; echo "$f"
        while IFS= read -r line; do
            path="$(sed -E 's/^[[:space:]]*source[[:space:]]*=[[:space:]]*//; s/[[:space:]]*(#.*)?$//' <<< "$line")"
            path="${path/#\~/$HOME}"; path="${path//\$HOME/$HOME}"
            case "$path" in *'*'*|'') continue ;; /*) ;; *) path="$HYPR_DIR/$path" ;; esac
            queue+=("$path")
        done < <(grep -E '^[[:space:]]*source[[:space:]]*=' "$f")
    done
}

# Sourced files that do not exist.
hypr_missing_sources() {
    local f line path
    while IFS= read -r f; do
        while IFS= read -r line; do
            path="$(sed -E 's/^[[:space:]]*source[[:space:]]*=[[:space:]]*//; s/[[:space:]]*(#.*)?$//' <<< "$line")"
            path="${path/#\~/$HOME}"; path="${path//\$HOME/$HOME}"
            case "$path" in *'*'*|'') continue ;; /*) ;; *) path="$HYPR_DIR/$path" ;; esac
            [ -e "$path" ] || echo "$path"
        done < <(grep -E '^[[:space:]]*source[[:space:]]*=' "$f")
    done < <(hypr_conf_files)
}

hypr_autostart() {  # every exec-once command, one per line
    local f
    while IFS= read -r f; do
        sed -nE 's/^[[:space:]]*exec-once[[:space:]]*=[[:space:]]*//p' "$f" | sed -E 's/[[:space:]]+#.*$//'
    done < <(hypr_conf_files)
}

hypr_bind_clashes() {  # same bind type + MODS + KEY in more than one file
    # (several binds for one key in the same file are a deliberate chain,
    # e.g. ALT+Tab → cyclenext + bringactivetotop)
    local f
    while IFS= read -r f; do
        sed -nE 's/^[[:space:]]*(bind[a-z]*)[[:space:]]*=[[:space:]]*([^,]*),[[:space:]]*([^,]*),.*/\1|\2|\3/p' "$f" \
            | awk -F'|' -v file="${f/#$HOME/\~}" '{ gsub(/[[:space:]]+/, " ", $2); m=tolower($2); k=tolower($3); gsub(/ /, "", k); print $1 " " m " + " k "|" file }'
    done < <(hypr_conf_files) | sort -u \
        | awk -F'|' '{ files[$1] = files[$1] (files[$1] ? ", " : "") $2; n[$1]++ } END { for (k in n) if (n[k] > 1) print k " (in " files[k] ")" }'
}

mod_hyprland_check() {
    local p0=${#UR_PROBLEMS[@]}
    if [ -L "$HYPR_DIR" ] && [ ! -e "$HYPR_DIR" ]; then problem hyprland "~/.config/hypr is a broken link → $(readlink "$HYPR_DIR")"; return; fi
    [ -d "$HYPR_DIR" ] || { problem hyprland "~/.config/hypr is missing"; return; }
    [ -f "$HYPR_DIR/hyprland.conf" ] || [ -f "$HYPR_DIR/hyprland.lua" ] || problem hyprland "no hyprland.conf or hyprland.lua"
    command -v Hyprland >/dev/null 2>&1 || problem hyprland "Hyprland is not installed (sudo dnf install hyprland)"

    local out rc
    out="$(validate_hyprland "$HYPR_DIR")"; rc=$?
    case "$rc" in
        0) check_ok "Hyprland accepts the configuration" ;;
        2) ;;
        *) problem hyprland "Hyprland rejects the configuration: $(head -1 <<< "$out")" ;;
    esac

    local m; while IFS= read -r m; do [ -n "$m" ] && problem hyprland "sourced file missing: ${m/#$HOME/\~}"; done < <(hypr_missing_sources)
    [ -f "$HYPR_DIR/monitors.conf" ] || grep -qs '^[[:space:]]*monitor' "$HYPR_DIR/hyprland.conf" || problem hyprland "no monitor configuration (monitors.conf)"

    local cmd dup
    dup="$(hypr_autostart | sed 's/[[:space:]]\+/ /g' | sort | uniq -d)"
    while IFS= read -r cmd; do [ -n "$cmd" ] && problem hyprland "autostart command listed twice: $cmd"; done <<< "$dup"
    while IFS= read -r cmd; do
        [ -n "$cmd" ] || continue
        command_exists "$cmd" || problem hyprland "autostart program not found: ${cmd%% *}"
    done < <(hypr_autostart)

    local clash; while IFS= read -r clash; do [ -n "$clash" ] && problem hyprland "keybinding defined twice: $clash"; done < <(hypr_bind_clashes)

    local l; while IFS= read -r l; do problem hyprland "broken link: ${l/#$HOME/\~} → $(readlink "$l")"; done < <(broken_symlinks "$HYPR_DIR")
    while IFS= read -r l; do problem hyprland "$l"; done < <(permission_problems "$HYPR_DIR")
    [ "${#UR_PROBLEMS[@]}" -eq "$p0" ] && check_ok "Hyprland: sourced files, autostart and keybindings look right"
    return 0
}

mod_hyprland_repair() {
    repair_link "$HYPR_DIR" config/hypr
    repair_deleted_tracked config/hypr
    repair_missing_copy "$HYPR_DIR" config/hypr
    repair_broken_links "$HYPR_DIR"
    repair_perms "$HYPR_DIR"
    # Generated fragments (colours, monitors, glass…) that are missing: an
    # empty file lets Hyprland start; the owning tool regenerates it.
    local m
    while IFS= read -r m; do
        [ -n "$m" ] || continue
        case "$m" in "$HOME"/*) change "create empty placeholder for missing sourced file ${m/#$HOME/\~}" sh -c 'mkdir -p "$(dirname "$1")" && : > "$1"' sh "$m" ;; esac
    done < <(hypr_missing_sources)
    repair_full_restore hyprland config/hypr
    ui_info "Duplicate autostart entries and keybinding clashes are reported, not edited: they can be intentional."
}
