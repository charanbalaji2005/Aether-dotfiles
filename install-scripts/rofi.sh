# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# install-scripts/rofi.sh — the Rofi launchpad and menus.
# Sourced by install.sh (see functions/components.sh for the contract).

comp_rofi_validate() {
    v_need rofi rofi "rofi-wayland or rofi"
    v_link rofi "$HOME/.config/rofi"
    command -v rofi >/dev/null 2>&1 || return 0
    local t bad=""
    for t in "$HOME"/.config/rofi/themes/*.rasi; do
        [ -f "$t" ] || continue
        # rofi exits 0 even for a broken theme; its warning is the signal.
        [ "$(rofi -theme "$t" -dump-theme 2>&1 >/dev/null | grep -ci 'failed to parse\|error')" -gt 0 ] && bad+=" $(basename "$t")"
    done
    [ -z "$bad" ] && v_pass rofi "every theme parses" || v_fail rofi "themes that don't parse:$bad"
}
