#!/usr/bin/bash
# Runs the Python backend's unit tests (hardware detection, graphics/driver
# logic, telemetry, theme, performance, CLI) against fixture sysfs trees.
# Standard library unittest only — nothing to pip install.

set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PY="${PYTHON:-python3}"
if ! command -v "$PY" >/dev/null 2>&1; then
    if command -v python >/dev/null 2>&1; then PY=python; else echo "SKIP: python3 not installed"; exit 0; fi
fi

echo "Using $("$PY" --version 2>&1)"
# Byte-compile every module first: a syntax error fails here with a clear message.
"$PY" -m compileall -q "$REPO_DIR/lib/aether" "$REPO_DIR/tests/python"
cd "$REPO_DIR/tests/python"
"$PY" -m unittest discover -s . -p "test_*.py" -v 2>&1 | tail -n 25
exit "${PIPESTATUS[0]}"
