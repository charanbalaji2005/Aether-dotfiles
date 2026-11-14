#!/usr/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# Update AetherOS Dotfiles: pull the latest version, re-link your components,
# regenerate per-machine settings and validate. Same as ./install.sh --update.
#   ./update.sh [--yes] [--no-tui]
# On a terminal without options, the onboarding opens on the update screen's menu.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
exec "$REPO_DIR/install.sh" --update "$@"
