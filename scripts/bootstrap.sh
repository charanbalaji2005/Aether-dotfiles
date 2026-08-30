#!/usr/bin/bash
# Detects the distro, installs packages accordingly, builds Quickshell if
# needed, and symlinks configs into place. This is what install.sh calls;
# it's split out so it can also be run directly or re-run idempotently.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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
            arch|archarm|endeavouros|manjaro|cachyos)
                echo "arch"
                return
                ;;
            ubuntu|pop|mint)
                echo "ubuntu"
                return
                ;;
            debian)
                echo "debian"
                return
                ;;
            opensuse*|suse)
                echo "opensuse"
                return
                ;;
            nixos)
                echo "nixos"
                return
                ;;
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
    echo "--- Installing packages (dnf) ---"
    mapfile -t pkgs < <(grep -vE '^\s*#|^\s*$' "$REPO_DIR/packages/fedora/packages.txt")
    sudo dnf install -y "${pkgs[@]}"
}

install_arch() {
    echo "--- Installing packages (pacman) ---"
    mapfile -t pkgs < <(grep -vE '^\s*#|^\s*$' "$REPO_DIR/packages/arch/packages.txt")
    sudo pacman -S --needed --noconfirm "${pkgs[@]}"

    if ! command -v qs >/dev/null 2>&1; then
        echo
        echo "Quickshell not found. On Arch it's typically installed from the AUR"
        echo "(quickshell-git). Install it with your AUR helper, e.g.:"
        echo "  paru -S quickshell-git"
        echo "or"
        echo "  yay -S quickshell-git"
        echo "then re-run this script."
        exit 1
    fi
}

build_quickshell_from_source() {
    if command -v qs >/dev/null 2>&1; then
        echo "Quickshell already installed ($(command -v qs)), skipping build."
        return
    fi

    echo "Building Quickshell from source. This takes a few minutes."
    local build_dir
    build_dir="$(mktemp -d)"
    git clone --depth 1 https://github.com/quickshell-mirror/quickshell "$build_dir/quickshell"
    cmake -S "$build_dir/quickshell" -B "$build_dir/quickshell/build" -GNinja -DCMAKE_BUILD_TYPE=Release
    cmake --build "$build_dir/quickshell/build"
    sudo cmake --install "$build_dir/quickshell/build"
    rm -rf "$build_dir"
    echo "If this failed: check https://quickshell.org for current build docs —"
    echo "its dependencies/build system may have changed since this script was written."
}

echo "=== AetherOS bootstrap ==="
echo

distro="$(detect_distro)"
echo "Detected distro: $distro"
echo

case "$distro" in
    fedora)
        install_fedora
        build_quickshell_from_source
        ;;
    fedora-unsupported:*)
        ver="${distro#fedora-unsupported:}"
        echo "Fedora $ver is older than the minimum supported Fedora 40+."
        echo "Please upgrade Fedora before bootstrapping AetherOS."
        exit 1
        ;;
    arch)
        install_arch
        ;;
    ubuntu|debian)
        echo "Detected Debian/Ubuntu-based distribution."
        echo "Automated package installation is currently tailored for Fedora 40+ and Arch Linux."
        echo "Please see packages/generic/README.md for manual package setup instructions,"
        echo "then run: ./scripts/setup-symlinks.sh"
        exit 1
        ;;
    opensuse|nixos)
        echo "Detected $distro distribution."
        echo "Please install the equivalent dependencies listed in packages/generic/README.md,"
        echo "then run: ./scripts/setup-symlinks.sh"
        exit 1
        ;;
    unknown)
        echo "Unrecognized distribution — no automated package install available."
        echo "See packages/generic/README.md for what to install manually, then"
        echo "run: ./scripts/setup-symlinks.sh"
        exit 1
        ;;
esac

echo
echo "--- Symlinking configs ---"
bash "$REPO_DIR/scripts/setup-symlinks.sh"

echo
echo "--- Enabling systemd user services ---"
if systemctl --user daemon-reload 2>/dev/null; then
    systemctl --user enable aether-clipboard.service aether-shell.service 2>/dev/null || true
    echo "aether-clipboard.service and aether-shell.service enabled in systemd user session"
else
    echo "No active systemd --user session detected (normal if you're not inside a graphical"
    echo "session yet). After logging into Hyprland, services will start automatically."
fi

echo
echo "=== Bootstrap complete ==="
echo "Running diagnostics..."
echo
bash "$REPO_DIR/scripts/doctor.sh" || true
