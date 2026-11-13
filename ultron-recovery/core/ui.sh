# shellcheck shell=bash
# ULTRON RECOVERY — terminal interface: colours, banner, menus, prompts,
# spinner, progress bar. Plain ANSI only, so it works on a bare TTY. Colours are
# off when stdout is not a terminal or NO_COLOR is set.

ui_colors() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
        local n; n="$(tput colors 2>/dev/null || echo 8)"
        C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'
        if [ "${n:-8}" -ge 256 ]; then
            C_RED=$'\e[38;5;196m'; C_CRIMSON=$'\e[38;5;160m'; C_DARK=$'\e[38;5;88m'
            C_CYAN=$'\e[38;5;51m'; C_GREEN=$'\e[38;5;46m'; C_YELLOW=$'\e[38;5;220m'; C_GREY=$'\e[38;5;245m'
        else
            C_RED=$'\e[1;31m'; C_CRIMSON=$'\e[31m'; C_DARK=$'\e[31m'
            C_CYAN=$'\e[36m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_GREY=$'\e[37m'
        fi
    else
        C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_CRIMSON=""; C_DARK=""
        C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_GREY=""
    fi
}
ui_colors

ui_interactive() { [ -t 0 ] && [ -t 1 ] && [ "${UR_ASSUME_YES:-0}" != 1 ]; }

ui_info()  { [ "${UR_QUIET:-0}" = 1 ] || printf '  %s•%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
ui_ok()    { [ "${UR_QUIET:-0}" = 1 ] || printf '  %s✔%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
ui_warn()  { printf '  %s▲%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
ui_error() { printf '  %s✖%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
ui_step()  { [ "${UR_QUIET:-0}" = 1 ] || printf '\n %s▶ %s%s%s\n' "$C_CRIMSON" "$C_BOLD" "$*" "$C_RESET"; }
ui_kv()    { printf '  %s%-22s%s %s\n' "$C_GREY" "$1" "$C_RESET" "$2"; }
ui_rule()  { printf '%s%s%s\n' "$C_DARK" "$(printf '─%.0s' $(seq 1 "${1:-64}"))" "$C_RESET"; }

ui_logo() {
    # Block glyphs on graphical terminals; plain ASCII on the Linux console,
    # whose fonts often lack them.
    if [ "${TERM:-}" = linux ] || [ ! -r "$UR_HOME/assets/ultron-logo.txt" ]; then
        printf '%s' "$C_RED"
        cat <<'EOF'
   _   _ _   _____ ____   ___  _   _
  | | | | | |_   _|  _ \ / _ \| \ | |
  | | | | |   | | | |_) | | | |  \| |
  | |_| | |___| | |  _ <| |_| | |\  |
   \___/|_____|_| |_| \_\\___/|_| \_|
EOF
        printf '%s' "$C_RESET"
    else
        printf '%s%s%s' "$C_RED" "$(cat "$UR_HOME/assets/ultron-logo.txt")" "$C_RESET"
        echo
    fi
}

ui_banner() {
    [ "${UR_QUIET:-0}" = 1 ] && return 0
    ui_interactive && [ "${UR_NO_CLEAR:-0}" != 1 ] && printf '\e[H\e[2J'
    ui_logo
    printf '  %s%sULTRON RECOVERY%s  %s%s%s\n' "$C_BOLD" "$C_RED" "$C_RESET" "$C_GREY" "v$UR_VERSION" "$C_RESET"
    printf '  %sADVANCED LINUX RECOVERY SYSTEM%s · %sFEDORA HYPRLAND EDITION%s\n' "$C_CRIMSON" "$C_RESET" "$C_GREY" "$C_RESET"
    printf '  %sDeveloped by:%s %sNEELAMPALLI CHARAN BALAJI%s\n' "$C_GREY" "$C_RESET" "$C_BOLD" "$C_RESET"
    local mode="$UR_MODE"; mode="${mode^^}"
    local dry=""; [ "$UR_DRY_RUN" = 1 ] && dry="  ${C_YELLOW}[DRY RUN — nothing will be changed]${C_RESET}"
    printf '  %sMODE:%s %s%s%s%s\n' "$C_GREY" "$C_RESET" "$C_CYAN" "$mode" "$C_RESET" "$dry"
    ui_rule 64
}

ui_pause() { ui_interactive || return 0; printf '\n  %sPress Enter to continue…%s' "$C_GREY" "$C_RESET"; read -r _ || true; }

# ui_confirm "Question" — yes/no; non-interactive runs need UR_ASSUME_YES=1.
ui_confirm() {
    [ "${UR_ASSUME_YES:-0}" = 1 ] && { log_raw "CONFIRM (assumed yes) $1"; return 0; }
    if ! [ -t 0 ]; then log_raw "CONFIRM (no terminal, refused) $1"; return 1; fi
    local a
    printf '  %s?%s %s %s[y/N]%s ' "$C_YELLOW" "$C_RESET" "$1" "$C_GREY" "$C_RESET"
    read -r a || return 1
    case "$a" in y|Y|yes|YES) log_raw "CONFIRM yes $1"; return 0 ;; *) log_raw "CONFIRM no $1"; return 1 ;; esac
}

# ui_choose "Prompt" ITEM… — prints the chosen item (1-based menu), empty on cancel.
ui_choose() {
    local prompt="$1"; shift
    local i=1 item a
    for item in "$@"; do printf '   %s%2d%s  %s\n' "$C_RED" "$i" "$C_RESET" "$item" >&2; i=$((i + 1)); done
    printf '   %s 0%s  Back\n' "$C_RED" "$C_RESET" >&2
    printf '\n  %s%s ›%s ' "$C_CYAN" "$prompt" "$C_RESET" >&2
    read -r a || return 1
    [[ "$a" =~ ^[0-9]+$ ]] && [ "$a" -ge 1 ] && [ "$a" -le $# ] || return 1
    eval "printf '%s\n' \"\${$a}\""
}

ui_progress() {  # ui_progress CURRENT TOTAL LABEL
    [ "${UR_QUIET:-0}" = 1 ] && return 0
    [ -t 1 ] || return 0
    local cur="$1" tot="$2" w=30 fill pct k bar="" rest=""
    [ "$tot" -gt 0 ] || tot=1
    pct=$(( cur * 100 / tot )); fill=$(( cur * w / tot ))
    for ((k = 0; k < fill; k++)); do bar+="█"; done
    for ((k = fill; k < w; k++)); do rest+="░"; done
    printf '\r  %s[%s%s%s%s%s]%s %3d%% %s\e[K' "$C_DARK" "$C_RED" "$bar" "$C_DARK" "$rest" "$C_DARK" "$C_RESET" "$pct" "$3"
    [ "$cur" -ge "$tot" ] && echo
    return 0
}

# ui_spin "Label" CMD… — run CMD with a spinner; returns CMD's status.
ui_spin() {
    local label="$1"; shift
    if [ "${UR_QUIET:-0}" = 1 ] || ! [ -t 1 ]; then "$@"; return $?; fi
    local frames='⣾⣽⣻⢿⡿⣟⣯⣷' i=0 pid rc
    [ "${TERM:-}" = linux ] && frames='|/-\|/-\'
    "$@" >>"${UR_LOG_FILE:-/dev/null}" 2>&1 &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r  %s%s%s %s' "$C_RED" "${frames:i++%8:1}" "$C_RESET" "$label"
        sleep 0.1
    done
    wait "$pid"; rc=$?
    if [ "$rc" = 0 ]; then printf '\r  %s✔%s %s\e[K\n' "$C_GREEN" "$C_RESET" "$label"
    else printf '\r  %s✖%s %s\e[K\n' "$C_RED" "$C_RESET" "$label"; fi
    return "$rc"
}
