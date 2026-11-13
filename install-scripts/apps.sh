# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# install-scripts/apps.sh — application configs (wlogout, wallust, fastfetch).
# Sourced by install.sh (see functions/components.sh for the contract).

comp_apps_validate() {
    v_link apps "$HOME/.config/wlogout"
    v_link apps "$HOME/.config/fastfetch"
    v_need apps wlogout wlogout
    v_need apps fastfetch fastfetch
}
