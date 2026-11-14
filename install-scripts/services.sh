# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# install-scripts/services.sh — per-machine configuration and systemd user
# services. Sourced by install.sh.

do_configure() {
    step "Per-machine configuration"
    if ! command -v python3 >/dev/null 2>&1; then warn "python3 missing: hardware detection and settings migration skipped."; return 0; fi
    if [ "$DRY" -eq 1 ]; then
        info "would run: aether-interface set $INTERFACE (select the interface, its services and colours)"
        info "would run: aether config migrate         (upgrade settings from an older AetherOS)"
        info "would run: aether hyprland compat        (rules/gestures for the installed Hyprland)"
        info "would run: aether graphics configure     (GPU environment for this machine)"
        info "would run: aether theme apply            (terminal + border colours)"
        info "would run: aether idle apply             (hypridle timings)"
        info "would run: scripts/build-shaders.sh      (compile shaders for the installed Qt)"
        return 0
    fi
    try_step "aether-interface set $INTERFACE" bash "$REPO_DIR/scripts/bin/aether-interface" set "$INTERFACE" --no-reload
    aether config migrate || warn "settings migration reported a problem (aether config validate)"
    try_step "aether hyprland compat" aether hyprland compat
    # --yes: hardware.conf is AetherOS's own fragment (backed up before each write);
    # without it the unattended run can't answer the "Write this file?" question.
    try_step "aether graphics configure" aether graphics configure --yes
    try_step "aether theme apply" aether theme apply
    try_step "aether idle apply" aether idle apply
    bash "$REPO_DIR/scripts/build-shaders.sh" || warn "shaders not compiled locally: bundled ones are used, with a non-shader fallback"
    try_step "aether hardware" aether hardware
    # NVIDIA: only ever a *plan* here; the installer for it asks separately.
    if [ "$OS_ID" = "fedora" ] && grep -qs "^PCI_ID=10DE:" /sys/bus/pci/devices/*/uevent && [ ! -d /sys/module/nvidia ]; then
        echo
        info "An NVIDIA GPU without the proprietary driver was detected (nouveau or none)."
        info "Nothing was installed or replaced. Review the plan with: aether graphics install-nvidia --dry-run"
    fi
}

# No login manager at all (minimal installs): SDDM, when the user agreed.
# It is enabled, not started — starting it would end the console session.
enable_sddm() {
    [ "${INSTALL_SDDM:-0}" -eq 1 ] && [ "${DET_DM:-none}" = none ] || return 0
    command -v sddm >/dev/null 2>&1 || { warn "SDDM was not installed: start Hyprland from a console with: Hyprland"; return 0; }
    run sudo systemctl enable sddm.service && run sudo systemctl set-default graphical.target \
        && ok "SDDM enabled: the login screen appears at your next boot (choose Hyprland)"
}

do_services() {
    enable_sddm
    step "systemd user services"
    local units=() u
    for u in "$REPO_DIR"/system/systemd/*.service; do
        # Units without [Install] (the safe-mode fallback) are started on demand.
        grep -q '^\[Install\]' "$u" || continue
        # The classic interface runs its own idle daemon and no Quickshell.
        if [ "$INTERFACE" = classic ]; then
            case "$(basename "$u")" in aether-shell.service|aether-idle.service) continue ;; esac
        fi
        units+=("$(basename "$u")")
    done
    if [ "$DRY" -eq 1 ]; then info "would enable: ${units[*]}"; return 0; fi
    if systemctl --user daemon-reload 2>/dev/null; then
        if systemctl --user enable "${units[@]}"; then
            ok "enabled: ${units[*]}"
        else
            warn "systemctl --user enable failed for: ${units[*]} — enable them after logging in: systemctl --user enable ${units[*]}"
        fi
    else
        info "No systemd user session right now; Hyprland starts the services on first login."
    fi
}
