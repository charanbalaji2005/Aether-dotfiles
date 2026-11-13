#!/usr/bin/bash
# Repository-wide hygiene scan:
#   1. TODO/FIXME/XXX markers (excluding files that legitimately discuss
#      the concept of placeholders/TODOs in prose, e.g. this project's own
#      "no TODO disguised as implementation" policy docs)
#   2. Hardcoded development-machine paths that shouldn't ship
#   3. Suspicious "fake"/"stub"/"not implemented" markers left in code
#      (as opposed to docs, where discussing what's NOT implemented is
#      the whole point of PROGRESS.md)
#
# This doesn't replace human review — it catches the obvious cases.

set -uo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_DIR" || exit 1

ANY_FOUND=0

# Docs whose entire purpose is to talk ABOUT these terms — excluded from
# the marker scan so this script doesn't flag its own project's policy
# documents for following that policy.
EXCLUDE_DOCS=(
    "./tests/services/README.md"
    "./tests/scripts/scan_repo_hygiene.sh"
    "./CONTRIBUTING.md"
    "./CHANGELOG.md"
    "./PROGRESS.md"
    "./config/quickshell/aether-shell/PROGRESS.md"
)

is_excluded() {
    local f="$1"
    for e in "${EXCLUDE_DOCS[@]}"; do
        [ "$f" = "$e" ] && return 0
    done
    return 1
}

echo "--- TODO/FIXME/XXX markers ---"
section_found=0
while IFS=: read -r file line content; do
    is_excluded "$file" && continue
    echo "  $file:$line:$content"
    section_found=1
    ANY_FOUND=1
done < <(grep -rniIE "TODO|FIXME|\bXXX\b" . --exclude-dir=.git --exclude-dir=__pycache__ -n 2>/dev/null)
[ "$section_found" -eq 0 ] && echo "  none found"

echo
echo "--- Hardcoded development-machine paths ---"
section_found=0
# shellcheck disable=SC2016 # intentional: matching the literal text "$HOME" in files, not expanding it
while IFS= read -r hit; do
    echo "  $hit"
    section_found=1
    ANY_FOUND=1
done < <(grep -rnE "/home/[a-zA-Z0-9_-]+/" . --exclude-dir=.git 2>/dev/null | grep -vE '\$HOME|~/')
[ "$section_found" -eq 0 ] && echo "  none found"

echo
echo "--- Fake/stub implementation markers in code (not docs) ---"
section_found=0
while IFS=: read -r file line content; do
    case "$file" in
        *.md) continue ;;  # discussing what's not implemented is PROGRESS.md's job
    esac
    is_excluded "$file" && continue
    echo "  $file:$line:$content"
    section_found=1
    ANY_FOUND=1
done < <(grep -rniE "not implemented yet|fake data|dummy implementation|return true.*always" \
    --include="*.sh" --include="*.qml" --include="*.conf" \
    . --exclude-dir=.git -n 2>/dev/null)
[ "$section_found" -eq 0 ] && echo "  none found"

echo
if [ "$ANY_FOUND" -eq 0 ]; then
    echo "Scan clean."
    exit 0
else
    echo "Scan found items above — review before release."
    exit 1
fi
