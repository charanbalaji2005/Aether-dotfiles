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
    "tests/shell/test_qml_lint.sh"
    "tests/shell/test_security_invariants.sh"
    "tests/shell/runtime/run_runtime_tests.sh"
    "tests/config/test_config_files.sh"
    "tests/python/run_python_tests.sh"
    "tests/integration/test_symlink_lifecycle.sh"
    "tests/integration/test_installer.sh"
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
echo "  Not covered by this run (see tests/services/README.md and TEST_REPORT.md):"
echo "    - Quickshell-dependent QML (layer-shell windows, Hyprland IPC, PipeWire, PAM) — the"
echo "      runtime suite covers the pure-Qt engine (springs, shaders, wallpaper stage, components)"
echo "    - Real GPUs/drivers: hardware detection is tested against fixture sysfs trees;"
echo "      on a real machine run: aether graphics verify && aether diagnostics"
echo "    - Anything requiring an actual Hyprland session, Bluetooth adapter, or PAM auth"
