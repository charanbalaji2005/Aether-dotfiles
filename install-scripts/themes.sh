# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# install-scripts/themes.sh — GTK themes and icons.
# Sourced by install.sh (see functions/components.sh for the contract).

comp_themes_validate() {
    local f
    for f in gtk-3.0/settings.ini gtk-4.0/settings.ini; do v_link themes "$HOME/.config/$f"; done
    local theme icons
    theme="$(sed -n 's/^gtk-theme-name *= *//p' "$HOME/.config/gtk-3.0/settings.ini" 2>/dev/null | head -1)"
    icons="$(sed -n 's/^gtk-icon-theme-name *= *//p' "$HOME/.config/gtk-3.0/settings.ini" 2>/dev/null | head -1)"
    # Adwaita and HighContrast are built into GTK itself (no theme folder).
    case "$theme" in Adwaita|Adwaita-dark|HighContrast|HighContrastInverse) theme="" ;; esac
    [ -z "$theme" ] || [ -d "/usr/share/themes/$theme" ] || [ -d "$HOME/.themes/$theme" ] || [ -d "$HOME/.local/share/themes/$theme" ] \
        && v_pass themes "GTK theme ${theme:-default} is installed" || v_warn themes "GTK theme '$theme' is not installed (package: adw-gtk3-theme)"
    [ -z "$icons" ] || [ -d "/usr/share/icons/$icons" ] || [ -d "$HOME/.local/share/icons/$icons" ] || [ -d "$HOME/.icons/$icons" ] \
        && v_pass themes "icon theme ${icons:-default} is installed" || v_warn themes "icon theme '$icons' is not installed (package: papirus-icon-theme)"
}
