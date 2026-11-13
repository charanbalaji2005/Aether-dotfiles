# shellcheck shell=bash
# ULTRON RECOVERY — Quickshell & dock: installation, configs (shell.qml and
# QML syntax), links into the dotfiles repo, startup integration, the dock.

QS_DIR="$HOME/.config/quickshell"

mod_quickshell_paths() { echo "$QS_DIR"; }
mod_quickshell_deps()  { printf '%s\n' "qs:quickshell" "python3:python3" "busctl:systemd"; }

qs_bin() { command -v qs || command -v quickshell; }

mod_quickshell_check() {
    local p0=${#UR_PROBLEMS[@]} d out
    qs_bin >/dev/null || problem quickshell "Quickshell is not installed (see INSTALLATION.md: COPR errornointernet/quickshell)"
    [ -d "$QS_DIR" ] || { problem quickshell "~/.config/quickshell is missing"; return; }
    for d in aether-shell island; do
        if [ -L "$QS_DIR/$d" ] && [ ! -e "$QS_DIR/$d" ]; then problem quickshell "broken link ~/.config/quickshell/$d → $(readlink "$QS_DIR/$d")"
        elif [ ! -e "$QS_DIR/$d" ]; then
            [ -n "${UR_REPO:-}" ] && [ -d "$UR_REPO/config/quickshell/$d" ] && problem quickshell "~/.config/quickshell/$d is missing"
        elif [ ! -f "$QS_DIR/$d/shell.qml" ]; then problem quickshell "~/.config/quickshell/$d has no shell.qml"
        fi
    done
    out="$(validate_qml_tree "$QS_DIR" 2>&1)" || while IFS= read -r d; do problem quickshell "QML syntax: ${d/#$HOME/\~}"; done <<< "$out"
    local l; while IFS= read -r l; do problem quickshell "broken link: ${l/#$HOME/\~}"; done < <(broken_symlinks "$QS_DIR" 2)

    # Startup: Hyprland must start the interface (classic: aether-classic-start; aether: qs -c aether-shell).
    if [ -d "$HOME/.config/hypr" ] && ! grep -rqsE 'aether-classic-start|qs (-n )?(-d )?-c aether-shell|aether shell start|aether autostart' "$HOME/.config/hypr"/*.conf "$HOME/.config/hypr/interfaces" 2>/dev/null; then
        problem quickshell "Hyprland does not start the AetherOS interface (no aether-classic-start / aether-shell in exec-once)"
    fi
    # Dock (classic home look): aether-dock runs a native dock window.
    if command -v aether-dock >/dev/null 2>&1 && grep -qs '^look=home' "$HOME/.config/aether-shell/classic/state.conf" && det_hypr_running; then
        pgrep -f 'dock_app|aether-dock' >/dev/null 2>&1 || problem quickshell "the dock is not running (home look)"
    fi
    [ "${#UR_PROBLEMS[@]}" -eq "$p0" ] && check_ok "Quickshell: installed, configs and QML syntax valid, startup wired"
    return 0
}

mod_quickshell_repair() {
    mkdir -p "$QS_DIR" 2>/dev/null || true
    local d
    for d in aether-shell island; do repair_link "$QS_DIR/$d" "config/quickshell/$d"; repair_deleted_tracked "config/quickshell/$d"; done
    repair_broken_links "$QS_DIR"
    repair_full_restore quickshell config/quickshell
    if command -v aether-dock >/dev/null 2>&1 && grep -qs '^look=home' "$HOME/.config/aether-shell/classic/state.conf" && det_hypr_running \
        && ! pgrep -f 'dock_app|aether-dock' >/dev/null 2>&1; then
        change "start the dock" aether-dock run
    fi
}
