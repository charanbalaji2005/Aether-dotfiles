#!/usr/bin/bash
# Removes what setup-symlinks.sh created — and ONLY symlinks that actually
# point into this repo. Never deletes a real file or a symlink pointing
# somewhere else, so it can't destroy unrelated configuration. Backs up
# first regardless (belt and suspenders).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=SCRIPTDIR/lib/common.sh
. "$REPO_DIR/scripts/lib/common.sh"
mapfile -t TARGETS < <(aether_targets)

ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        --yes|-y) ASSUME_YES=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

echo "This removes the symlinks AetherOS dotfiles created, restoring nothing"
echo "in their place. Anything that isn't actually a symlink into this repo"
echo "is left completely alone."
echo
if [ "$ASSUME_YES" -ne 1 ]; then
    read -r -p "Continue? [y/N] " reply || reply=""
    if [ "$reply" != "y" ] && [ "$reply" != "Y" ]; then
        echo "Aborted."
        exit 0
    fi
fi

echo
echo "Backing up current state first..."
bash "$REPO_DIR/scripts/backup.sh"

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

# Stop and disable our user services (they'd fail without their unit files).
if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
    for unit in "$REPO_DIR"/system/systemd/*.service; do
        systemctl --user disable --now "$(basename "$unit")" >/dev/null 2>&1 || true
    done
    systemctl --user daemon-reload >/dev/null 2>&1 || true
fi

echo
echo "Done. Removed $removed, skipped $skipped."
echo "Your settings (~/.config/aether-shell), snapshots and backups were kept."
echo "Packages installed by install.sh were NOT removed — this only undoes"
echo "the symlinking. Remove packages manually via your package manager if"
echo "you want them gone too."
