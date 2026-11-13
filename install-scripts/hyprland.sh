# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# install-scripts/hyprland.sh — the Hyprland configuration.
# Sourced by install.sh (see functions/components.sh for the contract).

# What a moved-aside ~/.config/hypr held that is personal is carried over:
# its scripts/ folder is copied next to AetherOS's settings, and its
# keybinds are appended (commented out) to ~/.config/aether-shell/hypr/user.conf,
# which hyprland.conf sources last. Nothing is activated without you.
comp_hyprland_install() {
    [ "$DRY" -eq 1 ] && { info "would import scripts and keybinds from a moved-aside ~/.config/hypr"; return 0; }
    local old user marker binds n
    old="$(moved_aside "$HOME/.config/hypr")"
    [ -n "$old" ] && [ -d "$old" ] || return 0
    user="$HOME/.config/aether-shell/hypr/user.conf"
    marker="# Imported from $old"
    grep -qF "$marker" "$user" 2>/dev/null && return 0
    if [ -d "$old/scripts" ]; then
        copy_tree "$old/scripts" "$HOME/.config/aether-shell/user/hypr-scripts"
        ok "your Hyprland scripts are kept in ~/.config/aether-shell/user/hypr-scripts"
    fi
    binds="$(find "$old" -maxdepth 3 -name '*.conf' -exec grep -hE '^[[:space:]]*bind[a-z]*[[:space:]]*=' {} + 2>/dev/null | sed 's/^[[:space:]]*//' | awk '!seen[$0]++')"
    if [ -n "$binds" ]; then
        n="$(wc -l <<< "$binds")"
        mkdir -p "$(dirname "$user")"
        {
            echo
            echo "$marker — $n keybind(s), commented out."
            echo "# Uncomment the ones you want (define any \$variables they use), then check: aether-bindings check"
            sed 's/^/# /' <<< "$binds"
        } >> "$user"
        ok "$n of your keybinds saved (commented out) in ~/.config/aether-shell/hypr/user.conf"
    fi
}

comp_hyprland_validate() {
    v_need hyprland Hyprland hyprland
    v_link hyprland "$HOME/.config/hypr"
    local frag missing=""
    for frag in hardware compat profile theme interface user; do
        [ -f "$HOME/.config/aether-shell/hypr/$frag.conf" ] || missing+=" $frag.conf"
    done
    [ -z "$missing" ] && v_pass hyprland "every sourced fragment exists" || v_fail hyprland "missing fragments:$missing (run: aether repair)"
    if command -v python3 >/dev/null 2>&1; then
        if aether hyprland >/dev/null 2>&1; then v_pass hyprland "configuration validates (aether hyprland)"
        else v_warn hyprland "aether hyprland reported problems — run it to see them"; fi
    fi
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && [ -s "$(aether_state_dir)/hypr-lua.log" ]; then
        local p; p="$(head -n1 "$(aether_state_dir)/hypr-lua.log" | grep -oE '[0-9]+ problem' | cut -d' ' -f1)"
        [ "${p:-0}" -eq 0 ] && v_pass hyprland "running Hyprland loaded the config without problems" \
            || v_warn hyprland "running Hyprland reported $p problem(s): ~/.local/state/aether/hypr-lua.log"
    fi
}
