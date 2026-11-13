# shellcheck shell=bash
# ULTRON RECOVERY — system detection. Read-only; every probe tolerates a
# missing tool and answers "unknown" instead of failing.

det_os()       { . /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-$NAME}" || echo unknown; }
det_fedora()   { . /etc/os-release 2>/dev/null && [ "${ID:-}" = fedora ] && echo "${VERSION_ID:-?}"; }
det_kernel()   { uname -r; }
det_cpu()      { sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo 2>/dev/null | head -1 | sed 's/  */ /g'; }
det_cores()    { nproc 2>/dev/null || echo "?"; }
det_mem()      { awk '/MemTotal/ { printf "%.1f GiB", $2 / 1048576 }' /proc/meminfo 2>/dev/null; }

det_gpus() {
    if command -v lspci >/dev/null 2>&1; then
        lspci 2>/dev/null | grep -Ei 'vga|3d controller|display controller' | sed -E 's/^[0-9a-f:.]+ [^:]+: //'
    else
        echo "unknown (lspci not installed: pciutils)"
    fi
}

det_nvidia() {
    if ! grep -qi nvidia <<< "$(det_gpus)"; then echo "no NVIDIA GPU"; return; fi
    if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi --query-gpu=driver_version --format=csv,noheader >/dev/null 2>&1; then
        echo "driver $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1) loaded"
    elif grep -q '^nvidia ' <<< "$(lsmod 2>/dev/null)"; then echo "nvidia module loaded (nvidia-smi unavailable)"
    elif grep -q '^nouveau ' <<< "$(lsmod 2>/dev/null)"; then echo "nouveau (open driver) — proprietary driver not loaded"
    else echo "NO DRIVER LOADED"; fi
}

det_amd() {
    if ! grep -Eqi 'amd|ati |radeon' <<< "$(det_gpus)"; then echo "no AMD GPU"; return; fi
    if grep -q '^amdgpu ' <<< "$(lsmod 2>/dev/null)"; then echo "amdgpu loaded"
    elif grep -q '^radeon ' <<< "$(lsmod 2>/dev/null)"; then echo "radeon (legacy) loaded"
    else echo "NO DRIVER LOADED"; fi
}

det_version() {  # det_version NAME — installed version of a desktop component
    case "$1" in
        hyprland) command -v Hyprland >/dev/null && Hyprland --version 2>/dev/null | grep -m1 -oE 'Hyprland [0-9][^ ]*' | cut -d' ' -f2 ;;
        waybar) command -v waybar >/dev/null && waybar --version 2>/dev/null | grep -m1 -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' ;;
        rofi) command -v rofi >/dev/null && rofi -version 2>/dev/null | grep -m1 -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' ;;
        quickshell) { command -v qs >/dev/null || command -v quickshell >/dev/null; } && { qs --version 2>/dev/null || quickshell --version 2>/dev/null; } | grep -m1 -oE '[0-9]+\.[0-9]+\.[0-9]+' ;;
        kitty) command -v kitty >/dev/null && kitty --version 2>/dev/null | grep -m1 -oE '[0-9]+\.[0-9]+\.[0-9]+' ;;
        playerctl) command -v playerctl >/dev/null && playerctl --version 2>/dev/null | grep -m1 -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' ;;
    esac
}

# Font families, listed once per run. (Never `fc-list | grep -q`: with
# pipefail, grep quitting early makes fc-list die of SIGPIPE = "not found".)
UR_FONT_CACHE=""
font_families() { [ -n "$UR_FONT_CACHE" ] || UR_FONT_CACHE="$(fc-list : family 2>/dev/null)"; printf '%s\n' "$UR_FONT_CACHE"; }
font_family_installed() { grep -qiF -- "$1" <<< "$(font_families)"; }

det_fonts() {  # key font families: installed, MISSING (needed) or "not installed (optional)"
    local f
    for f in "JetBrainsMono Nerd Font" "Noto Sans"; do
        if font_family_installed "$f"; then echo "$f: installed"; else echo "$f: MISSING"; fi
    done
    # Optional: JetBrainsMono Nerd Font already carries the icons; emoji are nice to have.
    for f in "Symbols Nerd Font" "Noto Color Emoji"; do
        if font_family_installed "$f"; then echo "$f: installed"; else echo "$f: not installed (optional)"; fi
    done
}

det_disk() { df -h --output=avail,pcent "$HOME" 2>/dev/null | tail -1 | awk '{ print $1 " free (" $2 " used) on the home filesystem" }'; }
det_disk_low() { local a; a="$(df -k --output=avail "$HOME" 2>/dev/null | tail -1)"; [ "${a:-0}" -lt 1048576 ]; }

det_network() {
    if command -v nmcli >/dev/null 2>&1; then
        local s; s="$(nmcli -t -f STATE general 2>/dev/null)"
        echo "${s:-unknown} ($(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | grep -v ':loopback' | head -1 | cut -d: -f1))"
    elif grep -q '^default' <<< "$(ip route 2>/dev/null)"; then echo "connected (default route)"
    else echo "offline (no default route)"; fi
}

det_failed_services() { systemctl --user --failed --no-legend --plain 2>/dev/null | awk '{ print $1 }'; }

det_session() {
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then echo "inside Hyprland"
    elif [ -n "${WAYLAND_DISPLAY:-}" ]; then echo "Wayland session (not Hyprland)"
    elif [ "${TERM:-}" = linux ]; then echo "TTY $(tty 2>/dev/null)"
    else echo "terminal (no graphical session in this shell)"; fi
}

# UR_NO_PROCESS=1 (tests): behave as if no desktop runs — never look at or
# signal real Waybar/Quickshell processes.
det_hypr_running() {
    [ "${UR_NO_PROCESS:-0}" = 1 ] && return 1
    pgrep -x Hyprland >/dev/null 2>&1 || pgrep -x Hyprland-wrapped >/dev/null 2>&1
}
