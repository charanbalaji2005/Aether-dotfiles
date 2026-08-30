#!/usr/bin/bash
# Removes what setup-symlinks.sh created — and ONLY symlinks that actually
# point into this repo. Never deletes a real file or a symlink pointing
# somewhere else, so it can't destroy unrelated configuration. Backs up
# first regardless (belt and suspenders).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TARGETS=(
    "$HOME/.config/hypr"
    "$HOME/.config/quickshell/aether-shell"
    "$HOME/.config/kitty"
    "$HOME/.zshrc"
    "$HOME/.config/gtk-3.0/settings.ini"
    "$HOME/.config/gtk-3.0/gtk.css"
    "$HOME/.config/gtk-4.0/settings.ini"
    "$HOME/.config/gtk-4.0/gtk.css"
    "$HOME/.config/systemd/user/aether-clipboard.service"
    "$HOME/.config/systemd/user/aether-shell.service"
    "$HOME/.local/bin/aether"
    "$HOME/.local/bin/aether-screenshot"
    "$HOME/.local/bin/aether-wallpaper"
    "$HOME/.config/aether-shell/wallpapers"
)

echo "This removes the symlinks AetherOS dotfiles created, restoring nothing"
echo "in their place. Anything that isn't actually a symlink into this repo"
echo "is left completely alone."
echo
read -r -p "Continue? [y/N] " reply
if [ "$reply" != "y" ] && [ "$reply" != "Y" ]; then
    echo "Aborted."
    exit 0
fi

echo
echo "Backing up current state first..."
"$REPO_DIR/scripts/backup.sh"

echo
removed=0
skipped=0
for target in "${TARGETS[@]}"; do
    if [ -L "$target" ]; then
        real="$(readlink -f "$target")"
        if [[ "$real" == "$REPO_DIR"/* ]]; then
            rm "$target"
            echo "Removed $target"
            removed=$((removed + 1))
        else
            echo "Skipped $target (symlink points outside this repo: $real)"
            skipped=$((skipped + 1))
        fi
    elif [ -e "$target" ]; then
        echo "Skipped $target (not a symlink — untouched)"
        skipped=$((skipped + 1))
    fi
done

echo
echo "Done. Removed $removed, skipped $skipped."
echo "Packages installed by bootstrap.sh were NOT removed — this only undoes"
echo "the symlinking. Remove packages manually via your package manager if"
echo "you want them gone too."
