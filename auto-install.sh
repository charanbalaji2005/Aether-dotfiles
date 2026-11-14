#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# AetherOS Dotfiles — one-command install for Fedora:
#
#   sh <(curl -fsSL https://raw.githubusercontent.com/charanbalaji2005/Aether-dotfiles/release-final/auto-install.sh)
#
# Add --auto after it to install everything without questions:
#   sh <(curl -fsSL …/auto-install.sh) --auto
#
# What this script does, and nothing more: install git if it is missing,
# download (git clone over HTTPS) the release-final branch of
# https://github.com/charanbalaji2005/Aether-dotfiles to
# ~/.local/share/aether-dotfiles (or update it there), show the exact commit,
# and start its ./install.sh with your options. Your desktop runs from that
# folder afterwards (configs are linked to it): don't delete it.
set -eu

REPO_URL="https://github.com/charanbalaji2005/Aether-dotfiles.git"
BRANCH="${AETHER_BRANCH:-release-final}"
DEST="${AETHER_DIR:-$HOME/.local/share/aether-dotfiles}"

say() { printf '\033[1;35m::\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

printf '\n\033[1mAetherOS Dotfiles\033[0m — © 2026 Neelampalli Charan Balaji\n'
printf 'https://github.com/charanbalaji2005/Aether-dotfiles  ⭐ star it if you like it!\n\n'

[ "$(id -u)" -ne 0 ] || die "Run this as your normal user, not root (sudo is asked for when needed)."
if [ -r /etc/os-release ]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    [ "${ID:-}" = fedora ] || say "This is ${PRETTY_NAME:-not Fedora}: AetherOS targets Fedora 41+; only a configs-only install will work."
fi

if ! command -v git >/dev/null 2>&1; then
    say "Installing git (needed to download AetherOS): sudo dnf install -y git"
    sudo dnf install -y git || die "Couldn't install git."
fi

if [ -d "$DEST/.git" ]; then
    say "Updating $DEST ($BRANCH)…"
    git -C "$DEST" fetch --depth 1 origin "$BRANCH"
    git -C "$DEST" checkout -q -B "$BRANCH" FETCH_HEAD 2>/dev/null || git -C "$DEST" pull --ff-only
else
    if [ -e "$DEST" ]; then
        say "Moving the existing $DEST aside to $DEST.bak.$(date +%Y%m%d-%H%M%S)"
        mv "$DEST" "$DEST.bak.$(date +%Y%m%d-%H%M%S)"
    fi
    mkdir -p "$(dirname "$DEST")"
    say "Downloading AetherOS ($BRANCH) to $DEST…"
    git clone --depth 1 --branch "$BRANCH" --progress "$REPO_URL" "$DEST"
fi
say "Commit: $(git -C "$DEST" log -1 --format='%h  %s  (%cd)' --date=short)"
[ -x "$DEST/install.sh" ] || die "$DEST/install.sh is missing — the download is incomplete."

cd "$DEST"
# Downloaded with curl into a pipe, stdin may not be the terminal: give the
# installer the terminal back so its menus and questions work.
if [ -r /dev/tty ] && [ ! -t 0 ]; then exec bash ./install.sh "$@" < /dev/tty; fi
exec bash ./install.sh "$@"
