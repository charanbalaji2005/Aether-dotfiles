#!/usr/bin/bash
# Restores a backup created by backup.sh. Requires explicit confirmation
# before overwriting anything, and backs up whatever's currently in place
# (via backup.sh itself) before restoring — so a restore can't destroy data
# either.

set -euo pipefail

BACKUP_ROOT="$HOME/.aetheros-backups"

list_backups() {
    if [ ! -d "$BACKUP_ROOT" ] || [ -z "$(ls -A "$BACKUP_ROOT" 2>/dev/null)" ]; then
        echo "No backups found in $BACKUP_ROOT"
        exit 1
    fi
    echo "Available backups:"
    find "$BACKUP_ROOT" -maxdepth 1 -name 'aetheros-backup-*.tar.gz' -printf '%T@ %p\n' \
        | sort -rn | cut -d' ' -f2- | nl
}

ARCHIVE="${1:-}"

if [ -z "$ARCHIVE" ]; then
    list_backups
    echo
    echo "Usage: scripts/restore.sh <path-to-backup.tar.gz>"
    exit 1
fi

if [ ! -f "$ARCHIVE" ]; then
    echo "Not found: $ARCHIVE" >&2
    exit 1
fi

echo "This will restore configs from:"
echo "  $ARCHIVE"
echo
echo "Whatever's currently in place will be backed up first (via backup.sh),"
echo "so this is not destructive — but it WILL replace your current configs"
echo "at the managed paths with the ones from this backup."
echo
if [ "${2:-}" != "--yes" ]; then
    read -r -p "Continue? [y/N] " reply || reply=""
    if [ "$reply" != "y" ] && [ "$reply" != "Y" ]; then
        echo "Aborted."
        exit 0
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Strictly allowlisted managed destinations (relative to $HOME): the shared
# target list plus AetherOS's own state directory.
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=SCRIPTDIR/lib/common.sh
. "$REPO_DIR/scripts/lib/common.sh"
mapfile -t ALLOWED_TARGETS < <(aether_targets_rel)
ALLOWED_TARGETS+=(".config/aether-shell")

is_path_allowed() {
    local p="$1"
    p="${p#./}"
    p="${p%/}"
    [ -z "$p" ] && return 0
    for target in "${ALLOWED_TARGETS[@]}"; do
        local t="${target%/}"
        if [[ "$p" == "$t" ]] || [[ "$p" == "$t"/* ]] || [[ "$t" == "$p"/* ]]; then
            return 0
        fi
    done
    return 1
}

# Copy the source archive somewhere safe first — backup.sh (called next)
# creates its own archive under the same naming scheme, and we never want
# that to be able to clobber the archive we're about to restore from,
# no matter how the two timestamps might collide.
SAFE_COPY="$(mktemp -d)/source-archive.tar.gz"
cp "$ARCHIVE" "$SAFE_COPY"

echo "Validating archive integrity..."
while IFS= read -r entry; do
    entry="${entry#./}"
    [ -z "$entry" ] && continue
    # Reject absolute paths and directory traversal (..)
    if [[ "$entry" == /* ]] || [[ "$entry" =~ (^|/)\.\.(/|$) ]]; then
        echo "ERROR: Security violation: archive contains unsafe traversal path: $entry" >&2
        rm -rf "$(dirname "$SAFE_COPY")"
        exit 1
    fi
    if ! is_path_allowed "$entry"; then
        echo "ERROR: Refusing to restore archive containing unmanaged/unauthorized path: $entry" >&2
        rm -rf "$(dirname "$SAFE_COPY")"
        exit 1
    fi
done < <(tar -tzf "$SAFE_COPY")

echo
echo "Backing up current state first..."
"$SCRIPT_DIR/backup.sh"

echo
echo "Restoring..."
TMP_EXTRACT="$(mktemp -d)"
tar -xzf "$SAFE_COPY" -C "$TMP_EXTRACT"
rm -rf "$(dirname "$SAFE_COPY")"

# A managed path that is currently a symlink (into this repository, or
# anywhere else) must be unlinked before files are copied "into" it —
# otherwise the copy would follow the link and overwrite the repository's
# own files. It was captured by the backup taken a moment ago.
for target in "${ALLOWED_TARGETS[@]}"; do
    if [ -L "$HOME/$target" ] && [ -e "$TMP_EXTRACT/$target" ] && [ ! -L "$TMP_EXTRACT/$target" ]; then
        rm "$HOME/$target"
    fi
done

# The archive mirrors $HOME-relative paths (see backup.sh); copy each back.
find "$TMP_EXTRACT" -mindepth 1 | while read -r item; do
    rel="${item#"$TMP_EXTRACT"/}"
    rel="${rel#./}"
    if ! is_path_allowed "$rel"; then
        echo "Skipping unauthorized extracted path: $rel" >&2
        continue
    fi
    dest="$HOME/$rel"
    if [ -d "$item" ]; then
        mkdir -p "$dest"
    elif [ -L "$item" ]; then
        mkdir -p "$(dirname "$dest")"
        rm -f "$dest"
        cp -P "$item" "$dest"
        echo "Restored symlink $dest"
    else
        mkdir -p "$(dirname "$dest")"
        cp "$item" "$dest"
        echo "Restored $dest"
    fi
done

rm -rf "$TMP_EXTRACT"
echo
echo "Restore complete."
