# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# install-scripts/terminal.sh — the Kitty terminal (and tmux).
# Sourced by install.sh (see functions/components.sh for the contract).

comp_terminal_validate() {
    v_need terminal kitty kitty
    v_link terminal "$HOME/.config/kitty"
    [ -s "$HOME/.config/aether-shell/terminal/kitty-theme.conf" ] && v_pass terminal "kitty colour theme generated" \
        || v_warn terminal "kitty theme not generated yet (run: aether theme apply)"
}
