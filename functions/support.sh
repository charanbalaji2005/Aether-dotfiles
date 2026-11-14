# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# functions/support.sh — the first-run "support the project" screen.
# Shown once (a marker in ~/.local/state/aether), only on a terminal.
# Nothing is opened or starred without the user choosing it.

support_marker() { echo "$(aether_state_dir)/support-shown"; }

support_screen() {
    local force="${1:-}"
    [ "$force" = always ] || [ ! -e "$(support_marker)" ] || return 0
    ui_has_tty || return 0
    mkdir -p "$(aether_state_dir)" && : > "$(support_marker)"
    local gh_ok=0 choice
    command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && gh_ok=1
    local text
    text="AetherOS Dotfiles is made by Neelampalli Charan Balaji.

It's free software (GPL-3.0-or-later). If you enjoy it, please support it:

  ⭐  Star the repository on GitHub
  🐞  Report bugs and ideas in its issue tracker
  📣  Share it with friends who love a beautiful desktop

  $AETHER_REPO_WEB

Thank you for trying it!"
    local items=(open "Open the repository in my browser")
    [ "$gh_ok" -eq 1 ] && items+=(star "Star it now with the GitHub CLI (gh, signed in)")
    items+=(later "Continue to the installer")
    choice="$(ui_menu "Support AetherOS ⭐" "$text" "${items[@]}")" || return 0
    case "$choice" in
        open)
            if [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] && command -v xdg-open >/dev/null 2>&1; then
                xdg-open "$AETHER_REPO_WEB" >/dev/null 2>&1 &
                disown 2>/dev/null || true
                ui_msg "Thank you!" "Opened $AETHER_REPO_WEB in your browser."
            else
                ui_msg "Thank you!" "Open this address in a browser:

  $AETHER_REPO_WEB"
            fi ;;
        star)
            if gh api -X PUT "/user/starred/$AETHER_REPO_SLUG" >/dev/null 2>&1; then
                ui_msg "Thank you! ⭐" "You starred $AETHER_REPO_SLUG. It really helps!"
            else
                ui_msg "Couldn't star" "The GitHub CLI couldn't star it. You can do it at:

  $AETHER_REPO_WEB"
            fi ;;
    esac
    return 0
}
