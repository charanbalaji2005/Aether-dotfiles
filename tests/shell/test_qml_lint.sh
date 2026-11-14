#!/usr/bin/bash
# Real QML syntax check with Qt's own qmllint, on every .qml file.
#
# Only the [syntax] category fails the test: qmllint can't resolve the
# Quickshell module outside a Quickshell installation, so its import/type
# warnings are expected noise here. A real parse error, however, is caught.
#
# qmllint is looked up as $QMLLINT, qmllint, qmllint6, qmllint-qt6, or
# pyside6-qmllint (pip install PySide6-Essentials). If none exists the
# suite is skipped (and says so) rather than pretending to pass.

set -uo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHELL_DIR="$REPO_DIR/config/quickshell/aether-shell"

LINT="${QMLLINT:-}"
if [ -z "$LINT" ]; then
    for cand in qmllint qmllint6 qmllint-qt6 /usr/lib64/qt6/bin/qmllint /usr/lib/qt6/bin/qmllint pyside6-qmllint; do
        if command -v "$cand" >/dev/null 2>&1; then LINT="$cand"; break; fi
    done
fi
if [ -z "$LINT" ]; then
    echo "SKIP: qmllint not found (set QMLLINT=/path/to/qmllint or install qt6-qtdeclarative-devel)"
    exit 0
fi

mapfile -t FILES < <(find "$SHELL_DIR" -name "*.qml" | sort)
echo "qmllint: $LINT — checking ${#FILES[@]} files for syntax errors"
failed=0
for f in "${FILES[@]}"; do
    out="$("$LINT" "$f" 2>&1 | grep -E '\[syntax\]' || true)"
    if [ -n "$out" ]; then
        echo "FAIL: ${f#"$SHELL_DIR"/}"
        while IFS= read -r line; do echo "    $line"; done <<< "$out"
        failed=1
    fi
done

if [ "$failed" -eq 0 ]; then
    echo "PASS: no QML syntax errors in ${#FILES[@]} files"
else
    exit 1
fi
