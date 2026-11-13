# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# functions/ui.sh — the installer's terminal interface. Sourced, never executed.
#
#   ui_init                      pick the dialog backend and colours
#   ui_banner                    logo, name, version, copyright
#   ui_menu TITLE TEXT TAG DESC…             one choice  -> prints TAG
#   ui_checklist TITLE TEXT TAG DESC on|off…  many       -> prints TAGs
#   ui_yesno TITLE TEXT [no]     ui_msg TITLE TEXT       ui_textbox TITLE FILE
#   ui_steps_begin TOTAL         ui_task LABEL CMD…      ui_steps_summary
#
# Dialogs use whiptail when it is installed (AETHER_UI=plain forces numbered
# prompts). Everything interactive talks to /dev/tty, never to stdout: in
# live mode stdout is the install log, which must stay free of escape codes.

UI_BACKEND=plain
UI_LIVE=0          # 1: progress is drawn as a live panel on the terminal
UI_TTY=/dev/tty
UI_BACKTITLE="AetherOS Dotfiles — © 2026 Neelampalli Charan Balaji"
UI_STEP_TOTAL=0
UI_STEP_N=0
UI_DONE=()
UI_FAILED=()
UI_SKIPPED=()

ui_has_tty() { [ -t 0 ] && { : > /dev/tty; } 2>/dev/null; }

ui_init() {
    UI_BACKEND=plain
    if ui_has_tty; then
        case "${AETHER_UI:-auto}" in
            plain) ;;
            *) command -v whiptail >/dev/null 2>&1 && UI_BACKEND=whiptail ;;
        esac
    fi
    if ui_has_tty && [ "${TERM:-dumb}" != dumb ] && [ -z "${NO_COLOR:-}" ]; then
        U_B=$'\033[1m'; U_D=$'\033[2m'; U_N=$'\033[0m'
        U_OK=$'\033[38;5;84m'; U_ERR=$'\033[38;5;203m'; U_WARN=$'\033[38;5;221m'
        U_ACC=$'\033[38;5;141m'; U_ACC2=$'\033[38;5;81m'
    else
        U_B=""; U_D=""; U_N=""; U_OK=""; U_ERR=""; U_WARN=""; U_ACC=""; U_ACC2=""
    fi
    case "${LANG:-}${LC_ALL:-}" in
        *UTF-8*|*utf8*) U_SPIN='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'; U_TICK='✔'; U_CROSS='✖'; U_DOT='•'; U_FULL='━'; U_EMPTY='─' ;;
        *) U_SPIN='|/-\'; U_TICK='+'; U_CROSS='x'; U_DOT='*'; U_FULL='#'; U_EMPTY='-' ;;
    esac
    # whiptail in the AetherOS colours (violet on deep blue).
    export NEWT_COLORS='root=white,black;window=white,black;border=magenta,black;title=brightmagenta,black;
textbox=white,black;button=black,magenta;actbutton=black,cyan;compactbutton=white,black;
listbox=white,black;actlistbox=black,cyan;actsellistbox=black,cyan;checkbox=white,black;
actcheckbox=black,cyan;entry=white,black;label=brightmagenta,black;emptyscale=black,black;
fullscale=cyan,black;helpline=white,black;roottext=brightmagenta,black'
}

ui_size() {  # sets UI_H / UI_W for whiptail from the terminal size
    local lines cols
    lines="$(tput lines 2>/dev/null || echo 24)"; cols="$(tput cols 2>/dev/null || echo 80)"
    UI_H=$(( lines - 4 )); [ "$UI_H" -gt 26 ] && UI_H=26; [ "$UI_H" -lt 12 ] && UI_H=12
    UI_W=$(( cols - 6 )); [ "$UI_W" -gt 84 ] && UI_W=84; [ "$UI_W" -lt 50 ] && UI_W=50
}

ui_say() { printf '%s\n' "$*" > "$UI_TTY"; }

# ── banner ──────────────────────────────────────────────────────────────
ui_banner() {
    local logo="$1" version="$2" i=0 line
    local grad=(141 135 99 105 75 81 51)
    ui_say ""
    while IFS= read -r line; do
        if [ -n "$U_N" ]; then
            printf '  \033[38;5;%sm%s\033[0m\n' "${grad[$(( i % ${#grad[@]} ))]}" "$line" > "$UI_TTY"
        else
            printf '  %s\n' "$line" > "$UI_TTY"
        fi
        i=$((i + 1))
    done < "$logo"
    ui_say ""
    ui_say "  ${U_B}AetherOS Dotfiles${U_N} ${U_ACC}v$version${U_N}  ${U_D}·  a macOS-inspired Hyprland desktop for Fedora${U_N}"
    ui_say "  ${U_D}© 2026 Neelampalli Charan Balaji · GPL-3.0-or-later · ${AETHER_REPO_WEB:-}${U_N}"
    ui_say ""
}

# ── dialogs ─────────────────────────────────────────────────────────────
# whiptail draws on stdout and answers on stderr: draw on the terminal,
# capture the answer. Cancel/Esc returns 1.
ui_whiptail() { whiptail --backtitle "$UI_BACKTITLE" "$@" 2>&1 > "$UI_TTY" < "$UI_TTY"; }

ui_menu() {
    local title="$1" text="$2"; shift 2
    if [ "$UI_BACKEND" = whiptail ]; then
        ui_size
        ui_whiptail --title " $title " --notags --menu "$text" "$UI_H" "$UI_W" $(( $# / 2 )) "$@"
        return
    fi
    local tags=() i=1 c
    ui_say ""; ui_say "${U_B}${U_ACC}$title${U_N}"; ui_say "$text"; ui_say ""
    while [ $# -gt 1 ]; do
        tags+=("$1"); ui_say "  ${U_ACC2}$i)${U_N} $2"; i=$((i + 1)); shift 2
    done
    while true; do
        printf '\n  Choose 1-%d (q to cancel): ' "${#tags[@]}" > "$UI_TTY"
        IFS= read -r c < "$UI_TTY" || return 1
        [ "$c" = q ] && return 1
        if [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -ge 1 ] && [ "$c" -le "${#tags[@]}" ]; then
            printf '%s\n' "${tags[$((c - 1))]}"; return 0
        fi
    done
}

ui_checklist() {
    local title="$1" text="$2"; shift 2
    if [ "$UI_BACKEND" = whiptail ]; then
        ui_size
        local out
        out="$(ui_whiptail --title " $title " --notags --separate-output --checklist "$text" "$UI_H" "$UI_W" $(( $# / 3 )) "$@")" || return 1
        printf '%s\n' "$out" | tr '\n' ' ' | sed 's/ *$//'; echo
        return 0
    fi
    local tags=() descs=() on=() i c n
    while [ $# -gt 2 ]; do tags+=("$1"); descs+=("$2"); [ "$3" = on ] && on+=(1) || on+=(0); shift 3; done
    n=${#tags[@]}
    while true; do
        ui_say ""; ui_say "${U_B}${U_ACC}$title${U_N}"; ui_say "$text"; ui_say ""
        for ((i = 0; i < n; i++)); do
            ui_say "  $( [ "${on[$i]}" = 1 ] && printf '[%sx%s]' "$U_OK" "$U_N" || printf '[ ]' ) ${U_ACC2}$((i + 1)))${U_N} ${descs[$i]}"
        done
        printf '\n  Numbers toggle (e.g. "2 5"), a = all, n = none, Enter = done, q = cancel: ' > "$UI_TTY"
        IFS= read -r c < "$UI_TTY" || return 1
        case "$c" in
            q) return 1 ;;
            a) for ((i = 0; i < n; i++)); do on[i]=1; done ;;
            n) for ((i = 0; i < n; i++)); do on[i]=0; done ;;
            "") break ;;
            *) for i in $c; do
                   [[ "$i" =~ ^[0-9]+$ ]] && [ "$i" -ge 1 ] && [ "$i" -le "$n" ] && on[i - 1]=$(( 1 - on[i - 1] ))
               done ;;
        esac
    done
    local sel=()
    for ((i = 0; i < n; i++)); do [ "${on[$i]}" = 1 ] && sel+=("${tags[$i]}"); done
    echo "${sel[*]}"
}

ui_yesno() {  # ui_yesno TITLE TEXT [no]  — "no" makes No the default
    if [ "$UI_BACKEND" = whiptail ]; then
        ui_size
        local def=(); [ "${3:-}" = no ] && def=(--defaultno)
        whiptail --backtitle "$UI_BACKTITLE" --title " $1 " "${def[@]}" --yesno "$2" "$UI_H" "$UI_W" > "$UI_TTY" < "$UI_TTY" 2>&1
        return
    fi
    local r hint="[Y/n]"; [ "${3:-}" = no ] && hint="[y/N]"
    ui_say ""; ui_say "${U_B}${U_ACC}$1${U_N}"; ui_say "$2"
    printf '  %s ' "$hint" > "$UI_TTY"
    IFS= read -r r < "$UI_TTY" || return 1
    case "$r" in y|Y|yes) return 0 ;; n|N|no) return 1 ;; "") [ "${3:-}" != no ] ;; *) return 1 ;; esac
}

ui_msg() {
    if [ "$UI_BACKEND" = whiptail ]; then
        ui_size
        whiptail --backtitle "$UI_BACKTITLE" --title " $1 " --msgbox "$2" "$UI_H" "$UI_W" > "$UI_TTY" < "$UI_TTY" 2>&1
        return 0
    fi
    ui_say ""; ui_say "${U_B}${U_ACC}$1${U_N}"; ui_say "$2"
    printf '  Press Enter to continue ' > "$UI_TTY"; IFS= read -r _ < "$UI_TTY" || true
}

ui_textbox() {
    if [ "$UI_BACKEND" = whiptail ]; then
        ui_size
        whiptail --backtitle "$UI_BACKTITLE" --title " $1 " --scrolltext --textbox "$2" "$UI_H" "$UI_W" > "$UI_TTY" < "$UI_TTY" 2>&1
        return 0
    fi
    if command -v less >/dev/null 2>&1; then less -R "$2" < "$UI_TTY" > "$UI_TTY"; else cat "$2" > "$UI_TTY"; fi
}

# ── live progress ───────────────────────────────────────────────────────
ui_steps_begin() { UI_STEP_TOTAL="$1"; UI_STEP_N=0; UI_DONE=(); UI_FAILED=(); UI_SKIPPED=(); }

# The panel is drawn by a background renderer that tails the task's output;
# the task itself runs in the installer's own shell, so the variables it
# sets (warnings, package lists, saved state) are kept.
ui__render() {  # ui__render OUTFILE HEADER
    local out="$1" header="$2" h=7 first=1 k=0 t0=$SECONDS
    local cols tail line pct speed size bar fill i
    cols="$(tput cols 2>/dev/null || echo 80)"; [ "$cols" -gt 110 ] && cols=110
    local w=$(( cols - 40 )); [ "$w" -lt 10 ] && w=10
    trap 'exit 0' TERM
    while true; do
        tail="$(tail -c 8000 "$out" 2>/dev/null | tr '\r' '\n' | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' | grep -v '^[[:space:]]*$' | tail -n 60)"
        # Only transfers get a bar: a percentage next to a size or speed
        # (dnf, curl) or git's object counts — not any "%" in a message.
        line="$(grep -E '[0-9]%' <<< "$tail" | grep -E '[0-9] ?[KMGT]i?B|[0-9]%[[:space:]]+[0-9.]+[kMG]?[[:space:]]|objects|deltas' | tail -n 1)"
        pct="$(grep -oE '[0-9]{1,3}(\.[0-9]+)?%' <<< "$line" | tail -n 1 | cut -d. -f1 | tr -d '%')"
        speed="$(grep -oE '[0-9]+(\.[0-9]+)? ?[KMGT]i?B/s' <<< "$tail" | tail -n 1)"
        size="$(grep -oE '[0-9]+(\.[0-9]+)? ?[KMGT]i?B( |\||$)' <<< "$line" | tail -n 1 | tr -d ' |')"
        [ "$first" = 1 ] || printf '\033[%dA' "$h" > "$UI_TTY"
        first=0
        printf '\033[2K  %s%s%s  %s%s%s %s%02d:%02d%s\n' "$U_B" "$header" "$U_N" "$U_ACC" "${U_SPIN:$(( k % ${#U_SPIN} )):1}" "$U_N" \
            "$U_D" $(( (SECONDS - t0) / 60 )) $(( (SECONDS - t0) % 60 )) "$U_N" > "$UI_TTY"
        if [ -n "$pct" ] && [ "$pct" -le 100 ] 2>/dev/null; then
            fill=$(( pct * w / 100 )); bar=""
            for ((i = 0; i < w; i++)); do if [ "$i" -lt "$fill" ]; then bar+="$U_FULL"; else bar+="$U_EMPTY"; fi; done
            printf '\033[2K  %s%s%s %3d%%  %s  %s\n' "$U_ACC2" "$bar" "$U_N" "$pct" "${speed:-}" "${size:+$size}" > "$UI_TTY"
        else
            printf '\033[2K  %sworking…%s\n' "$U_D" "$U_N" > "$UI_TTY"
        fi
        mapfile -t last < <(tail -n 4 <<< "$tail")
        for ((i = 0; i < 4; i++)); do
            printf '\033[2K  %s│ %s%s\n' "$U_D" "$(cut -c1-$(( cols - 6 )) <<< "${last[$i]:-}")" "$U_N" > "$UI_TTY"
        done
        printf '\033[2K\n' > "$UI_TTY"
        k=$((k + 1))
        sleep 0.15
    done
}

ui__clear_panel() { printf '\033[7A\033[J' > "$UI_TTY"; }

# ui_task LABEL CMD… : one numbered step, run in a subshell with errexit on
# (the first failing command fails the step; the installer carries on with
# the next one). Always returns 0: the step's exit code is in UI_LAST_RC.
# Call it as a plain statement — inside `if`/`||` bash would turn errexit
# off for the step too. Steps keep state in files, not shell variables.
UI_LAST_RC=0
ui_task() {
    local label="$1"; shift
    UI_STEP_N=$((UI_STEP_N + 1))
    local header="[$UI_STEP_N/$UI_STEP_TOTAL] $label" rc t0=$SECONDS
    echo
    echo "==> $header"
    set +e
    if [ "$UI_LIVE" -eq 1 ]; then
        local out rpid warns
        out="$(mktemp)"
        ui__render "$out" "$header" &
        rpid=$!
        ( set -e; "$@" ) > "$out" 2>&1 < /dev/null
        rc=$?
        kill "$rpid" 2>/dev/null; wait "$rpid" 2>/dev/null
        ui__clear_panel
        cat "$out"
        warns="$(grep -c 'WARN' "$out")"
        rm -f "$out"
        if [ "$rc" -eq 0 ]; then
            printf '  %s%s%s %s %s(%ss%s)%s\n' "$U_OK" "$U_TICK" "$U_N" "$header" "$U_D" "$(( SECONDS - t0 ))" \
                "$( [ "${warns:-0}" -gt 0 ] && printf ', %s warning(s)' "$warns")" "$U_N" > "$UI_TTY"
        else
            printf '  %s%s %s%s %s(exit %s — see the log)%s\n' "$U_ERR" "$U_CROSS" "$header" "$U_N" "$U_D" "$rc" "$U_N" > "$UI_TTY"
        fi
    else
        ( set -e; "$@" )
        rc=$?
        [ "$rc" -eq 0 ] || echo "  FAIL  $label (exit $rc)"
    fi
    set -e
    UI_LAST_RC=$rc
    if [ "$rc" -eq 0 ]; then UI_DONE+=("$label"); else UI_FAILED+=("$label"); fi
    return 0
}

ui_skip() { UI_SKIPPED+=("$1"); }
