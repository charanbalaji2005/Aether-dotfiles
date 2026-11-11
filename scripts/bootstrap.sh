#!/usr/bin/bash
# Compatibility wrapper: the installer now lives in ./install.sh (one
# implementation). Old flags are mapped onto it:
#   --yes → --yes   --no-packages → --no-packages   --skip-quickshell → --skip-quickshell
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$REPO_DIR/install.sh" --install "$@"
