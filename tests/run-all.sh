#!/usr/bin/bash
# Runs every real, automated test in this repo and reports a summary.
# Exits non-zero if any suite fails. This is what CI runs.

set -uo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SUITES=(
    "tests/scripts/test_shellcheck.sh"
    "tests/scripts/scan_repo_hygiene.sh"
    "tests/scripts/test_release_metadata.sh"
    "tests/scripts/test_workflows.sh"
    "tests/hyprland/test_config_syntax.sh"
    "tests/shell/test_qml_structure.sh"
    "tests/shell/test_qml_lint.sh"
    "tests/shell/test_security_invariants.sh"
    "tests/shell/test_quickshell_api.sh"
    "tests/shell/runtime/run_runtime_tests.sh"
    "tests/config/test_config_files.sh"
    "tests/python/run_python_tests.sh"
    "tests/integration/test_symlink_lifecycle.sh"
    "tests/integration/test_installer.sh"
    "tests/integration/test_symlinked_entrypoints.sh"
    "tests/packaging/test_tarball_pkgbuild.sh"
    "tests/packaging/test_rpm_build.sh"
)

failed_suites=()
skipped_suites=()
passed=0

# A suite that prints a line starting with "SKIP" (SKIP:/SKIPPED:) and exits 0
# did NOT run its checks: it is reported as SKIPPED, never as PASS.
for suite in "${SUITES[@]}"; do
    echo "════════════════════════════════════════════════════════════"
    echo "  $suite"
    echo "════════════════════════════════════════════════════════════"
    out="$(mktemp)"
    if bash "$REPO_DIR/$suite" 2>&1 | tee "$out"; [ "${PIPESTATUS[0]}" -eq 0 ]; then
        if grep -qE '^SKIP(PED)?:' "$out"; then
            echo "--- $suite: SKIPPED ($(grep -m1 -E '^SKIP(PED)?:' "$out" | sed -E 's/^SKIP(PED)?: *//')) ---"
            skipped_suites+=("$suite")
        else
            echo "--- $suite: PASS ---"
            passed=$((passed + 1))
        fi
    else
        echo "--- $suite: FAIL ---"
        failed_suites+=("$suite")
    fi
    rm -f "$out"
    echo
done

echo "════════════════════════════════════════════════════════════"
echo "  Summary"
echo "════════════════════════════════════════════════════════════"
echo "  ${#SUITES[@]} suites: $passed passed, ${#failed_suites[@]} failed, ${#skipped_suites[@]} skipped"
for s in "${skipped_suites[@]}"; do
    echo "    skipped: $s"
done

if [ ${#failed_suites[@]} -gt 0 ]; then
    echo
    echo "  Failed:"
    for s in "${failed_suites[@]}"; do
        echo "    - $s"
    done
    exit 1
fi

echo
if [ ${#skipped_suites[@]} -gt 0 ]; then
    echo "  No failures — but ${#skipped_suites[@]} suite(s) were skipped (see above); this is not a full pass."
else
    echo "  All suites passed."
fi
echo
echo "  Not covered by this run (see tests/services/README.md and TEST_REPORT.md):"
echo "    - Quickshell-dependent QML (layer-shell windows, Hyprland IPC, PipeWire, PAM) — the"
echo "      runtime suite covers the pure-Qt engine (springs, shaders, wallpaper stage, components)"
echo "    - Real GPUs/drivers: hardware detection is tested against fixture sysfs trees;"
echo "      on a real machine run: aether graphics verify && aether diagnostics"
echo "    - Anything requiring an actual Hyprland session, Bluetooth adapter, or PAM auth"
