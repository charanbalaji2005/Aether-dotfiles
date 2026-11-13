# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# install-scripts/shell.sh — Zsh and the shell configuration.
# Sourced by install.sh (see functions/components.sh for the contract).

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
