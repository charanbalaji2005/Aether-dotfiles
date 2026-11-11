#!/usr/bin/bash
# GitHub workflows: actionlint (if installed; CI installs it), valid YAML,
# and no swallowed failures (`|| true`, `continue-on-error`).
set -uo pipefail
REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
failed=0
if grep -nE '\|\|\s*true|continue-on-error' "$REPO_DIR"/.github/workflows/*.yml; then
    echo "FAIL: a workflow swallows failures (lines above)"
    failed=1
else
    echo "PASS: no workflow swallows failures"
fi
python3 - "$REPO_DIR" <<'PY' || failed=1
import glob, sys
try:
    import yaml
except ImportError:
    print("NOTE: PyYAML not installed; YAML parse check not run")
    sys.exit(0)
for f in glob.glob(sys.argv[1] + "/.github/**/*.yml", recursive=True):
    yaml.safe_load(open(f))
print("PASS: workflows and issue templates are valid YAML")
PY
if command -v actionlint >/dev/null 2>&1; then
    if actionlint "$REPO_DIR"/.github/workflows/*.yml; then echo "PASS: actionlint"; else failed=1; fi
else
    echo "NOTE: actionlint not installed; run in CI (lint.yml)"
fi
exit "$failed"
