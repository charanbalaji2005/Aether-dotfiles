#!/usr/bin/bash
# Runs every real, automated test in this repo and reports a summary.
# Exits non-zero if any suite fails. This is what CI runs.

set -uo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SUITES=(
    "tests/scripts/test_shellcheck.sh"
    "tests/scripts/scan_repo_hygiene.sh"
    "tests/hyprland/test_config_syntax.sh"
    "tests/shell/test_qml_structure.sh"
    "tests/integration/test_symlink_lifecycle.sh"
)

failed_suites=()

for suite in "${SUITES[@]}"; do
    echo "════════════════════════════════════════════════════════════"
    echo "  $suite"
    echo "════════════════════════════════════════════════════════════"
    if bash "$REPO_DIR/$suite"; then
        echo "--- $suite: PASS ---"
    else
        echo "--- $suite: FAIL ---"
        failed_suites+=("$suite")
    fi
    echo
done

echo "════════════════════════════════════════════════════════════"
echo "  Summary"
echo "════════════════════════════════════════════════════════════"
echo "  ${#SUITES[@]} suites run, ${#failed_suites[@]} failed"

if [ ${#failed_suites[@]} -gt 0 ]; then
    echo
    echo "  Failed:"
    for s in "${failed_suites[@]}"; do
        echo "    - $s"
    done
    exit 1
fi

echo
echo "  All suites passed."
echo
echo "  Not covered by this run (see tests/services/README.md):"
echo "    - Live QML/Quickshell runtime behavior (no Qt6/Quickshell in this environment)"
echo "    - Anything requiring an actual Hyprland session, Bluetooth adapter, or PAM auth"
