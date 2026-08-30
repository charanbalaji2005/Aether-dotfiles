#!/usr/bin/bash
# Pulls the latest dotfiles and re-applies symlinks. Does not touch package
# installation — rerun install.sh manually if packages/fedora.txt changed.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

if [ -d .git ]; then
    echo "Pulling latest changes..."
    git pull --ff-only
else
    echo "Not a git checkout, skipping pull."
fi

"$REPO_DIR/scripts/setup-symlinks.sh"

echo
echo "Reload Hyprland (SUPER+SHIFT+Q to log out and back in, or run 'hyprctl reload')"
echo "and restart the shell with: aether shell-reload"
