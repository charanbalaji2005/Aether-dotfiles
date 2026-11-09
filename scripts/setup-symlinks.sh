#!/usr/bin/bash
# Symlinks this repo's configs into their real XDG locations.
# Existing files/directories are backed up (renamed with a timestamp
# suffix) rather than overwritten or deleted.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_SUFFIX=".bak.$(date +%Y%m%d-%H%M%S)"

link() {
    local src="$1"
    local dest="$2"

    if [ -L "$dest" ]; then
        local real
        real="$(readlink -f "$dest" 2>/dev/null || true)"
        if [[ "$real" == "$REPO_DIR"/* ]]; then
            # Owned symlink pointing into this repo; safe to replace
            rm "$dest"
        else
            # Unrelated symlink pointing elsewhere; back it up rather than deleting
            echo "Backing up existing external symlink $dest -> ${dest}${BACKUP_SUFFIX}"
            mv "$dest" "${dest}${BACKUP_SUFFIX}"
        fi
    elif [ -e "$dest" ]; then
        echo "Backing up existing $dest -> ${dest}${BACKUP_SUFFIX}"
        mv "$dest" "${dest}${BACKUP_SUFFIX}"
    fi

    mkdir -p "$(dirname "$dest")"
    ln -s "$src" "$dest"
    echo "Linked $dest -> $src"
}

echo "Linking AetherOS dotfiles from $REPO_DIR"
echo

link "$REPO_DIR/config/hypr" "$HOME/.config/hypr"
link "$REPO_DIR/config/quickshell/aether-shell" "$HOME/.config/quickshell/aether-shell"
link "$REPO_DIR/config/kitty" "$HOME/.config/kitty"
link "$REPO_DIR/config/zsh/.zshrc" "$HOME/.zshrc"
link "$REPO_DIR/theme/gtk/gtk-3.0/settings.ini" "$HOME/.config/gtk-3.0/settings.ini"
link "$REPO_DIR/theme/gtk/gtk-3.0/gtk.css" "$HOME/.config/gtk-3.0/gtk.css"
link "$REPO_DIR/theme/gtk/gtk-4.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"
link "$REPO_DIR/theme/gtk/gtk-4.0/gtk.css" "$HOME/.config/gtk-4.0/gtk.css"

for unit in "$REPO_DIR"/system/systemd/*.service; do
    [ -f "$unit" ] || continue
    link "$unit" "$HOME/.config/systemd/user/$(basename "$unit")"
done

mkdir -p "$HOME/.local/bin"
link "$REPO_DIR/scripts/bin/aether" "$HOME/.local/bin/aether"
chmod +x "$REPO_DIR/scripts/bin/aether"

if [ -d "$REPO_DIR/theme/wallpapers" ]; then
    link "$REPO_DIR/theme/wallpapers" "$HOME/.config/aether-shell/wallpapers"
fi

if [ -f "$REPO_DIR/scripts/bin/aether-screenshot" ]; then
    link "$REPO_DIR/scripts/bin/aether-screenshot" "$HOME/.local/bin/aether-screenshot"
    chmod +x "$REPO_DIR/scripts/bin/aether-screenshot"
fi

if [ -f "$REPO_DIR/scripts/bin/aether-wallpaper" ]; then
    link "$REPO_DIR/scripts/bin/aether-wallpaper" "$HOME/.local/bin/aether-wallpaper"
    chmod +x "$REPO_DIR/scripts/bin/aether-wallpaper"
fi

# Per-machine Hyprland fragments. hyprland.conf sources these, so they must
# exist before Hyprland first starts. They are created empty (comments
# only) and NEVER overwritten here — `aether graphics configure`,
# `aether hyprland compat` and `aether performance hyprland` fill them in.
FRAG_DIR="$HOME/.config/aether-shell/hypr"
ensure_fragment() {
    local path="$1" how="$2"
    if [ ! -e "$path" ]; then
        mkdir -p "$(dirname "$path")"
        printf '# Placeholder created by AetherOS. Generate real settings with: aether %s\n' "$how" > "$path"
        echo "Created $path"
    fi
}
ensure_fragment "$FRAG_DIR/hardware.conf" "graphics configure"
ensure_fragment "$FRAG_DIR/compat.conf" "hyprland compat"
ensure_fragment "$FRAG_DIR/profile.conf" "performance hyprland <profile>"

echo
echo "Done. Backups (if any) are alongside the original paths with a $BACKUP_SUFFIX suffix."
echo "Make sure \$HOME/.local/bin is on your PATH (config/zsh/.zshrc already adds it)."
