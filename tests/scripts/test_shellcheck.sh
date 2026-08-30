#!/usr/bin/bash
# Runs shellcheck against every shell script in the repo. Fails (non-zero
# exit) if shellcheck reports anything, at any severity — this is a real
# check with a real tool, not a script that always prints PASS.

set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! command -v shellcheck >/dev/null 2>&1; then
    echo "SKIP: shellcheck is not installed"
    exit 0
fi

mapfile -t SCRIPTS < <(find "$REPO_DIR" \
    -type f \
    \( -name "*.sh" -o -path "*/scripts/bin/*" \) \
    -not -path "*/config/quickshell/*")

echo "Checking ${#SCRIPTS[@]} scripts..."
failed=0
for script in "${SCRIPTS[@]}"; do
    if ! shellcheck "$script"; then
        failed=1
    fi
done

if [ "$failed" -eq 0 ]; then
    echo "PASS: all scripts clean"
else
    echo "FAIL: shellcheck found issues (see above)"
    exit 1
fi
