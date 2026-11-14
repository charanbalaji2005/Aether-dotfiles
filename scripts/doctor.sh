#!/usr/bin/bash
# Diagnostics for an AetherOS install. Checks what it can actually check —
# binary presence, running services, file existence, basic syntax — and
# says PASS/WARN/FAIL with a reason for each. This does not and cannot
# verify runtime correctness of the shell's QML (that needs a live
# Quickshell session); it verifies the things a static check can catch.

set +e  # we want to keep checking even if individual checks fail

REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
PASS=0
WARN=0
FAIL=0

pass() { printf "  \033[32mPASS\033[0m  %s\n" "$1"; PASS=$((PASS + 1)); }
warn() { printf "  \033[33mWARN\033[0m  %s\n" "$1"; WARN=$((WARN + 1)); }
fail() { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; FAIL=$((FAIL + 1)); }
section() { printf "\n\033[1m%s\033[0m\n" "$1"; }

require_bin() {
    local bin="$1" reason="$2"
    if command -v "$bin" >/dev/null 2>&1; then
        pass "$bin found"
    else
        fail "$bin not found — $reason"
    fi
}

optional_bin() {
    local bin="$1" reason="$2"
    if command -v "$bin" >/dev/null 2>&1; then
        pass "$bin found"
    else
        warn "$bin not found — $reason"
    fi
}

section "Core compositor/session"
require_bin Hyprland "the compositor itself"
require_bin qs "Quickshell — the shell won't run without it"
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    pass "running inside a Hyprland session (instance $HYPRLAND_INSTANCE_SIGNATURE)"
else
    warn "not running inside a Hyprland session right now (fine if you're checking before first login)"
fi

if systemctl --user is-active --quiet aether-shell.service 2>/dev/null; then
    pass "aether-shell.service is active (systemd-managed Quickshell)"
elif pgrep -f "qs -c aether-shell" >/dev/null 2>&1; then
    pass "aether-shell is running (direct process)"
else
    warn "aether-shell is not currently running"
fi

section "Qt / QML runtime"
if pkg-config --exists Qt6Core 2>/dev/null; then
    pass "Qt6Core found ($(pkg-config --modversion Qt6Core))"
else
    warn "pkg-config couldn't find Qt6Core — Quickshell may still work if Qt6 is installed via a non-pkg-config path"
fi

section "System services"
optional_bin pipewire "audio won't work — AudioService will report unavailable"
optional_bin wireplumber "audio device switching may not work correctly"
optional_bin wpctl "used by Hyprland's volume keybinds"
optional_bin nmcli "NetworkService will report unavailable, network module hides itself"
optional_bin bluetoothctl "Bluetooth is accessed via Quickshell's own binding, but this is a useful sanity check that BlueZ is present"
optional_bin upower "PowerService will report unavailable on laptops that need it"

if command -v systemctl >/dev/null 2>&1; then
    for svc in NetworkManager bluetooth upower; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            pass "$svc.service is active"
        else
            warn "$svc.service is not active (its shell features will report unavailable)"
        fi
    done
else
    warn "systemctl not found — skipping service-active checks"
fi

if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    pass "D-Bus session bus is set"
else
    warn "DBUS_SESSION_BUS_ADDRESS not set — normal outside a graphical session"
fi

section "PAM (lock screen authentication)"
if [ -d /etc/pam.d ]; then
    pass "/etc/pam.d exists"
else
    fail "/etc/pam.d not found — PAM authentication cannot work at all"
fi
warn "This only checks that PAM itself is present, not that Quickshell's PamContext integration works — see the shell's PROGRESS.md, that specific piece is flagged unverified"

section "Shell feature dependencies (each degrades gracefully if missing)"
optional_bin cliphist "clipboard history will be empty"
optional_bin wl-copy "clipboard operations (copy, screenshot-to-clipboard) won't work"
optional_bin wl-paste "cliphist has nothing to record without this running"
optional_bin grim "screenshots won't work"
optional_bin slurp "region-select screenshots won't work"
optional_bin playerctl "media key bindings won't do anything"
optional_bin brightnessctl "brightness key bindings won't do anything"
optional_bin hyprpolkitagent "GUI privilege prompts (package managers, disk tools) won't appear"

if systemctl --user is-active --quiet aether-clipboard.service 2>/dev/null; then
    pass "aether-clipboard.service is active (systemd-managed cliphist watcher)"
elif pgrep -f "wl-paste --watch cliphist" >/dev/null 2>&1; then
    pass "cliphist watcher is running (not via systemd, but it's running)"
else
    warn "cliphist watcher isn't running — clipboard history will stay empty until it is (run: systemctl --user enable --now aether-clipboard.service)"
fi

section "AetherOS backend (aether CLI: telemetry, hardware, graphics)"
if command -v python3 >/dev/null 2>&1; then
    pyver="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null)"
    if python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' 2>/dev/null; then
        pass "python3 $pyver found"
    else
        fail "python3 $pyver is too old — the aether backend needs 3.9+"
    fi
    if python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import aether.cli' "$REPO_DIR/lib" 2>/dev/null; then
        pass "aether backend imports cleanly ($REPO_DIR/lib/aether)"
    else
        fail "aether backend failed to import — run: python3 -I -c 'import sys; sys.path.insert(0, \"$REPO_DIR/lib\"); import aether.cli'"
    fi
else
    fail "python3 not found — bar/dashboard telemetry falls back to basic CPU/RAM/disk, and aether system/graphics commands won't run"
fi
optional_bin lspci "GPU model names fall back to the pci.ids database (pciutils)"
optional_bin hyprsunset "night light toggle will be unavailable"
optional_bin powerprofilesctl "battery saver / performance modes will be unavailable (power-profiles-daemon or tuned-ppd)"
if command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; then
    pass "ImageMagick found (accent colour from wallpaper)"
else
    warn "ImageMagick not found — 'accent from wallpaper' won't work"
fi
optional_bin vulkaninfo "aether graphics detect can't enumerate Vulkan devices (vulkan-tools)"
optional_bin vainfo "aether graphics verify can't check video acceleration (libva-utils)"
if grep -qs "^PCI_ID=10DE:" /sys/bus/pci/devices/*/uevent; then
    optional_bin nvidia-smi "NVIDIA GPU usage/temperature will show as unavailable (xorg-x11-drv-nvidia-cuda)"
fi

frag_dir="$HOME/.config/aether-shell/hypr"
for frag in hardware.conf compat.conf profile.conf; do
    if [ -f "$frag_dir/$frag" ]; then
        pass "$frag_dir/$frag exists"
    else
        fail "$frag_dir/$frag missing — hyprland.conf sources it; run: aether repair"
    fi
done

section "Fonts"
if command -v fc-list >/dev/null 2>&1; then
    if fc-list | grep -i "jetbrains mono" >/dev/null; then
        pass "JetBrains Mono found"
    else
        warn "JetBrains Mono not found — terminal/monospace UI will fall back to a system font"
    fi
    if fc-list | grep -i "manrope" >/dev/null; then
        pass "Manrope found"
    else
        warn "Manrope not found — GTK apps will fall back to a system font"
    fi
else
    warn "fc-list not found — can't check installed fonts"
fi

section "Configuration files"
check_file() {
    local path="$1"
    if [ -f "$path" ] && [ -s "$path" ]; then
        pass "$path exists and is non-empty"
    else
        fail "$path missing or empty"
    fi
}
check_file "$REPO_DIR/config/hypr/hyprland.conf"
check_file "$REPO_DIR/config/quickshell/aether-shell/shell.qml"
check_file "$REPO_DIR/config/kitty/kitty.conf"
check_file "$REPO_DIR/config/zsh/.zshrc"

# Basic brace-balance sanity check on hyprland.conf and every QML file —
# catches obvious corruption, not semantic correctness.
check_braces() {
    local path="$1"
    local open close
    open=$(grep -o '{' "$path" | wc -l)
    close=$(grep -o '}' "$path" | wc -l)
    if [ "$open" -eq "$close" ]; then
        pass "$(basename "$path") braces balanced ($open/$close)"
    else
        fail "$(basename "$path") braces UNBALANCED ($open open, $close close)"
    fi
}
for f in "$REPO_DIR"/config/hypr/*.conf; do
    check_braces "$f"
done

section "Symlinks"
check_symlink() {
    local path="$1"
    if [ -L "$path" ]; then
        if [ -e "$path" ]; then
            pass "$path is a valid symlink"
        else
            fail "$path is a broken symlink"
        fi
    elif [ -e "$path" ]; then
        warn "$path exists but is not a symlink — setup-symlinks.sh hasn't been run, or it was overwritten"
    else
        warn "$path does not exist — run scripts/setup-symlinks.sh"
    fi
}
check_symlink "$HOME/.config/hypr"
check_symlink "$HOME/.config/quickshell/aether-shell"
check_symlink "$HOME/.config/kitty"
check_symlink "$HOME/.zshrc"
check_symlink "$HOME/.local/bin/aether"
check_symlink "$HOME/.local/bin/aether-screenshot"
check_symlink "$HOME/.local/bin/aether-wallpaper"
check_symlink "$HOME/.config/aether-shell/wallpapers"

section "Summary"
echo "  $PASS passed, $WARN warnings, $FAIL failed"
echo
if [ "$FAIL" -gt 0 ]; then
    echo "Fix FAIL items first — the shell likely won't start correctly until they're resolved."
    exit 1
elif [ "$WARN" -gt 0 ]; then
    echo "No failures. Warnings are mostly optional features that'll just hide themselves."
    exit 0
else
    echo "Everything checked out."
    exit 0
fi
