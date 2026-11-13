# shellcheck shell=bash
# ULTRON RECOVERY — full diagnostics: system facts plus every component's
# checks, printed and written to a report in $UR_REPORT_DIR. Read-only.

system_info() {
    ui_step "System"
    ui_kv "OS" "$(det_os)"
    ui_kv "Kernel" "$(det_kernel)"
    ui_kv "CPU" "$(det_cpu) ($(det_cores) threads)"
    ui_kv "Memory" "$(det_mem)"
    local g; while IFS= read -r g; do ui_kv "GPU" "$g"; done < <(det_gpus)
    ui_kv "NVIDIA" "$(det_nvidia)"
    ui_kv "AMD" "$(det_amd)"
    ui_kv "Session" "$(det_session)"
    ui_kv "Disk" "$(det_disk)"
    ui_kv "Network" "$(det_network)"
    ui_step "Desktop components"
    local c v
    for c in hyprland waybar rofi quickshell kitty playerctl; do
        v="$(det_version "$c")"
        if [ -n "$v" ]; then ui_kv "$c" "${C_GREEN}$v${C_RESET}"; else ui_kv "$c" "${C_RED}not installed${C_RESET}"; fi
    done
    ui_kv "Dotfiles repo" "${UR_REPO:-not found (repairs use backups only)}"
    ui_step "Fonts"
    local f; while IFS= read -r f; do
        case "$f" in *MISSING) ui_warn "$f" ;; *optional*) ui_info "$f" ;; *) ui_ok "$f" ;; esac
    done < <(det_fonts)
}

diagnostics_run() {
    local report c f
    mkdir -p "$UR_REPORT_DIR"
    report="$UR_REPORT_DIR/diagnostics-$(date +%Y%m%d-%H%M%S).txt"
    problems_reset
    {
        system_info
        ui_step "Failed user services"
        # app-NAME@<id>.service transient units: one line per app
        f="$(det_failed_services | sed -E 's/^(app-[^@]+@)[0-9a-f]+(\.service)$/\1…\2/' | sort | uniq -c | awk '{ print ($1 > 1 ? $2 " (" $1 " instances)" : $2) }')"
        if [ -n "$f" ]; then while IFS= read -r c; do problem system "failed user service: $c"; done <<< "$f"
        else ui_ok "none"; fi
        det_disk_low && problem system "less than 1 GiB free in your home filesystem"
        for c in "${UR_COMPONENTS[@]}"; do
            ui_step "Check: $(component_title "$c")"
            component_check "$c"
        done
        diagnostics_summary
        echo "${#UR_PROBLEMS[@]}" > "$report.count"
    } 2>&1 | tee >(sed 's/\x1b\[[0-9;]*[mHJK]//g' > "$report")
    # The block ran in a subshell (the pipe): its problem count comes back by file.
    UR_DIAG_PROBLEMS="$(cat "$report.count" 2>/dev/null || echo 0)"; rm -f "$report.count"
    echo
    log_ok "Report saved: $report"
    UR_LAST_REPORT="$report"
}

diagnostics_summary() {
    ui_step "Summary"
    if [ "${#UR_PROBLEMS[@]}" -eq 0 ]; then
        ui_ok "No problems found."
    else
        ui_warn "${#UR_PROBLEMS[@]} problem(s) found:"
        local p; for p in "${UR_PROBLEMS[@]}"; do printf '      %s\n' "$p"; done
        echo
        ui_info "Repair: ultron-recovery --repair COMPONENT   (preview first with --dry-run)"
    fi
}
