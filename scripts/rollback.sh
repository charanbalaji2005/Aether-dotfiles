#!/usr/bin/bash
# Puts back what setup-symlinks.sh moved aside, using the install manifest
# (~/.local/state/aether/manifest.tsv). Called by `install.sh --rollback`
# after uninstall.sh has removed AetherOS's links.
#
# For every path, the EARLIEST recorded backup is the pre-AetherOS original;
# it is moved back only if nothing is at that path now, so a file you
# created since is never overwritten. Nothing is deleted.

set -euo pipefail
REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
# shellcheck source=SCRIPTDIR/lib/common.sh
. "$REPO_DIR/scripts/lib/common.sh"

MANIFEST="$(aether_manifest)"
if [ ! -f "$MANIFEST" ]; then
    echo "No install manifest ($MANIFEST): nothing was moved aside by this installer."
    echo "Older backups, if any: ~/.aetheros-backups/ (restore with scripts/restore.sh)."
    exit 0
fi

restored=0; kept=0
declare -A seen=()
# Manifest lines are in time order: the first backup of a path is the original.
while IFS=$'\t' read -r _when kind dest detail; do
    [ "$kind" = "backup" ] || continue
    [ -n "${seen[$dest]:-}" ] && continue
    seen[$dest]=1
    # Only ever touch paths AetherOS manages.
    case "$dest" in "$HOME"/*) ;; *) continue ;; esac
    if [ ! -e "$detail" ] && [ ! -L "$detail" ]; then
        echo "Original of $dest is gone ($detail): skipped."
        continue
    fi
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        echo "Kept $dest as it is now; your original is still at $detail"
        kept=$((kept + 1))
        continue
    fi
    mkdir -p "$(dirname "$dest")"
    mv "$detail" "$dest"
    echo "Restored $dest"
    restored=$((restored + 1))
done < "$MANIFEST"

mv "$MANIFEST" "$MANIFEST.rolled-back-$(date +%Y%m%d-%H%M%S)"
echo "Restored $restored original(s); $kept left in place."
