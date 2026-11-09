#!/usr/bin/bash
# Backs up the live config locations this repo manages into
# ~/.aetheros-backups/<timestamp>/, then tars them. Read-only with respect
# to the originals — nothing here modifies or deletes what it's backing up.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S-%N)"
BACKUP_ROOT="$HOME/.aetheros-backups"
BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"

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
    "$HOME/.config/aether-shell/config.json"
    "$HOME/.config/aether-shell/hypr"
)

mkdir -p "$BACKUP_DIR"
copied=0

for target in "${TARGETS[@]}"; do
    if [ -L "$target" ]; then
        rel="${target#"$HOME"/}"
        dest="$BACKUP_DIR/$rel"
        mkdir -p "$(dirname "$dest")"
        real="$(readlink -f "$target" 2>/dev/null || true)"
        if [[ "$real" == "$REPO_DIR"/* ]]; then
            # Follow repo-owned symlinks so the backup contains the real content
            # rather than dangling links if the repo moves.
            cp -rL "$target" "$dest"
            echo "Backed up $target (repo-managed content)"
        else
            # Preserve external symlinks without following them into external trees
            cp -P "$target" "$dest"
            echo "Backed up $target (external symlink preserved)"
        fi
        copied=$((copied + 1))
    elif [ -e "$target" ]; then
        rel="${target#"$HOME"/}"
        dest="$BACKUP_DIR/$rel"
        mkdir -p "$(dirname "$dest")"
        cp -a "$target" "$dest"
        echo "Backed up $target"
        copied=$((copied + 1))
    fi
done

if [ "$copied" -eq 0 ]; then
    echo "Nothing found to back up (no configs at the managed paths yet)."
    rmdir "$BACKUP_DIR" 2>/dev/null || true
    exit 0
fi

ARCHIVE="$BACKUP_ROOT/aetheros-backup-$TIMESTAMP.tar.gz"
tar -czf "$ARCHIVE" -C "$BACKUP_DIR" .
rm -rf "$BACKUP_DIR"

echo
echo "Backup complete: $ARCHIVE"
echo "Restore it with: scripts/restore.sh $ARCHIVE"
