#!/usr/bin/bash
# Symlinks this repo's configs into their real XDG locations.
# Existing files/directories are backed up (renamed with a timestamp
# suffix) rather than overwritten or deleted.

#
# Options:
#   --dry-run       print what would be linked / moved aside; change nothing
#   --keep-zshrc    leave an existing ~/.zshrc that isn't ours untouched
#
# Every link created and every file moved aside is recorded in
# ~/.local/state/aether/manifest.tsv, which `install.sh --rollback` reads to
# put the originals back.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
# shellcheck source=SCRIPTDIR/lib/common.sh
. "$REPO_DIR/scripts/lib/common.sh"
BACKUP_SUFFIX=".bak.$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0
KEEP_ZSHRC=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --keep-zshrc) KEEP_ZSHRC=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

link() {
    local src="$1"
    local dest="$2"

    if [ "$DRY_RUN" -eq 1 ]; then
        if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
            echo "  unchanged  $dest"
        elif [ -L "$dest" ] && [[ "$(readlink -f "$dest" 2>/dev/null || true)" == "$REPO_DIR"/* ]]; then
            echo "  relink     $dest -> $src"
        elif [ -e "$dest" ] || [ -L "$dest" ]; then
            echo "  move aside $dest -> ${dest}${BACKUP_SUFFIX}"
            echo "  link       $dest -> $src"
        else
            echo "  link       $dest -> $src"
        fi
        return 0
    fi

    if [ -L "$dest" ]; then
        local real
        real="$(readlink -f "$dest" 2>/dev/null || true)"
        if [ "$(readlink "$dest")" = "$src" ]; then
            return 0  # already correct: nothing to do, nothing to record
        elif [[ "$real" == "$REPO_DIR"/* ]]; then
            # Owned symlink pointing into this repo; safe to replace
            rm "$dest"
        else
            # Unrelated symlink pointing elsewhere; back it up rather than deleting
            echo "Backing up existing external symlink $dest -> ${dest}${BACKUP_SUFFIX}"
            mv "$dest" "${dest}${BACKUP_SUFFIX}"
            manifest_add backup "$dest" "${dest}${BACKUP_SUFFIX}"
        fi
    elif [ -e "$dest" ]; then
        echo "Backing up existing $dest -> ${dest}${BACKUP_SUFFIX}"
        mv "$dest" "${dest}${BACKUP_SUFFIX}"
        manifest_add backup "$dest" "${dest}${BACKUP_SUFFIX}"
    fi

    mkdir -p "$(dirname "$dest")"
    ln -s "$src" "$dest"
    manifest_add link "$dest" "$src"
    echo "Linked $dest -> $src"
}

echo "Linking AetherOS dotfiles from $REPO_DIR"
echo

link "$REPO_DIR/config/hypr" "$HOME/.config/hypr"
link "$REPO_DIR/config/quickshell/aether-shell" "$HOME/.config/quickshell/aether-shell"
link "$REPO_DIR/config/kitty" "$HOME/.config/kitty"
if [ "$KEEP_ZSHRC" -eq 1 ] && [ -e "$HOME/.zshrc" ] && [[ "$(readlink -f "$HOME/.zshrc" 2>/dev/null || true)" != "$REPO_DIR"/* ]]; then
    echo "Keeping your existing ~/.zshrc (--keep-zshrc). AetherOS's version: $REPO_DIR/config/zsh/.zshrc"
else
    link "$REPO_DIR/config/zsh/.zshrc" "$HOME/.zshrc"
fi
link "$REPO_DIR/theme/gtk/gtk-3.0/settings.ini" "$HOME/.config/gtk-3.0/settings.ini"
link "$REPO_DIR/theme/gtk/gtk-3.0/gtk.css" "$HOME/.config/gtk-3.0/gtk.css"
link "$REPO_DIR/theme/gtk/gtk-4.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"
link "$REPO_DIR/theme/gtk/gtk-4.0/gtk.css" "$HOME/.config/gtk-4.0/gtk.css"

for unit in "$REPO_DIR"/system/systemd/*.service; do
    [ -f "$unit" ] || continue
    link "$unit" "$HOME/.config/systemd/user/$(basename "$unit")"
done

[ "$DRY_RUN" -eq 1 ] || mkdir -p "$HOME/.local/bin"
for helper in "$REPO_DIR"/scripts/bin/*; do
    [ -f "$helper" ] || continue
    [ "$DRY_RUN" -eq 1 ] || chmod +x "$helper"
    link "$helper" "$HOME/.local/bin/$(basename "$helper")"
done

if [ -d "$REPO_DIR/theme/wallpapers" ]; then
    link "$REPO_DIR/theme/wallpapers" "$HOME/.config/aether-shell/wallpapers"
fi

# Per-machine Hyprland fragments. hyprland.conf sources these, so they must
# exist before Hyprland first starts. They are created empty (comments
# only) and NEVER overwritten here — `aether graphics configure`,
# `aether hyprland compat` and `aether performance hyprland` fill them in.
FRAG_DIR="$HOME/.config/aether-shell/hypr"
ensure_fragment() {
    local path="$1" how="$2"
    if [ ! -e "$path" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then echo "  create     $path"; return 0; fi
        mkdir -p "$(dirname "$path")"
        printf '# Placeholder created by AetherOS. Generate real settings with: aether %s\n' "$how" > "$path"
        manifest_add file "$path" "-"
        echo "Created $path"
    fi
}
ensure_fragment "$FRAG_DIR/hardware.conf" "graphics configure"
ensure_fragment "$FRAG_DIR/compat.conf" "hyprland compat"
ensure_fragment "$FRAG_DIR/profile.conf" "performance hyprland <profile>"
ensure_fragment "$FRAG_DIR/theme.conf" "theme apply"
# kitty.conf includes this; `aether theme apply` fills it in.
ensure_fragment "$HOME/.config/aether-shell/terminal/kitty-theme.conf" "theme apply"
ensure_fragment "$HOME/.config/aether-shell/terminal/kitty-local.conf" "theme apply"
ensure_fragment "$FRAG_DIR/cursor.conf" "theme cursor --set <theme>"
ensure_fragment "$FRAG_DIR/input.conf" "input apply"
ensure_fragment "$FRAG_DIR/displays.conf" "display apply"
ensure_fragment "$FRAG_DIR/apprules.conf" "workspace rules"

if [ "$DRY_RUN" -eq 1 ]; then
    echo
    echo "Dry run: nothing was changed."
    exit 0
fi

echo
echo "Done. Backups (if any) are alongside the original paths with a $BACKUP_SUFFIX suffix."
echo "Make sure \$HOME/.local/bin is on your PATH (config/zsh/.zshrc already adds it)."
