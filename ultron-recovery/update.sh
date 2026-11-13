#!/usr/bin/env bash
# ULTRON RECOVERY — update the installed copy from its source.
#
#   update.sh           reinstall from the dotfiles checkout it was installed from
#   update.sh --pull    first `git pull --ff-only` that checkout
#
# Backups, logs, reports and your config are never touched.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
SRC=""
# Installed copy: install.conf says where it came from. A checkout: itself.
if [ -f "$HERE/install.conf" ]; then SRC="$(sed -n 's/^INSTALLED_FROM=//p' "$HERE/install.conf" | tail -1)"; fi
[ -n "$SRC" ] || SRC="$HERE"
[ -x "$SRC/install.sh" ] || { echo "source checkout not found: $SRC (clone the dotfiles again and run ultron-recovery/install.sh)" >&2; exit 1; }

case "${1:-}" in -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
if [ "${1:-}" = --pull ]; then
    repo="$(git -C "$SRC" rev-parse --show-toplevel 2>/dev/null)" || { echo "$SRC is not a git checkout" >&2; exit 1; }
    echo "Updating $repo (git pull --ff-only)…"
    git -C "$repo" pull --ff-only
fi
old="$(bash "$HERE/recovery.sh" --version 2>/dev/null || echo unknown)"
bash "$SRC/install.sh"
echo "Was: $old"
echo "Now: $(bash "${XDG_DATA_HOME:-$HOME/.local/share}/ultron-recovery/app/recovery.sh" --version)"
