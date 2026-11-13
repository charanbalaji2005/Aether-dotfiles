# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# functions/detect.sh — what this machine is. Sourced, never executed.
# Read-only: nothing here changes the system or needs root.
#
#   detect_system      fills the DET_* variables below
#   detect_summary     a human-readable summary (welcome screen, report)
#   detect_gpu_packages  extra, optional packages that suit the GPUs found
#
# GPU policy: drivers are never installed or replaced here. Only userspace
# helpers for a driver that is ALREADY in use are suggested, and all of them
# are optional ("?") — skipped quietly if your repositories don't have them.

detect_system() {
    DET_OS="unknown"; DET_OS_ID="unknown"; DET_OS_VERSION="0"
    if [ -r /etc/os-release ]; then
        # shellcheck source=/dev/null
        DET_OS="$(. /etc/os-release; echo "${PRETTY_NAME:-${NAME:-unknown}}")"
        # shellcheck source=/dev/null
        DET_OS_ID="$(. /etc/os-release; echo "${ID:-unknown}")"
        # shellcheck source=/dev/null
        DET_OS_VERSION="$(. /etc/os-release; echo "${VERSION_ID:-0}")"
    fi
    DET_KERNEL="$(uname -r)"
    DET_ARCH="$(uname -m)"

    DET_CPU="$(sed -n 's/^model name[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo 2>/dev/null | head -n1)"
    [ -n "$DET_CPU" ] || DET_CPU="$(lscpu 2>/dev/null | sed -n 's/^Model name:[[:space:]]*//p' | head -n1)"
    DET_CPU="${DET_CPU:-unknown} ($(nproc 2>/dev/null || echo '?') threads)"

    local kb_total kb_avail
    kb_total="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)"
    kb_avail="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)"
    DET_RAM_MB=$(( ${kb_total:-0} / 1024 ))
    DET_RAM="$(awk -v t="${kb_total:-0}" -v a="${kb_avail:-0}" 'BEGIN { printf "%.1f GiB total, %.1f GiB available", t/1048576, a/1048576 }')"

    # GPUs: vendor from the PCI ID, the driver actually bound to it.
    DET_GPUS=(); DET_GPU_VENDORS=""
    local dev class vendor driver name
    for dev in /sys/bus/pci/devices/*; do
        class="$(cat "$dev/class" 2>/dev/null)"
        case "$class" in 0x0300*|0x0302*|0x0380*) ;; *) continue ;; esac
        vendor="$(cat "$dev/vendor" 2>/dev/null)"
        driver="$(basename "$(readlink -f "$dev/driver" 2>/dev/null)" 2>/dev/null)"
        [ "$driver" = driver ] || [ -z "$driver" ] && driver="none"
        name=""
        # "00:02.0 VGA compatible controller: Intel … (rev 04)" -> "Intel …"
        command -v lspci >/dev/null 2>&1 && name="$(lspci -s "$(basename "$dev")" 2>/dev/null | cut -d: -f3- | sed 's/^ *//; s/ (rev [0-9a-f]*)$//')"
        case "$vendor" in
            0x10de) DET_GPU_VENDORS+=" nvidia"; name="${name:-NVIDIA GPU}" ;;
            0x1002) DET_GPU_VENDORS+=" amd"; name="${name:-AMD GPU}" ;;
            0x8086) DET_GPU_VENDORS+=" intel"; name="${name:-Intel GPU}" ;;
            *) name="${name:-GPU $vendor}" ;;
        esac
        DET_GPUS+=("$name [driver: $driver]")
    done
    [ ${#DET_GPUS[@]} -gt 0 ] || DET_GPUS=("none detected")
    DET_NVIDIA_DRIVER=0
    [ -d /sys/module/nvidia ] && DET_NVIDIA_DRIVER=1

    # Display resolution: Hyprland's view when running, else the DRM modes.
    DET_RES=""
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
        DET_RES="$(hyprctl -j monitors 2>/dev/null | python3 -I -c 'import json,sys
try: print(", ".join("%s %dx%d@%.0fHz" % (m["name"], m["width"], m["height"], m["refreshRate"]) for m in json.load(sys.stdin)))
except Exception: pass' 2>/dev/null)"
    fi
    if [ -z "$DET_RES" ]; then
        local c
        for c in /sys/class/drm/card*-*; do
            [ "$(cat "$c/status" 2>/dev/null)" = connected ] || continue
            local conn="${c##*/}"; conn="${conn#card*-}"   # card1-eDP-1 -> eDP-1
            DET_RES+="${DET_RES:+, }$conn $(head -n1 "$c/modes" 2>/dev/null)"
        done
    fi
    DET_RES="${DET_RES:-unknown}"

    DET_DESKTOP="${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-none (TTY)}}${XDG_SESSION_TYPE:+ ($XDG_SESSION_TYPE)}"
    DET_HYPRLAND="not installed"
    command -v Hyprland >/dev/null 2>&1 && DET_HYPRLAND="$(Hyprland --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1)"
    [ -n "$DET_HYPRLAND" ] || DET_HYPRLAND="installed (version unknown)"
    DET_WAYBAR="not installed"
    command -v waybar >/dev/null 2>&1 && DET_WAYBAR="$(waybar --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 | tr -d v)"
    if [ -e "$HOME/.config/waybar" ] && [[ "$(readlink -f "$HOME/.config/waybar" 2>/dev/null)" != "${REPO_DIR:-/nonexistent}"/* ]]; then
        DET_WAYBAR+=" — your own config at ~/.config/waybar (backed up before replacing)"
    fi
    DET_QUICKSHELL="not installed"
    if command -v qs >/dev/null 2>&1 || command -v quickshell >/dev/null 2>&1; then
        DET_QUICKSHELL="$( (qs --version 2>/dev/null || quickshell --version 2>/dev/null) | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
        DET_QUICKSHELL="${DET_QUICKSHELL:-installed}"
    fi
    DET_DM="$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)" .service)"
    [ -n "$DET_DM" ] && [ "$DET_DM" != display-manager ] || DET_DM="none"

    local kb_free
    kb_free="$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')"
    DET_DISK_FREE_MB=$(( ${kb_free:-0} / 1024 ))
    DET_DISK="$(awk -v k="${kb_free:-0}" 'BEGIN { printf "%.1f GiB free in your home", k/1048576 }')"
}

detect_summary() {
    local g
    printf '%-14s %s\n' "System" "$DET_OS ($DET_ARCH)" "Kernel" "$DET_KERNEL" "CPU" "$DET_CPU" "Memory" "$DET_RAM"
    for g in "${DET_GPUS[@]}"; do printf '%-14s %s\n' "GPU" "$g"; done
    printf '%-14s %s\n' "Display" "$DET_RES" "Desktop" "$DET_DESKTOP" "Hyprland" "$DET_HYPRLAND" \
        "Waybar" "$DET_WAYBAR" "Quickshell" "$DET_QUICKSHELL" "Login manager" "$DET_DM" "Disk" "$DET_DISK"
}

detect_gpu_packages() {
    case "$DET_GPU_VENDORS" in
        *nvidia*) if [ "$DET_NVIDIA_DRIVER" -eq 1 ]; then echo "?egl-wayland"; echo "?libva-nvidia-driver|nvidia-vaapi-driver"; fi ;;
    esac
    case "$DET_GPU_VENDORS" in *amd*|*intel*) echo "?mesa-vulkan-drivers"; echo "?mesa-va-drivers|mesa-va-drivers-freeworld" ;; esac
    case "$DET_GPU_VENDORS" in *intel*) echo "?intel-media-driver|libva-intel-media-driver" ;; esac
    return 0
}
