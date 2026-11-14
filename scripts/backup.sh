#!/usr/bin/bash
# Backs up the live config locations this repo manages into
# ~/.aetheros-backups/<timestamp>/, then tars them. Read-only with respect
# to the originals — nothing here modifies or deletes what it's backing up.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S-%N)"
BACKUP_ROOT="$HOME/.aetheros-backups"
BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"

# shellcheck source=SCRIPTDIR/lib/common.sh
. "$REPO_DIR/scripts/lib/common.sh"
mapfile -t TARGETS < <(aether_targets)
# Per-machine state that isn't a symlink target but belongs in a backup.
TARGETS+=(
    "$HOME/.config/aether-shell/config.json"
    "$HOME/.config/aether-shell/hypr"
    "$HOME/.config/aether-shell/terminal"
    "$HOME/.config/aether-shell/layouts.json"
    "$HOME/.config/aether-shell/profiles"
    "$HOME/.config/aether-shell/interface"
    "$HOME/.config/aether-shell/classic/state.conf"
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
    # Best effort: remove the staging directory only if it ended up empty.
    rmdir "$BACKUP_DIR" 2>/dev/null || true
    exit 0
fi

ARCHIVE="$BACKUP_ROOT/aetheros-backup-$TIMESTAMP.tar.gz"
tar -czf "$ARCHIVE" -C "$BACKUP_DIR" .
rm -rf "$BACKUP_DIR"

echo
echo "Backup complete: $ARCHIVE"
echo "Restore it with: scripts/restore.sh $ARCHIVE"
