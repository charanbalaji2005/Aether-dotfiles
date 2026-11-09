#!/usr/bin/bash
# Fresh-machine setup: detect the distro, install packages, build Quickshell
# if needed, back up and symlink configs, generate the per-machine Hyprland
# fragments, offer hardware-specific graphics setup, enable services, and
# validate the result. install.sh calls this; it is safe to re-run.
#
# Options:
#   --yes             don't ask before installing the package lists
#   --no-packages     skip package installation (configs + validation only)
#   --skip-quickshell don't build Quickshell from source
#
# Nothing here installs GPU drivers on its own: on NVIDIA machines it runs
# `aether graphics install-nvidia`, which shows its full plan and asks
# separately. Secure Boot is never touched.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSUME_YES=0
INSTALL_PACKAGES=1
BUILD_QUICKSHELL=1

for arg in "$@"; do
    case "$arg" in
        --yes|-y) ASSUME_YES=1 ;;
        --no-packages) INSTALL_PACKAGES=0 ;;
        --skip-quickshell) BUILD_QUICKSHELL=0 ;;
        -h|--help)
            sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

if [ "$(id -u)" -eq 0 ]; then
    echo "Run this as your normal user, not root. It uses sudo only for package installation." >&2
    exit 1
fi

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

confirm() {
    [ "$ASSUME_YES" -eq 1 ] && return 0
    [ -t 0 ] || { echo "$1 -> skipped (non-interactive; pass --yes)"; return 1; }
    local reply
    read -r -p "$1 [y/N] " reply
    [ "$reply" = "y" ] || [ "$reply" = "Y" ]
}

# Package list files: one package per line, '#' starts a comment (also
# inline), blank lines ignored.
read_pkgs() {
    sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' "$1" | awk 'NF'
}

detect_distro() {
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        case "${ID:-}" in
            fedora)
                local ver="${VERSION_ID:-0}"
                if [ "$ver" -lt 40 ] 2>/dev/null; then
                    echo "fedora-unsupported:$ver"
                else
                    echo "fedora"
                fi
                return
                ;;
            arch|archarm|endeavouros|manjaro|cachyos) echo "arch"; return ;;
            ubuntu|pop|mint) echo "ubuntu"; return ;;
            debian) echo "debian"; return ;;
            opensuse*|suse) echo "opensuse"; return ;;
            nixos) echo "nixos"; return ;;
        esac
    fi
    if [ -f /etc/fedora-release ]; then
        echo "fedora"
    elif [ -f /etc/arch-release ] || command -v pacman >/dev/null 2>&1; then
        echo "arch"
    else
        echo "unknown"
    fi
}

install_fedora() {
    local pkgs optional
    mapfile -t pkgs < <(read_pkgs "$REPO_DIR/packages/fedora/packages.txt")
    echo "Required packages (${#pkgs[@]}): ${pkgs[*]}"
    if confirm "Install these with dnf?"; then
        sudo dnf install -y "${pkgs[@]}"
    else
        echo "Skipped required packages — features depending on them will report unavailable."
    fi

    if [ -f "$REPO_DIR/packages/fedora/optional.txt" ]; then
        mapfile -t optional < <(read_pkgs "$REPO_DIR/packages/fedora/optional.txt")
        echo
        echo "Optional packages (${#optional[@]}): ${optional[*]}"
        if confirm "Install optional packages (unavailable ones are skipped)?"; then
            # dnf5 (Fedora 41+) has --skip-unavailable; dnf4 needs strict=0.
            if dnf --version 2>/dev/null | grep -qi dnf5; then
                sudo dnf install -y --skip-unavailable "${optional[@]}" || echo "Some optional packages failed; continuing."
            else
                sudo dnf install -y --setopt=strict=0 "${optional[@]}" || echo "Some optional packages failed; continuing."
            fi
        fi
    fi
}

install_arch() {
    local pkgs
    mapfile -t pkgs < <(read_pkgs "$REPO_DIR/packages/arch/packages.txt")
    echo "Packages (${#pkgs[@]}): ${pkgs[*]}"
    if confirm "Install these with pacman?"; then
        sudo pacman -S --needed --noconfirm "${pkgs[@]}"
    fi
    if ! command -v qs >/dev/null 2>&1; then
        echo
        echo "Quickshell not found. On Arch it's typically installed from the AUR"
        echo "(quickshell-git), e.g.:  paru -S quickshell-git   then re-run this script."
        exit 1
    fi
}

build_quickshell_from_source() {
    if command -v qs >/dev/null 2>&1; then
        echo "Quickshell already installed ($(command -v qs)), skipping build."
        return
    fi
    echo "Quickshell is not packaged for Fedora; it will be built from its official"
    echo "source repository (https://github.com/quickshell-mirror/quickshell)."
    if ! confirm "Clone and build Quickshell now (takes a few minutes, installs to /usr/local)?"; then
        echo "Skipped. The shell won't start until 'qs' is installed."
        return
    fi
    local build_dir
    build_dir="$(mktemp -d)"
    trap 'rm -rf "$build_dir"' RETURN
    git clone --depth 1 https://github.com/quickshell-mirror/quickshell "$build_dir/quickshell"
    cmake -S "$build_dir/quickshell" -B "$build_dir/quickshell/build" -GNinja -DCMAKE_BUILD_TYPE=Release
    cmake --build "$build_dir/quickshell/build"
    sudo cmake --install "$build_dir/quickshell/build"
    echo "If the build failed: check https://quickshell.org for current build instructions —"
    echo "its dependencies may have changed since this script was written."
}

aether() {
    bash "$REPO_DIR/scripts/bin/aether" "$@"
}

echo "=== AetherOS bootstrap ==="
distro="$(detect_distro)"
echo "Detected distro: $distro"

if [ "$INSTALL_PACKAGES" -eq 1 ]; then
    case "$distro" in
        fedora)
            step "Installing packages"
            install_fedora
            [ "$BUILD_QUICKSHELL" -eq 1 ] && { step "Quickshell"; build_quickshell_from_source; }
            ;;
        fedora-unsupported:*)
            echo "Fedora ${distro#fedora-unsupported:} is older than the minimum supported Fedora 40."
            exit 1
            ;;
        arch)
            step "Installing packages"
            install_arch
            ;;
        ubuntu|debian|opensuse|nixos|unknown)
            echo "No automated package installation for '$distro'."
            echo "Install the packages listed in packages/generic/README.md, then run:"
            echo "  ./scripts/bootstrap.sh --no-packages"
            exit 1
            ;;
    esac
fi

step "Backing up existing configuration"
bash "$REPO_DIR/scripts/backup.sh"

step "Linking configs"
bash "$REPO_DIR/scripts/setup-symlinks.sh"

if command -v python3 >/dev/null 2>&1; then
    step "Hardware"
    aether hardware || true

    step "Hyprland version-specific settings"
    aether hyprland compat || true

    step "Graphics"
    aether graphics drivers --offline || true
    echo
    echo "Hyprland GPU settings for this machine:"
    aether graphics configure || true

    # Offer the NVIDIA installer only when an NVIDIA GPU has no proprietary
    # driver loaded. It prints its own plan and asks before every change.
    if [ "$distro" = "fedora" ] && grep -qs "^PCI_ID=10DE:" /sys/bus/pci/devices/*/uevent \
        && [ ! -d /sys/module/nvidia ]; then
        echo
        echo "An NVIDIA GPU without the proprietary driver was detected."
        if confirm "Review the NVIDIA driver installation plan now?"; then
            aether graphics install-nvidia || true
        else
            echo "Later: aether graphics install-nvidia"
        fi
    fi
else
    echo "python3 not found — skipping hardware detection (sudo dnf install python3)."
fi

step "Enabling systemd user services"
if systemctl --user daemon-reload 2>/dev/null; then
    systemctl --user enable aether-clipboard.service aether-shell.service 2>/dev/null || true
    echo "aether-clipboard.service and aether-shell.service enabled"
else
    echo "No systemd --user session right now (normal outside a graphical session)."
    echo "Hyprland starts both services itself on first login (see hyprland.conf)."
fi

step "Validating"
bash "$REPO_DIR/scripts/doctor.sh" || true
if command -v python3 >/dev/null 2>&1; then
    aether hyprland || true
fi

echo
echo "=== Bootstrap complete ==="
echo "Log out and choose Hyprland at your display manager (or run Hyprland from a TTY)."
echo "If Hyprland ever fails to start:  Hyprland -c ~/.config/hypr/recovery.conf"
