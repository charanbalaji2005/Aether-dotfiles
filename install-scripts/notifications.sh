# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# install-scripts/notifications.sh — notifications (SwayNC).
# Sourced by install.sh (see functions/components.sh for the contract).

comp_notifications_validate() {
    v_need notifications swaync SwayNotificationCenter
    v_link notifications "$HOME/.config/swaync"
    python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$HOME/.config/swaync/config.json" 2>/dev/null \
        && v_pass notifications "config.json parses" || v_fail notifications "~/.config/swaync/config.json doesn't parse"
}
