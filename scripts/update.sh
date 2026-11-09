#!/usr/bin/bash
# Pulls the latest dotfiles, re-applies symlinks (which also recreates any
# missing per-machine Hyprland fragment), and validates the result. Does
# not install packages — re-run install.sh if the package lists changed.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

if [ -d .git ]; then
    if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
        echo "You have local changes in $REPO_DIR (your live configs are symlinks into it)."
        echo "Pulling with --ff-only; if it refuses, commit or stash them first:  git stash"
    fi
    echo "Pulling latest changes..."
    git pull --ff-only
else
    echo "Not a git checkout, skipping pull."
fi

bash "$REPO_DIR/scripts/setup-symlinks.sh"

echo
if command -v python3 >/dev/null 2>&1; then
    echo "Validating Hyprland configuration..."
    bash "$REPO_DIR/scripts/bin/aether" hyprland || {
        echo
        echo "Hyprland reported problems (see above). If you upgraded Hyprland, try:"
        echo "  aether hyprland compat"
    }
fi

echo
echo "Reload Hyprland with 'hyprctl reload' (or log out and back in)"
echo "and restart the shell with: aether shell-reload"
