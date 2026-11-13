# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# install-scripts/fonts.sh — fonts (Fedora packages + JetBrainsMono Nerd Font for icons).
# Sourced by install.sh (see functions/components.sh for the contract).

comp_fonts_install() {
    [ "$INSTALL_FONTS" -eq 1 ] || return 0
    if command -v fc-list >/dev/null 2>&1 && fc-list 2>/dev/null | grep -i "Nerd Font" >/dev/null; then
        ok "A Nerd Font is installed"
        return 0
    fi
    if [ "$DRY" -eq 1 ]; then bash "$REPO_DIR/scripts/install-fonts.sh" --dry-run | sed 's/^/  /'; return 0; fi
    echo "  The bar and menu icons need a Nerd Font, which Fedora doesn't package."
    echo "  JetBrainsMono Nerd Font $(sed -n 's/^VERSION="\(.*\)"/\1/p' "$REPO_DIR/scripts/install-fonts.sh") can be downloaded from GitHub (checksum-verified) to ~/.local/share/fonts."
    if confirm "Download and install it?"; then
        with_pty bash "$REPO_DIR/scripts/install-fonts.sh" | sed 's/^/  /' || warn "font installation failed — icons will show as boxes (retry: scripts/install-fonts.sh)"
    else
        warn "No Nerd Font: icons will show as boxes. Install later with scripts/install-fonts.sh"
    fi
}

comp_fonts_validate() {
    command -v fc-list >/dev/null 2>&1 || { v_warn fonts "fontconfig missing: fonts can't be checked"; return 0; }
    fc-list 2>/dev/null | grep -qi "Nerd Font" && v_pass fonts "a Nerd Font is installed (icons)" || v_warn fonts "no Nerd Font: icons show as boxes (scripts/install-fonts.sh)"
    fc-list 2>/dev/null | grep -qi "JetBrains Mono" && v_pass fonts "JetBrains Mono installed" || v_warn fonts "JetBrains Mono missing (package: jetbrains-mono-fonts-all)"
}
