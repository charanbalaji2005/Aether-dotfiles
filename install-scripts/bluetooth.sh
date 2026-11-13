# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# install-scripts/bluetooth.sh — Bluetooth (BlueZ + Blueman).
# Sourced by install.sh (see functions/components.sh for the contract).

# Enabling the system bluetooth service needs root: done only when you said
# yes to it (onboarding) or passed --yes, never otherwise; a "no" in the
# onboarding is kept even with --yes.
comp_bluetooth_install() {
    command -v systemctl >/dev/null 2>&1 || return 0
    systemctl is-enabled bluetooth.service >/dev/null 2>&1 && { ok "bluetooth.service already enabled"; return 0; }
    systemctl cat bluetooth.service >/dev/null 2>&1 || { info "bluetooth.service not installed yet (package: bluez)"; return 0; }
    # ENABLE_BLUETOOTH: 1 yes, 0 no (both from the onboarding), empty: ask.
    if [ "${ENABLE_BLUETOOTH:-}" = 1 ] || { [ -z "${ENABLE_BLUETOOTH:-}" ] && confirm "Enable and start the Bluetooth service (sudo systemctl enable --now bluetooth)?"; }; then
        run sudo systemctl enable --now bluetooth.service && ok "bluetooth.service enabled"
    else
        info "Bluetooth service left as is (enable later: sudo systemctl enable --now bluetooth)"
    fi
}

comp_bluetooth_validate() {
    v_need bluetooth bluetoothctl bluez
    v_need bluetooth blueman-manager blueman
    systemctl is-enabled bluetooth.service >/dev/null 2>&1 && v_pass bluetooth "bluetooth.service enabled" \
        || v_warn bluetooth "bluetooth.service not enabled (sudo systemctl enable --now bluetooth)"
}
