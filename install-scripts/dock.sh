# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# install-scripts/dock.sh — the macOS-style dock (GTK layer-shell, lib/aether/dock_app.py).
# Sourced by install.sh (see functions/components.sh for the contract).

comp_dock_install() {
    [ "$DRY" -eq 1 ] && { info "would run: aether-dock generate"; return 0; }
    bash "$REPO_DIR/scripts/bin/aether-dock" generate >/dev/null && ok "dock modules generated (pin apps with: aether-dock add APP)"
}

comp_dock_validate() {
    if python3 -c 'import gi; gi.require_version("Gtk", "3.0"); gi.require_version("GtkLayerShell", "0.1"); from gi.repository import Gtk, GtkLayerShell' >/dev/null 2>&1; then
        v_pass dock "GTK 3 and gtk-layer-shell bindings load"
    else
        v_fail dock "GTK 3 / gtk-layer-shell Python bindings missing (packages: python3-gobject gtk-layer-shell)"
    fi
}
