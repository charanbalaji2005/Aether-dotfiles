# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# install-scripts/login-manager.sh — the login screen theme (SDDM only).
# Sourced by install.sh (see functions/components.sh for the contract).

# Only SDDM is themed, and only with your explicit yes: the theme is copied
# to /usr/share/sddm/themes/aether and selected by a drop-in,
# /etc/sddm.conf.d/10-aetheros.conf — delete that one file to undo. GDM and
# other display managers are never modified, and no display manager is
# installed or switched.
SDDM_THEME_DIR=/usr/share/sddm/themes/aether
SDDM_DROPIN=/etc/sddm.conf.d/10-aetheros.conf

comp_login_manager_install() {
    if [ "${DET_DM:-none}" != sddm ]; then
        info "Login manager: ${DET_DM:-none} — only SDDM can be themed; it was left exactly as it is."
        return 0
    fi
    if [ "${ENABLE_SDDM_THEME:-0}" -ne 1 ] && ! confirm_explicit "Install the AetherOS SDDM theme (sudo; undo by deleting $SDDM_DROPIN)?"; then
        info "SDDM theme not installed."
        return 0
    fi
    run sudo mkdir -p "$SDDM_THEME_DIR" /etc/sddm.conf.d
    run sudo cp -r "$REPO_DIR/assets/sddm/aether/." "$SDDM_THEME_DIR/"
    local wall; wall="$(find "$REPO_DIR/theme/wallpapers" -maxdepth 1 -iname '*.jpg' | sort | head -n1)"
    [ -n "$wall" ] && run sudo cp "$wall" "$SDDM_THEME_DIR/background.jpg"
    if [ "$DRY" -eq 0 ]; then
        printf '# Written by the AetherOS installer. Delete this file to restore your previous theme.\n[Theme]\nCurrent=aether\n' \
            | sudo tee "$SDDM_DROPIN" >/dev/null
        state_set sddm_theme "$SDDM_DROPIN"
    else
        info "would write $SDDM_DROPIN ([Theme] Current=aether)"
    fi
    ok "SDDM theme installed (shown at your next login)"
}

comp_login_manager_validate() {
    [ "${DET_DM:-none}" = sddm ] || { v_pass login-manager "${DET_DM:-no} login manager: left untouched (only SDDM is themed)"; return 0; }
    [ -f "$SDDM_THEME_DIR/Main.qml" ] && [ -f "$SDDM_DROPIN" ] && v_pass login-manager "SDDM theme installed and selected" \
        || v_warn login-manager "SDDM theme not installed"
}
