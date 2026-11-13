#!/usr/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# Restore your previous configuration.
#   ./restore.sh                  menu: undo the installation, or pick a backup archive
#   ./restore.sh FILE [--yes]     restore one archive from ~/.aetheros-backups
#   ./restore.sh --rollback       undo the AetherOS installation (originals back)
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
case "${1:-}" in
    --rollback) shift; exec "$REPO_DIR/install.sh" --rollback "$@" ;;
    "") exec "$REPO_DIR/install.sh" --restore ;;
    -*) exec "$REPO_DIR/install.sh" --restore "$@" ;;
    *) archive="$1"; shift; exec "$REPO_DIR/install.sh" --restore --archive "$archive" "$@" ;;
esac
