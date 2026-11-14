# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# install-scripts/wallpapers.sh — the wallpaper collection.
# Sourced by install.sh (see functions/components.sh for the contract).

# Your own wallpapers are never lost: if ~/.config/aether-shell/wallpapers
# was a folder of yours, it was moved aside; its images are copied to
# ~/Pictures/Wallpapers (never replacing a file there), which the gallery
# (Super+W) lists first.
comp_wallpapers_install() {
    [ "$DRY" -eq 1 ] && return 0
    local old
    old="$(moved_aside "$HOME/.config/aether-shell/wallpapers")"
    if [ -n "$old" ] && [ -d "$old" ] && [ ! -e "$HOME/Pictures/Wallpapers/.aether-imported-$(basename "$old")" ]; then
        copy_tree "$old" "$HOME/Pictures/Wallpapers"
        : > "$HOME/Pictures/Wallpapers/.aether-imported-$(basename "$old")"
        ok "your wallpapers were copied to ~/Pictures/Wallpapers"
    fi
}

comp_wallpapers_validate() {
    v_link wallpapers "$HOME/.config/aether-shell/wallpapers"
    local n
    n="$(find -L "$HOME/.config/aether-shell/wallpapers" "$HOME/Pictures/Wallpapers" -maxdepth 2 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null | wc -l)"
    [ "$n" -gt 0 ] && v_pass wallpapers "$n wallpapers available (Super+W)" || v_warn wallpapers "no wallpapers found"
    command -v swww >/dev/null 2>&1 && v_pass wallpapers "swww found (animated transitions)" || v_warn wallpapers "swww missing: wallpapers can't be set"
}
