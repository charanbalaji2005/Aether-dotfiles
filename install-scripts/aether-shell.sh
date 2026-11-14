# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# install-scripts/aether-shell.sh — the Quickshell desktop (the "aether" interface).
# Sourced by install.sh (see functions/components.sh for the contract).

comp_aether_shell_validate() {
    v_link aether-shell "$HOME/.config/quickshell/aether-shell"
    local qsv
    if command -v qs >/dev/null 2>&1 || command -v quickshell >/dev/null 2>&1; then
        qsv="$( (qs --version 2>/dev/null || quickshell --version 2>/dev/null) | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
        if [ -n "$qsv" ] && [ "$(printf '%s\n%s\n' "$MIN_QUICKSHELL" "$qsv" | sort -V | head -1)" = "$MIN_QUICKSHELL" ]; then
            v_pass aether-shell "Quickshell $qsv (>= $MIN_QUICKSHELL)"
        else
            v_fail aether-shell "Quickshell ${qsv:-?} is older than $MIN_QUICKSHELL"
        fi
    else
        v_fail aether-shell "Quickshell is not installed: the shell can't start (./install.sh --install builds it on request)"
    fi
    [ -s "$HOME/.config/quickshell/aether-shell/shell.qml" ] && v_pass aether-shell "shell.qml present" || v_fail aether-shell "shell.qml missing"
}
