# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# install-scripts/audio.sh — audio (PipeWire, WirePlumber, volume and media keys).
# Sourced by install.sh (see functions/components.sh for the contract).

comp_audio_validate() {
    v_need audio wpctl wireplumber
    v_need audio pavucontrol pavucontrol
    v_need audio playerctl playerctl
    if [ -n "${XDG_RUNTIME_DIR:-}" ] && systemctl --user is-active pipewire.service >/dev/null 2>&1; then
        systemctl --user is-active wireplumber.service >/dev/null 2>&1 && v_pass audio "PipeWire and WirePlumber are running" \
            || v_warn audio "PipeWire runs but WirePlumber doesn't (systemctl --user enable --now wireplumber)"
    else
        v_pass audio "PipeWire starts with your graphical session"
    fi
}
