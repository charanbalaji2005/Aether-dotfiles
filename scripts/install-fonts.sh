#!/usr/bin/bash
# Installs JetBrainsMono Nerd Font (needed for the classic interface's
# icons) into ~/.local/share/fonts — no root, no repositories.
#
# The archive is pinned to a release and verified against a SHA-256 checksum
# before anything is extracted. Fedora doesn't package Nerd Fonts.
#
#   scripts/install-fonts.sh            install (skips if already present)
#   scripts/install-fonts.sh --dry-run  show what would happen
#   scripts/install-fonts.sh --force    reinstall

set -euo pipefail

VERSION="v3.4.0"
URL="https://github.com/ryanoasis/nerd-fonts/releases/download/$VERSION/JetBrainsMono.tar.xz"
SHA256="ef552a3e638f25125c6ad4c51176a6adcdce295ab1d2ffacf0db060caf8c1582"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/JetBrainsMonoNerdFont"

DRY=0; FORCE=0
for a in "$@"; do
    case "$a" in
        --dry-run) DRY=1 ;;
        --force) FORCE=1 ;;
        *) echo "Unknown option: $a" >&2; exit 2 ;;
    esac
done

if [ "$FORCE" -eq 0 ] && command -v fc-list >/dev/null 2>&1 && fc-list 2>/dev/null | grep -i "JetBrainsMono Nerd Font" >/dev/null; then
    echo "JetBrainsMono Nerd Font is already installed."
    exit 0
fi
if [ "$DRY" -eq 1 ]; then
    echo "would download $URL"
    echo "would verify sha256 $SHA256"
    echo "would extract the .ttf files to $DEST and run fc-cache"
    exit 0
fi
for tool in curl tar sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required" >&2; exit 1; }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "Downloading JetBrainsMono Nerd Font $VERSION…"
curl -fL --retry 2 --max-time 300 -o "$tmp/font.tar.xz" "$URL"
if ! echo "$SHA256  $tmp/font.tar.xz" | sha256sum -c --quiet -; then
    echo "Checksum mismatch: the download was not installed." >&2
    exit 1
fi
mkdir -p "$DEST"
tar -xJf "$tmp/font.tar.xz" -C "$DEST" --wildcards '*.ttf'
if command -v fc-cache >/dev/null 2>&1; then fc-cache -f "$DEST" >/dev/null; fi
echo "Installed to $DEST"
