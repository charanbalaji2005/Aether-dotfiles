# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# install-scripts/shell.sh — Zsh and the shell configuration.
# Sourced by install.sh (see functions/components.sh for the contract).

# zsh as the login shell: only with a yes (onboarding) or --auto.
comp_shell_install() {
    [ "${MAKE_ZSH_DEFAULT:-0}" -eq 1 ] || return 0
    local zsh; zsh="$(command -v zsh 2>/dev/null || true)"
    [ -n "$zsh" ] || { warn "zsh is not installed: login shell left as is"; return 0; }
    [ "$(getent passwd "$USER" | cut -d: -f7)" = "$zsh" ] && { ok "zsh is already your login shell"; return 0; }
    run sudo usermod -s "$zsh" "$USER" && ok "zsh is your login shell from your next login"
}

comp_shell_validate() {
    v_need shell zsh zsh
    if [[ "$(readlink -f "$HOME/.zshrc" 2>/dev/null)" == "$REPO_DIR"/* ]]; then
        zsh -n "$HOME/.zshrc" 2>/dev/null && v_pass shell "~/.zshrc (AetherOS) parses" || v_fail shell "~/.zshrc has a syntax error"
    else
        v_pass shell "your own ~/.zshrc was kept (AetherOS's: config/zsh/.zshrc)"
    fi
    [ "$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)" = "$(command -v zsh 2>/dev/null)" ] \
        || v_warn shell "zsh is not your login shell — switch with: chsh -s $(command -v zsh 2>/dev/null || echo /usr/bin/zsh)"
}
