#!/usr/bin/bash
# Every Quickshell type, property, signal handler, method and enum the shell
# uses must exist in Quickshell's source — checked against the oldest and the
# newest supported releases (see tools/qs_api_check.py).
#
# Needs git and network access to fetch the source once (cached in
# ~/.cache/aether-tests). Offline: prints SKIPPED with the reason (exit 0
# with an explicit SKIPPED line; the summary counts it as skipped, never as
# passed). Override the source with QUICKSHELL_SRC=/path (single version).
set -uo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MIN_VERSION="v0.2.0"
CHECK_TAGS=("$MIN_VERSION" "v0.3.2")
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/aether-tests"

if [ -n "${QUICKSHELL_SRC:-}" ]; then
    exec python3 "$REPO_DIR/tools/qs_api_check.py" "$QUICKSHELL_SRC"
fi
if ! command -v git >/dev/null 2>&1; then
    echo "SKIPPED: git not installed (needed to fetch Quickshell's source)"
    exit 0
fi
failed=0
for tag in "${CHECK_TAGS[@]}"; do
    dir="$CACHE/quickshell-$tag"
    if [ ! -d "$dir/src" ]; then
        mkdir -p "$CACHE"
        if ! git clone -q --depth 1 --branch "$tag" https://github.com/quickshell-mirror/quickshell "$dir" 2>/dev/null; then
            rm -rf "$dir"
            echo "SKIPPED: could not fetch Quickshell $tag (offline?)"
            exit 0
        fi
    fi
    echo "== Quickshell $tag"
    python3 "$REPO_DIR/tools/qs_api_check.py" "$dir" || failed=1
done
exit "$failed"
