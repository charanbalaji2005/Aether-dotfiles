# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# install-scripts/dynamic-island.sh — the Dynamic Island (a Quickshell layer over the bar).
# Sourced by install.sh (see functions/components.sh for the contract).

comp_dynamic_island_validate() {
    v_link dynamic-island "$HOME/.config/quickshell/island"
    if command -v qs >/dev/null 2>&1 || command -v quickshell >/dev/null 2>&1; then
        v_pass dynamic-island "Quickshell found: the animated island is used"
    else
        v_warn dynamic-island "Quickshell not installed: the simpler Waybar island is used instead"
    fi
    command -v playerctl >/dev/null 2>&1 && v_pass dynamic-island "playerctl found (media controls)" \
        || v_warn dynamic-island "playerctl missing: the island can't show music"
}
