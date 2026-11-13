#!/usr/bin/env bash
# ULTRON RECOVERY — advanced Linux recovery system, Fedora Hyprland edition.
# Developed by NEELAMPALLI CHARAN BALAJI.
#
# Works from a TTY with nothing but bash and coreutils: no Hyprland, Waybar,
# Rofi or Quickshell needed. See README.md, or: ultron-recovery --help
set -uo pipefail

UR_VERSION="1.0.0"
UR_HOME="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
UR_DATA="${UR_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/ultron-recovery}"
UR_BACKUP_DIR="$UR_DATA/backups"
UR_LOG_DIR="$UR_DATA/logs"
UR_REPORT_DIR="$UR_DATA/reports"
UR_STATE_DIR="$UR_DATA/state"
UR_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ultron-recovery"
UR_MODE="standard"
UR_DRY_RUN=0
UR_ASSUME_YES="${UR_ASSUME_YES:-0}"
UR_KEEP_BACKUPS=20
UR_REPO_OVERRIDE="${UR_REPO_OVERRIDE:-}"     # tests point this at a fake repo
UR_SOURCE_REPO=""

load_config() {  # whitelisted KEY=value lines only; never sourced
    local f="$1" key val
    [ -r "$f" ] || return 0
    while IFS='=' read -r key val; do
        key="${key//[[:space:]]/}"; val="${val%%#*}"; val="${val%"${val##*[![:space:]]}"}"; val="${val#"${val%%[![:space:]]*}"}"
        case "$key" in
            MODE) case "$val" in safe|standard|full) UR_MODE="$val" ;; esac ;;
            KEEP_BACKUPS) [[ "$val" =~ ^[0-9]+$ ]] && UR_KEEP_BACKUPS="$val" ;;
            REPO) [ -n "$val" ] && UR_REPO_OVERRIDE="${val/#\~/$HOME}" ;;
            SOURCE_REPO) [ -n "$val" ] && UR_SOURCE_REPO="${val/#\~/$HOME}" ;;
            COLOR) [ "$val" = never ] && export NO_COLOR=1 ;;
        esac
    done < <(grep -E '^[[:space:]]*[A-Z_]+[[:space:]]*=' "$f")
}
load_config "$UR_HOME/config/recovery.conf"
load_config "$UR_HOME/install.conf"          # written by install.sh
load_config "$UR_CONFIG_DIR/recovery.conf"

for f in ui logging validation detection backup restore rollback diagnostics recovery-engine; do
    # shellcheck source=/dev/null
    . "$UR_HOME/core/$f.sh"
done
for f in "$UR_HOME"/modules/*.sh; do
    # shellcheck source=/dev/null
    . "$f"
done
unset f

usage() {
    cat <<EOF
${C_RED}${C_BOLD}ULTRON RECOVERY${C_RESET} $UR_VERSION — advanced Linux recovery system (Fedora Hyprland edition)
Developed by NEELAMPALLI CHARAN BALAJI

Usage: ultron-recovery [MODE] [ACTION]

Actions (none: the interactive menu)
  --diagnose                 full system diagnostics + report
  --repair COMPONENT|all     repair one component, or all of them
  --backup [COMPONENT…]      create a backup (default: every component)
  --restore [ID [COMP…]]     restore a backup (no ID: choose from a list)
  --rollback                 undo the last recovery (restores its automatic backup)
  --list-backups             list backups        --verify ID   check a backup's integrity
  --preview ID               show what a backup holds
  --deps                     dependency report (and the dnf command to fix it)
  --info                     system information
  --logs                     show the latest recovery log
  --emergency                emergency TTY recovery menu
  --version, --help

Modes
  --safe                     read-only: diagnostics and recommendations only
  --standard                 repair missing files, links, permissions (default)
  --full                     also restore changed/invalid configs from the
                             known-good release (dotfiles repo) or newest backup
  --dry-run                  show every change without making it (any mode)
  --yes                      don't ask (for scripts); backups are still taken

Components: ${UR_COMPONENTS[*]}

Data: backups $UR_BACKUP_DIR
      logs    $UR_LOG_DIR
      reports $UR_REPORT_DIR
EOF
}

# ── interactive pieces ─────────────────────────────────────────────────
pick_backup() {  # prints a backup id chosen from a list
    local ids=() labels=() id
    mapfile -t ids < <(backup_ids)
    [ "${#ids[@]}" -gt 0 ] || { ui_info "No backups yet." >&2; return 1; }
    for id in "${ids[@]}"; do labels+=("$id  ${C_GREY}$(backup_meta "$id" size) · $(backup_meta "$id" components)${C_RESET}"); done
    local choice; choice="$(ui_choose "Backup" "${labels[@]}")" || return 1
    printf '%s\n' "${choice%% *}"
}

pick_components() {  # pick_components [FROM…] — "1 3 4" or "a"; prints names
    local from=("$@") i=1 c a
    [ "${#from[@]}" -gt 0 ] || from=("${UR_COMPONENTS[@]}")
    for c in "${from[@]}"; do printf '   %s%2d%s  %s\n' "$C_RED" "$i" "$C_RESET" "$(component_title "$c") [$c]" >&2; i=$((i + 1)); done
    printf '\n  %sNumbers separated by spaces, a = all, Enter = cancel ›%s ' "$C_CYAN" "$C_RESET" >&2
    read -r a || return 1
    [ -n "$a" ] || return 1
    if [ "$a" = a ]; then printf '%s\n' "${from[@]}"; return 0; fi
    for i in $a; do [[ "$i" =~ ^[0-9]+$ ]] && [ "$i" -ge 1 ] && [ "$i" -le "${#from[@]}" ] && echo "${from[$((i - 1))]}"; done
}

run_repairs() {  # run_repairs COMPONENT…
    results_reset
    local c; for c in "$@"; do repair_component "$c"; done
    completion_screen
    completion_menu
}

menu_backups() {
    while true; do
        ui_banner
        printf '  %sBACKUP MANAGER%s  %s%s%s\n\n' "$C_BOLD" "$C_RESET" "$C_GREY" "$UR_BACKUP_DIR" "$C_RESET"
        local a id comps=()
        a="$(ui_choose "Select" "Create full backup" "Create component backup" "List backups" "Preview a backup" \
            "Verify a backup" "Restore selected components" "Restore full backup" "Delete a backup")" || return 0
        echo
        case "$a" in
            "Create full backup") backup_create manual "${UR_COMPONENTS[@]}" ;;
            "Create component backup") mapfile -t comps < <(pick_components); [ "${#comps[@]}" -gt 0 ] && backup_create manual "${comps[@]}" ;;
            "List backups") backup_list ;;
            "Preview a backup") id="$(pick_backup)" && { echo; backup_preview "$id"; } ;;
            "Verify a backup") id="$(pick_backup)" && backup_verify "$id" ;;
            "Restore selected components")
                id="$(pick_backup)" || continue
                echo; mapfile -t comps < <(pick_components $(backup_components "$id"))
                [ "${#comps[@]}" -gt 0 ] && restore_backup "$id" "${comps[@]}" ;;
            "Restore full backup") id="$(pick_backup)" && restore_backup "$id" ;;
            "Delete a backup") id="$(pick_backup)" && backup_delete "$id" ;;
        esac
        ui_pause
    done
}

menu_deps() {
    ui_step "Dependency Manager"
    local c line cmd pkg missing=() seen=" "
    for c in "${UR_COMPONENTS[@]}"; do
        printf '\n  %s%s%s\n' "$C_CYAN" "$(component_title "$c")" "$C_RESET"
        while IFS= read -r line; do
            cmd="${line%%:*}"; pkg="${line#*:}"
            if command -v "$cmd" >/dev/null 2>&1; then printf '     %s✔%s %-12s %s(%s)%s\n' "$C_GREEN" "$C_RESET" "$cmd" "$C_GREY" "$pkg" "$C_RESET"
            else
                printf '     %s✖%s %-12s %smissing — package %s%s\n' "$C_RED" "$C_RESET" "$cmd" "$C_YELLOW" "$pkg" "$C_RESET"
                [[ "$seen" == *" $pkg "* ]] || { missing+=("$pkg"); seen+="$pkg "; }
            fi
        done < <(component_deps "$c")
    done
    echo
    if [ "${#missing[@]}" -eq 0 ]; then log_ok "All dependencies are installed."; return 0; fi
    local cmdline="sudo dnf install ${missing[*]}"
    log_warn "Missing packages: ${missing[*]}"
    [[ " ${missing[*]} " == *" quickshell "* ]] && ui_info "quickshell comes from the COPR errornointernet/quickshell (sudo dnf copr enable errornointernet/quickshell)"
    ui_info "Install with: $cmdline"
    if [ "$UR_MODE" != safe ] && [ "$UR_DRY_RUN" != 1 ] && ui_interactive && ui_confirm "Run it now (asks for your password)?"; then
        log_raw "RUN $cmdline"
        sudo dnf install "${missing[@]}" && log_ok "Packages installed" || log_error "dnf failed (see above)"
    fi
}

menu_logs() {
    local logs=() choice
    mapfile -t logs < <(logs_list | head -15)
    [ "${#logs[@]}" -gt 0 ] || { ui_info "No logs yet."; return 0; }
    choice="$(ui_choose "Log" "${logs[@]}")" || return 0
    logs_show "$choice"
}

SAFE_HYPR_CONF=""
write_safe_hypr_conf() {
    SAFE_HYPR_CONF="$UR_DATA/safe-hyprland.conf"
    mkdir -p "$UR_DATA"
    cat > "$SAFE_HYPR_CONF" <<'EOF'
# ULTRON RECOVERY — minimal Hyprland session: no autostart, no effects,
# nothing sourced. Super+Return: terminal · Super+Q: close · Super+Shift+E: exit.
monitor = , preferred, auto, 1
env = XDG_CURRENT_DESKTOP,Hyprland
decoration {
    blur { enabled = false }
    shadow { enabled = false }
}
animations { enabled = false }
misc { disable_hyprland_logo = true }
bind = SUPER, Return, exec, kitty || foot || alacritty || xterm
bind = SUPER, Q, killactive
bind = SUPER SHIFT, E, exit
bind = SUPER, T, exec, kitty -e ultron-recovery
exec-once = kitty -e ultron-recovery
EOF
}

menu_emergency() {
    while true; do
        ui_banner
        printf '  %sEMERGENCY TTY RECOVERY%s   session: %s\n' "$C_BOLD" "$C_RESET" "$(det_session)"
        printf '  %sTo get here when the desktop is broken: Ctrl+Alt+F3, log in, run ultron-recovery.%s\n' "$C_GREY" "$C_RESET"
        printf '  %sBack to the graphical session: Ctrl+Alt+F2 (or F1).%s\n\n' "$C_GREY" "$C_RESET"
        local a id
        a="$(ui_choose "Select" "Quick check: Hyprland and Waybar" "Restore Hyprland from the newest backup" \
            "Roll back the last recovery" "Start a minimal safe Hyprland session (from a TTY)" \
            "Stop stuck desktop parts (Waybar, Quickshell, Rofi)" "Repair Hyprland now")" || return 0
        echo
        case "$a" in
            "Quick check"*) problems_reset; ui_step "Hyprland"; component_check hyprland; ui_step "Waybar"; component_check waybar ;;
            "Restore Hyprland"*)
                id="$(backup_ids | while read -r b; do backup_components "$b" | grep -qx hyprland && { echo "$b"; break; }; done)"
                if [ -n "$id" ]; then restore_backup "$id" hyprland; else log_warn "No backup contains Hyprland yet."; fi ;;
            "Roll back"*) rollback_last ;;
            "Start a minimal"*)
                if det_hypr_running; then log_warn "Hyprland is already running — this is only for a TTY with no session."
                elif ! command -v Hyprland >/dev/null 2>&1; then log_error "Hyprland is not installed."
                else
                    write_safe_hypr_conf
                    ui_info "Config: $SAFE_HYPR_CONF (a terminal with ULTRON opens inside it)"
                    if [ -f "$HOME/.config/hypr/recovery.conf" ]; then ui_info "AetherOS also ships one: Hyprland -c ~/.config/hypr/recovery.conf"; fi
                    if ui_confirm "Start Hyprland with the minimal config now?"; then log_raw "exec Hyprland -c $SAFE_HYPR_CONF"; exec Hyprland -c "$SAFE_HYPR_CONF"; fi
                fi ;;
            "Stop stuck"*)
                [ "${UR_NO_PROCESS:-0}" = 1 ] && { log_info "process actions disabled (UR_NO_PROCESS=1)"; ui_pause; continue; }
                local p any=0
                for p in waybar qs quickshell rofi; do
                    if pgrep -x "$p" >/dev/null 2>&1; then any=1; change "stop $p" pkill -x "$p"; fi
                done
                [ "$any" = 1 ] || log_info "None of them is running." ;;
            "Repair Hyprland now") run_repairs hyprland; continue ;;
        esac
        ui_pause
    done
}

menu_main() {
    local items=("Full System Diagnostics" "Full Dotfiles Recovery" "Restore Previous Configuration" "Repair Hyprland" \
        "Repair Waybar" "Repair Rofi" "Repair Quickshell Dock" "Repair Dynamic Island" "Repair Kitty Terminal" \
        "Repair Shell Configuration" "Repair GTK Themes and Icons" "Repair Fonts and Wallpapers" "Dependency Manager" \
        "Backup Manager" "System Information" "Recovery Logs" "Emergency TTY Recovery" "Exit")
    local a i id
    while true; do
        ui_banner
        i=1
        for a in "${items[@]}"; do
            printf '   %s%2d%s  %-34s' "$C_RED" "$i" "$C_RESET" "$a"
            [ $((i % 2)) = 0 ] && echo
            i=$((i + 1))
        done
        printf '\n   %s m%s  mode: %s (safe → standard → full)   %s d%s  dry run: %s\n' "$C_RED" "$C_RESET" "$UR_MODE" "$C_RED" "$C_RESET" "$([ "$UR_DRY_RUN" = 1 ] && echo on || echo off)"
        printf '\n  %sSelect ›%s ' "$C_CYAN" "$C_RESET"
        read -r a || exit 0
        case "$a" in
            m|M) case "$UR_MODE" in safe) UR_MODE=standard ;; standard) UR_MODE=full ;; *) UR_MODE=safe ;; esac; log_raw "mode → $UR_MODE"; continue ;;
            d|D) UR_DRY_RUN=$((1 - UR_DRY_RUN)); log_raw "dry run → $UR_DRY_RUN"; continue ;;
            q|Q) a=18 ;;
        esac
        echo
        case "$a" in
            1) diagnostics_run; ui_pause ;;
            2) run_repairs "${UR_COMPONENTS[@]}" ;;
            3) if id="$(pick_backup)"; then echo; restore_backup "$id"; fi; ui_pause ;;
            4) run_repairs hyprland ;;  5) run_repairs waybar ;;   6) run_repairs rofi ;;
            7) run_repairs quickshell ;; 8) run_repairs island ;;  9) run_repairs kitty ;;
            10) run_repairs shell ;;    11) run_repairs themes ;; 12) run_repairs fonts ;;
            13) menu_deps; ui_pause ;;
            14) menu_backups ;;
            15) system_info; ui_pause ;;
            16) menu_logs ;;
            17) menu_emergency ;;
            18) printf '\n  %sULTRON offline. Your desktop. Your control.%s\n\n' "$C_CRIMSON" "$C_RESET"; exit 0 ;;
            *) ;;
        esac
    done
}

# ── command line ───────────────────────────────────────────────────────
main() {
    local action="" arg=() repair_target=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help) action=help ;;
            -v|--version) action=version ;;
            --safe) UR_MODE=safe ;;
            --standard) UR_MODE=standard ;;
            --full) UR_MODE=full ;;
            --dry-run|-n) UR_DRY_RUN=1 ;;
            -y|--yes) UR_ASSUME_YES=1 ;;
            --no-color) export NO_COLOR=1; ui_colors ;;
            --diagnose|--diagnostics) action=diagnose ;;
            --repair) action=repair; shift; repair_target="${1:-}" ;;
            --backup) action=backup ;;
            --restore) action=restore ;;
            --rollback) action=rollback ;;
            --list-backups) action=list ;;
            --verify) action=verify ;;
            --preview) action=preview ;;
            --deps) action=deps ;;
            --info) action=info ;;
            --logs) action=logs ;;
            --emergency) action=emergency ;;
            -*) echo "ultron-recovery: unknown option $1 (see --help)" >&2; exit 2 ;;
            *) arg+=("$1") ;;
        esac
        shift
    done

    case "$action" in
        help) usage; exit 0 ;;
        version) echo "ULTRON RECOVERY $UR_VERSION — developed by NEELAMPALLI CHARAN BALAJI"; exit 0 ;;
    esac

    mkdir -p "$UR_BACKUP_DIR" "$UR_LOG_DIR" "$UR_REPORT_DIR" "$UR_STATE_DIR" || { echo "cannot create $UR_DATA" >&2; exit 1; }
    log_init || { echo "cannot write logs in $UR_LOG_DIR" >&2; exit 1; }
    journal_init
    UR_REPO="$(detect_repo || true)"
    log_raw "repo=${UR_REPO:-none}"

    local c comps=()
    case "$action" in
        "") ui_interactive || { usage; exit 2; }
            journal_check; menu_main ;;
        diagnose) UR_NO_CLEAR=1 ui_banner; diagnostics_run; [ "${UR_DIAG_PROBLEMS:-0}" = 0 ] ;;
        repair)
            UR_NO_CLEAR=1 ui_banner
            [ -n "$repair_target" ] || { log_error "--repair needs a component: ${UR_COMPONENTS[*]} or all"; exit 2; }
            journal_check
            if [ "$repair_target" = all ]; then comps=("${UR_COMPONENTS[@]}")
            else
                c="$(component_normalize "$repair_target")"
                component_valid "$c" || { log_error "unknown component '$repair_target' (choose: ${UR_COMPONENTS[*]} all)"; exit 2; }
                comps=("$c")
            fi
            results_reset
            for c in "${comps[@]}"; do repair_component "$c"; done
            completion_screen
            completion_menu
            [ "${#UR_REMAINING[@]}" = 0 ] ;;
        backup)
            for c in "${arg[@]}"; do c="$(component_normalize "$c")"; component_valid "$c" || { log_error "unknown component $c"; exit 2; }; comps+=("$c"); done
            UR_NO_CLEAR=1 ui_banner; backup_create manual "${comps[@]}" && { echo; ui_kv "Backup" "$UR_BACKUP_DIR/$UR_LAST_BACKUP"; } ;;
        restore)
            UR_NO_CLEAR=1 ui_banner
            local id="${arg[0]:-}"
            if [ -z "$id" ]; then
                ui_interactive || { log_error "--restore needs a backup id when not run in a terminal (see --list-backups)"; exit 2; }
                id="$(pick_backup)" || exit 0; echo
            fi
            restore_backup "$id" "${arg[@]:1}" ;;
        rollback) UR_NO_CLEAR=1 ui_banner; rollback_last ;;
        list) backup_list ;;
        verify) [ -n "${arg[0]:-}" ] || { log_error "--verify needs a backup id"; exit 2; }; backup_verify "${arg[0]}" ;;
        preview) [ -n "${arg[0]:-}" ] || { log_error "--preview needs a backup id"; exit 2; }; backup_preview "${arg[0]}" ;;
        deps) UR_NO_CLEAR=1 ui_banner; menu_deps ;;
        info) UR_NO_CLEAR=1 ui_banner; system_info ;;
        logs) logs_show ;;
        emergency) ui_interactive || { log_error "--emergency is interactive"; exit 2; }; menu_emergency ;;
    esac
}

main "$@"
