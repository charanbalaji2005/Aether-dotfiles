#!/usr/bin/bash
# Entry point for a fresh install. Real logic lives in scripts/bootstrap.sh
# (distro detection, package install, Quickshell build, symlinking) — this
# just exists so `./install.sh` at the repo root is the obvious first thing
# to run, matching the README.

set -euo pipefail
exec "$(dirname "${BASH_SOURCE[0]}")/scripts/bootstrap.sh" "$@"
