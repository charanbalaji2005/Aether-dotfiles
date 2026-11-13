# shellcheck shell=bash
# ULTRON RECOVERY — recovery engine: component registry, modes, the guarded
# `change` primitive every repair goes through, shared repair helpers, and the
# completion screen.
#
# Modes
#   safe      read-only: checks and recommendations, never writes
#   standard  repairs missing files, links, permissions; asks first; backs up first
#   full      standard + restores changed/invalid configs from the known-good
#             release (your dotfiles repo at git HEAD) or the newest backup
#   dry run   (any mode) shows every change without making it

UR_COMPONENTS=(hyprland waybar rofi quickshell island kitty shell themes fonts)
UR_PROBLEMS=()
UR_REPAIRED=()
UR_SKIPPED=()
UR_REMAINING=()
UR_CHANGES=0

component_title() {
    case "$1" in
        hyprland) echo "Hyprland" ;; waybar) echo "Waybar" ;; rofi) echo "Rofi" ;;
        quickshell) echo "Quickshell & Dock" ;; island) echo "Dynamic Island" ;; kitty) echo "Kitty terminal" ;;
        shell) echo "Shell configuration" ;; themes) echo "GTK themes & icons" ;; fonts) echo "Fonts & wallpapers" ;;
        *) echo "$1" ;;
    esac
}
component_valid() { local c; for c in "${UR_COMPONENTS[@]}"; do [ "$c" = "$1" ] && return 0; done; return 1; }
component_normalize() {  # accept a few aliases on the command line
    case "${1,,}" in
        hypr) echo hyprland ;; qs|dock|quickshell-dock) echo quickshell ;; dynamic-island|dynamicisland) echo island ;;
        zsh|bash|tmux|shells) echo shell ;; gtk|icons|theme) echo themes ;; wallpapers|wallpaper|font) echo fonts ;;
        terminal) echo kitty ;; *) echo "${1,,}" ;;
    esac
}
component_paths()  { "mod_${1}_paths"; }
component_check()  { "mod_${1}_check"; }
component_deps()   { "mod_${1}_deps"; }

problems_reset() { UR_PROBLEMS=(); }
problem() {  # problem COMPONENT MESSAGE
    UR_PROBLEMS+=("[$1] $2")
    log_warn "$2"
}
check_ok() { log_ok "$*"; }

# change "what" CMD… — the only way repairs modify anything.
change() {
    local what="$1"; shift
    if [ "$UR_MODE" = safe ]; then log_info "recommendation: $what"; return 0; fi
    if [ "$UR_DRY_RUN" = 1 ]; then log_info "${C_YELLOW}[dry run]${C_RESET} would: $what"; UR_CHANGES=$((UR_CHANGES + 1)); return 0; fi
    log_raw "CHANGE $what :: $*"
    if "$@" >>"$UR_LOG_FILE" 2>&1; then log_ok "$what"; UR_CHANGES=$((UR_CHANGES + 1)); return 0; fi
    log_error "failed: $what (details in the log)"
    return 1
}

# ── known-good release: the AetherOS dotfiles repository ─────────────────
detect_repo() {
    local cand d
    for cand in "${UR_REPO_OVERRIDE:-}" "${UR_SOURCE_REPO:-}" "$(dirname "$UR_HOME")" \
                "$(readlink -f "$HOME/.config/hypr" 2>/dev/null | sed 's|/config/hypr$||')"; do
        [ -n "$cand" ] || continue
        d="$(readlink -f "$cand" 2>/dev/null)" || continue
        [ -d "$d/config/hypr" ] && [ -d "$d/config/waybar" ] && { echo "$d"; return 0; }
    done
    return 1
}
repo_is_git() { [ -n "${UR_REPO:-}" ] && git -C "$UR_REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; }

# ── shared repair helpers (each calls `change`) ─────────────────────────
# repair_link PATH REPO_REL — a missing or dangling config link → relink to the repo
repair_link() {
    local p="$1" rel="$2"
    [ -n "${UR_REPO:-}" ] && [ -e "$UR_REPO/$rel" ] || return 0
    if [ -L "$p" ] && [ ! -e "$p" ]; then
        change "relink broken ${p/#$HOME/\~} → $UR_REPO/$rel" ln -sfn -- "$UR_REPO/$rel" "$p"
    elif [ ! -e "$p" ] && [ ! -L "$p" ]; then
        change "link missing ${p/#$HOME/\~} → $UR_REPO/$rel" sh -c 'mkdir -p "$(dirname "$2")" && ln -sfn -- "$1" "$2"' sh "$UR_REPO/$rel" "$p"
    fi
}

# repair_deleted_tracked REPO_REL — files git tracks that were deleted → restore from HEAD
repair_deleted_tracked() {
    repo_is_git || return 0
    local rel="$1" files
    files="$(git -C "$UR_REPO" ls-files -d -- "$rel" 2>/dev/null)"
    [ -n "$files" ] || return 0
    change "restore $(wc -l <<< "$files") deleted file(s) in $rel from the dotfiles repo (git HEAD)" \
        git -C "$UR_REPO" checkout -- "$rel"
}

# repair_missing_copy DIR REPO_REL — DIR is a real directory (not linked to the
# repo): copy files the repo has and DIR lacks. Existing files are untouched.
repair_missing_copy() {
    local d="$1" rel="$2" f missing=()
    [ -n "${UR_REPO:-}" ] && [ -d "$UR_REPO/$rel" ] && [ -d "$d" ] && [ ! -L "$d" ] || return 0
    while IFS= read -r f; do
        [ -e "$d/$f" ] || missing+=("$f")
    done < <(cd "$UR_REPO/$rel" && find . -type f ! -path '*/.git/*' ! -name '*.pyc' -printf '%P\n')
    [ "${#missing[@]}" -gt 0 ] || return 0
    change "copy ${#missing[@]} missing file(s) into ${d/#$HOME/\~} from the dotfiles repo" \
        sh -c 'src="$1"; dst="$2"; shift 2; for f; do mkdir -p "$dst/$(dirname "$f")" && cp -an "$src/$f" "$dst/$f" || exit 1; done' \
        sh "$UR_REPO/$rel" "$d" "${missing[@]}"
}

# repair_perms DIR — scripts get +x, world-writable files lose o+w
repair_perms() {
    local d="$1" line f
    while IFS= read -r line; do
        case "$line" in
            "script not executable: "*) f="${line#script not executable: }"; change "make ${f/#$HOME/\~} executable" chmod u+x -- "$f" ;;
            "world-writable: "*) f="${line#world-writable: }"; change "remove world-write permission from ${f/#$HOME/\~}" chmod o-w -- "$f" ;;
        esac
    done < <(permission_problems "$d")
}

# repair_broken_links DIR — a dangling link whose path exists in the current
# repo (e.g. the repo moved) is pointed there; others are only reported.
repair_broken_links() {
    local d="$1" l t rel
    while IFS= read -r l; do
        t="$(readlink "$l")"
        rel="$(sed -nE 's|.*/(config/.+)$|\1|p' <<< "$t")"
        if [ -n "${UR_REPO:-}" ] && [ -n "$rel" ] && [ -e "$UR_REPO/$rel" ]; then
            change "point broken link ${l/#$HOME/\~} at $UR_REPO/$rel" ln -sfn -- "$UR_REPO/$rel" "$l"
        fi
    done < <(broken_symlinks "$d")
}

# repair_full_restore COMPONENT REPO_REL… — FULL mode only: put back the
# known-good version of changed files (git HEAD), else the newest backup.
repair_full_restore() {
    local c="$1"; shift
    [ "$UR_MODE" = full ] || return 0
    local rel changed=""
    if repo_is_git; then
        for rel in "$@"; do changed+="$(git -C "$UR_REPO" diff --name-only -- "$rel" 2>/dev/null)"$'\n'; done
        changed="$(sed '/^$/d' <<< "$changed")"
        if [ -n "$changed" ]; then
            ui_info "Changed from the known-good release:"; sed 's/^/      /' <<< "$changed" | head -15
            change "restore $(wc -l <<< "$changed") changed file(s) of $c from the dotfiles repo (git HEAD)" \
                git -C "$UR_REPO" checkout -- "$@"
        fi
        return 0
    fi
    local id; id="$(backup_ids | while read -r b; do backup_components "$b" | grep -qx "$c" && { echo "$b"; break; }; done)"
    if [ -n "$id" ]; then
        log_info "No git release available; newest backup with $c: $id"
        [ "$UR_DRY_RUN" = 1 ] && { log_info "[dry run] would restore $c from $id"; return 0; }
        restore_backup "$id" "$c"
    fi
}

# ── repair session ─────────────────────────────────────────────────────
repair_component() {
    local c="$1" before after
    ui_step "Repair: $(component_title "$c")"
    problems_reset
    component_check "$c"
    before="${#UR_PROBLEMS[@]}"
    if [ "$before" = 0 ] && [ "$UR_MODE" != full ]; then
        log_ok "$(component_title "$c"): no problems"
        UR_SKIPPED+=("$c (healthy)"); return 0
    fi
    if [ "$UR_MODE" = safe ]; then
        log_info "SAFE MODE: recommendations only —"
        "mod_${c}_repair"
        UR_SKIPPED+=("$c (safe mode)"); UR_REMAINING+=("${UR_PROBLEMS[@]}"); return 0
    fi
    echo
    if [ "$UR_DRY_RUN" != 1 ]; then
        ui_confirm "Repair $(component_title "$c") (${before} problem(s); a backup is taken first)?" \
            || { UR_SKIPPED+=("$c (declined)"); UR_REMAINING+=("${UR_PROBLEMS[@]}"); return 0; }
        op_begin "repair $c" "$c" || { UR_REMAINING+=("${UR_PROBLEMS[@]}"); return 1; }
    fi
    UR_CHANGES=0
    "mod_${c}_repair"
    [ "$UR_DRY_RUN" = 1 ] || op_end
    # Re-check to report what is left.
    ui_step "Re-check: $(component_title "$c")"
    problems_reset
    component_check "$c"
    after="${#UR_PROBLEMS[@]}"
    if [ "$UR_DRY_RUN" = 1 ]; then UR_SKIPPED+=("$c (dry run: $UR_CHANGES change(s) previewed)")
    elif [ "$UR_CHANGES" -gt 0 ]; then UR_REPAIRED+=("$c ($UR_CHANGES change(s))")
    else UR_SKIPPED+=("$c (nothing repairable automatically)"); fi
    [ "$after" -gt 0 ] && UR_REMAINING+=("${UR_PROBLEMS[@]}")
    return 0
}

# ── restarting desktop parts (never the session, never a reboot) ────────
restart_component() {
    local c="$1"
    if ! det_hypr_running || [ -z "${WAYLAND_DISPLAY:-}${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        log_warn "No Hyprland session reachable from here — restart $c after logging in."; return 1
    fi
    case "$c" in
        hyprland) change "reload Hyprland config" hyprctl reload ;;
        waybar)
            if command -v aether-waybar >/dev/null 2>&1; then change "restart Waybar" aether-waybar restart
            else change "restart Waybar" sh -c 'pkill -x waybar; sleep 0.5; setsid -f waybar >/dev/null 2>&1'; fi ;;
        island|quickshell)
            if [ -x "$HOME/.config/waybar/scripts/dynamic-island.sh" ]; then change "restart Dynamic Island" "$HOME/.config/waybar/scripts/dynamic-island.sh" restart; fi
            [ "$c" = quickshell ] && command -v aether-dock >/dev/null 2>&1 && change "restart dock" sh -c 'aether-dock stop; aether-dock run' ;;
        *) log_info "$(component_title "$c") needs no restart (new terminals/apps pick it up)" ;;
    esac
}

# ── completion screen ──────────────────────────────────────────────────
completion_screen() {
    local status="COMPLETE" x
    [ "${#UR_REMAINING[@]}" -gt 0 ] && status="COMPLETE WITH REMAINING PROBLEMS"
    [ "$UR_DRY_RUN" = 1 ] && status="DRY RUN — NOTHING CHANGED"
    [ "$UR_MODE" = safe ] && status="SAFE MODE — NOTHING CHANGED"
    echo; ui_rule 64
    printf '  %s%sRECOVERY STATUS:%s %s\n' "$C_BOLD" "$C_RED" "$C_RESET" "$status"
    ui_rule 64
    printf '  %sRepaired%s\n' "$C_GREEN" "$C_RESET"
    if [ "${#UR_REPAIRED[@]}" -gt 0 ]; then for x in "${UR_REPAIRED[@]}"; do printf '      ✔ %s\n' "$x"; done; else echo "      —"; fi
    printf '  %sSkipped%s\n' "$C_CYAN" "$C_RESET"
    if [ "${#UR_SKIPPED[@]}" -gt 0 ]; then for x in "${UR_SKIPPED[@]}"; do printf '      • %s\n' "$x"; done; else echo "      —"; fi
    printf '  %sRemaining problems%s\n' "$C_YELLOW" "$C_RESET"
    if [ "${#UR_REMAINING[@]}" -gt 0 ]; then for x in "${UR_REMAINING[@]}"; do printf '      ▲ %s\n' "$x"; done; else echo "      none"; fi
    echo
    ui_kv "Backups" "$UR_BACKUP_DIR"
    ui_kv "Logs" "$UR_LOG_FILE"
    if [ "${#UR_REMAINING[@]}" -gt 0 ]; then ui_kv "Next" "fix the remaining items by hand (see log), or try FULL mode: ultron-recovery --full --repair X"
    elif [ "${#UR_REPAIRED[@]}" -gt 0 ]; then ui_kv "Next" "restart the repaired components (below) or log out and back in"
    else ui_kv "Next" "nothing to do"; fi
    ui_rule 64
}

completion_menu() {  # offer restarts of what was repaired
    ui_interactive || return 0
    [ "${#UR_REPAIRED[@]}" -gt 0 ] || { ui_pause; return 0; }
    local items=() x c
    for x in "${UR_REPAIRED[@]}"; do c="${x%% *}"; items+=("Restart $(component_title "$c") [$c]"); done
    while true; do
        echo
        x="$(ui_choose "Restart a component, or 0 for the main menu" "${items[@]}")" || return 0
        c="$(sed -nE 's/.*\[([a-z]+)\]$/\1/p' <<< "$x")"
        [ -n "$c" ] && restart_component "$c"
    done
}

results_reset() { UR_REPAIRED=(); UR_SKIPPED=(); UR_REMAINING=(); }
