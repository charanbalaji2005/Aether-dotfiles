# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# functions/validate.sh — post-install checks and the installation report.
# Sourced, never executed. Read-only.
#
#   v_pass/v_warn/v_fail COMPONENT MESSAGE   record a result
#   v_need COMPONENT COMMAND PACKAGE         a required program
#   v_link COMPONENT PATH                    a deployed symlink is intact
#   validate_all                             every selected component + global checks
#   write_report FILE                        the report (system, components, results)

V_RESULTS=""   # lines: LEVEL<TAB>component<TAB>message
V_FAILS=0; V_WARNS=0

v__add() {
    V_RESULTS+="$1"$'\t'"$2"$'\t'"$3"$'\n'
    case "$1" in
        PASS) printf '  %sPASS%s  %-15s %s\n' "${G:-}" "${N:-}" "$2" "$3" ;;
        WARN) V_WARNS=$((V_WARNS + 1)); printf '  %sWARN%s  %-15s %s\n' "${Y:-}" "${N:-}" "$2" "$3" ;;
        FAIL) V_FAILS=$((V_FAILS + 1)); printf '  %sFAIL%s  %-15s %s\n' "${R:-}" "${N:-}" "$2" "$3" ;;
    esac
}
v_pass() { v__add PASS "$1" "$2"; }
v_warn() { v__add WARN "$1" "$2"; }
v_fail() { v__add FAIL "$1" "$2"; }

v_need() {
    if command -v "$2" >/dev/null 2>&1; then v_pass "$1" "$2 found"
    else v_fail "$1" "$2 not installed (package: $3)"; fi
}

v_link() {
    local p="$2"
    if [ -L "$p" ] && [ -e "$p" ]; then
        [[ "$(readlink -f "$p")" == "$REPO_DIR"/* ]] && v_pass "$1" "${p/#$HOME/\~} deployed" || v_pass "$1" "${p/#$HOME/\~} is yours (kept)"
    elif [ -L "$p" ]; then v_fail "$1" "${p/#$HOME/\~} is a broken symlink"
    elif [ -e "$p" ]; then v_warn "$1" "${p/#$HOME/\~} exists but is not AetherOS's"
    else v_fail "$1" "${p/#$HOME/\~} is missing"; fi
}

# Every managed path that is a dangling symlink.
v_broken_links() {
    local rel broken=""
    while IFS= read -r rel; do
        [ -L "$HOME/$rel" ] && [ ! -e "$HOME/$rel" ] && broken+=" ~/$rel"
    done < <(aether_targets_rel)
    [ -z "$broken" ] && v_pass system "no broken symlinks at the managed paths" || v_fail system "broken symlinks:$broken (run: aether repair)"
}

# Programs started twice: by two exec-once lines, by exec-once and an enabled
# user service, or (in a running session) more than once right now.
v_duplicate_startup() {
    local files=() f cmds dups
    for f in "$HOME"/.config/hypr/*.conf "$HOME"/.config/hypr/interfaces/"$INTERFACE".conf "$HOME"/.config/aether-shell/hypr/*.conf; do
        [ -f "$f" ] && files+=("$f")
    done
    [ ${#files[@]} -gt 0 ] || return 0
    # Each exec-once command, whitespace-normalised: two identical lines start
    # the same thing twice (different subcommands of one program don't).
    local lines
    lines="$(grep -hE '^[[:space:]]*exec-once[[:space:]]*=' "${files[@]}" 2>/dev/null \
        | sed -E 's/^[^=]*=[[:space:]]*//; s/[[:space:]]+#.*$//; s/[[:space:]]+/ /g; s/ $//')"
    dups="$(sort <<< "$lines" | uniq -d | awk 'NF' | paste -sd ';' - | sed 's/;/ ; /g')"
    # The program names, for the service check below.
    cmds="$(sed -E 's/^(env [^ ]+ )+//; s/^([A-Za-z_]+=[^ ]+ )+//' <<< "$lines" | awk '{print $1}' | sed 's|.*/||')"
    [ -z "${dups// }" ] && v_pass system "no program is started twice by exec-once" || v_warn system "started by more than one exec-once: $dups"
    local unit prog
    for unit in waybar swaync hypridle; do
        systemctl --user is-enabled "$unit.service" >/dev/null 2>&1 || continue
        prog="$unit"
        # The classic desktop always starts its own Waybar (aether-classic-start).
        if grep -qx "$prog" <<< "$cmds" || { [ "$INTERFACE" = classic ] && [ "$prog" = waybar ]; }; then
            v_warn system "$unit.service is enabled and AetherOS starts $prog too — disable one: systemctl --user disable $unit.service"
        fi
    done
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        local p n daemons=""
        for p in swaync hypridle; do
            n="$(pgrep -u "$(id -u)" -xc "$p" 2>/dev/null || true)"
            [ "${n:-0}" -gt 1 ] && v_warn system "$p is running $n times (restart the desktop: Super+Ctrl+R)"
        done
        for p in swaync mako dunst; do pgrep -u "$(id -u)" -x "$p" >/dev/null 2>&1 && daemons+=" $p"; done
        [ "$(wc -w <<< "$daemons")" -gt 1 ] && v_warn system "more than one notification daemon is running:$daemons"
    fi
    return 0
}

validate_all() {
    V_RESULTS=""; V_FAILS=0; V_WARNS=0
    local id fn
    for id in $COMPONENTS; do
        fn="$(comp_fn "$id" validate)"
        # A check that breaks is reported, never fatal: the other checks still run.
        [ -z "$fn" ] || "$fn" || v_warn "$id" "a check could not finish (exit $?)"
    done
    v_broken_links || true
    v_duplicate_startup || true
    if command -v python3 >/dev/null 2>&1; then
        aether config validate >/dev/null 2>&1 && v_pass system "AetherOS settings validate" || v_warn system "settings problems: run aether config validate"
    fi
    return 0
}

write_report() {
    local file="$1" id
    mkdir -p "$(dirname "$file")"
    {
        echo "AetherOS Dotfiles $AETHER_VERSION — installation report"
        echo "© 2026 Neelampalli Charan Balaji · $AETHER_REPO_WEB"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')   Interface: $INTERFACE   Mode: $MODE"
        echo
        echo "== System"
        detect_summary
        echo
        echo "== Components"
        for id in $(comp_list "$INTERFACE"); do
            if [[ " ${UI_FAILED[*]-} " == *" $(comp_step "$id") "* ]]; then echo "  FAILED     $id"
            elif [[ " $COMPONENTS " == *" $id "* ]]; then echo "  installed  $id"
            else echo "  skipped    $id"; fi
        done
        echo
        echo "== Validation ($V_FAILS failed, $V_WARNS warning(s))"
        printf '%s' "$V_RESULTS" | awk -F'\t' 'NF {printf "  %-5s %-15s %s\n", $1, $2, $3}'
        echo
        echo "== Files"
        echo "  Backup archive:   $(state_get last_backup)"
        echo "  Moved-aside list: $(aether_manifest)"
        echo "  Install log:      ${LOG_FILE:-}"
    } > "$file"
}
