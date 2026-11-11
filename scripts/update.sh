#!/usr/bin/bash
# Compatibility wrapper for `./install.sh --update` (pull, re-link, migrate
# settings, regenerate fragments, validate). Kept so `aether update` and
# older instructions keep working.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$REPO_DIR/install.sh" --update "$@"
