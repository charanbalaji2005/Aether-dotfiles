#!/usr/bin/bash
# Validates non-code configuration: systemd units, package lists, JSON
# files, the shell's config schema, and that every IPC target the
# keybinds/CLI call actually exists in the QML.

set -uo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHELL_DIR="$REPO_DIR/config/quickshell/aether-shell"
failed=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failed=1; }

PY=python3
command -v "$PY" >/dev/null 2>&1 || PY=python

# ── systemd units ──────────────────────────────────────────────────────
for unit in "$REPO_DIR"/system/systemd/*.service; do
    name="$(basename "$unit")"
    for sect in Unit Service Install; do
        grep -q "^\[$sect\]" "$unit" || fail "$name has no [$sect] section"
    done
    grep -q "^ExecStart=" "$unit" || fail "$name has no ExecStart"
    # StartLimit* belong to [Unit]; in [Service] systemd ignores them with a warning.
    if awk '/^\[Service\]/{s=1;next} /^\[/{s=0} s && /^StartLimit/' "$unit" | grep -q .; then
        fail "$name sets StartLimit* in [Service] (must be in [Unit])"
    fi
    if command -v systemd-analyze >/dev/null 2>&1; then
        if systemd-analyze --user verify "$unit" >/dev/null 2>&1; then
            pass "$name passes systemd-analyze verify"
        else
            # verify also fails when ExecStart binaries aren't installed (CI); show why.
            echo "INFO: systemd-analyze verify $name reported:"; systemd-analyze --user verify "$unit" 2>&1 | sed 's/^/    /' | head -5
        fi
    else
        pass "$name structurally valid (systemd-analyze not available)"
    fi
done
if grep -q '%h/.local/bin' "$REPO_DIR/system/systemd/aether-shell.service"; then
    pass "aether-shell.service puts ~/.local/bin on PATH (helpers resolvable under systemd)"
else
    fail "aether-shell.service lacks ~/.local/bin on PATH — aether-screenshot/aether won't be found"
fi

# ── package lists ──────────────────────────────────────────────────────
for list in "$REPO_DIR"/packages/*/*.txt; do
    bad="$(sed -e 's/#.*//' "$list" | awk 'NF > 1')"
    if [ -n "$bad" ]; then
        fail "$(basename "$(dirname "$list")")/$(basename "$list") has lines with more than one token: $bad"
    else
        pass "$(basename "$(dirname "$list")")/$(basename "$list") parses to one package per line"
    fi
done

# ── JSON files in the repo ─────────────────────────────────────────────
while IFS= read -r -d '' json; do
    if "$PY" -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$json" 2>/dev/null; then
        pass "valid JSON: ${json#"$REPO_DIR"/}"
    else
        fail "invalid JSON: ${json#"$REPO_DIR"/}"
    fi
done < <(find "$REPO_DIR" -name "*.json" -not -path "*/.git/*" -print0)

# ── Shell config schema: every Config.<section>.<key> used exists ─────
"$PY" - "$SHELL_DIR" <<'PYEOF' || failed=1
import os, re, sys
root = sys.argv[1]
cfg = open(os.path.join(root, "core", "Config.qml"), encoding="utf-8").read()
schema = {}
for m in re.finditer(r"property JsonObject (\w+): JsonObject \{(.*?)\n            \}", cfg, re.S):
    schema[m.group(1)] = set(re.findall(r"property \w+ (\w+):", m.group(2)))
used = set()
for d, _, files in os.walk(root):
    for f in files:
        if f.endswith(".qml"):
            text = open(os.path.join(d, f), encoding="utf-8").read()
            used |= set(re.findall(r"Config\.(\w+)\.(\w+)", text))
missing = sorted("%s.%s" % u for u in used if u[0] in schema and u[1] not in schema[u[0]])
unknown_sections = sorted({u[0] for u in used} - set(schema) - {"ready"})
if missing or unknown_sections:
    print("FAIL: config keys used but not declared in core/Config.qml: %s %s" % (missing, unknown_sections))
    sys.exit(1)
print("PASS: all %d Config.<section>.<key> references are declared in the schema" % len(used))
PYEOF

# ── IPC targets used by keybinds / CLI exist in the shell ─────────────
targets="$(grep -rhoE 'target: "[a-z]+"' "$SHELL_DIR" --include=*.qml | sed -E 's/target: "([a-z]+)"/\1/' | sort -u)"
# shellcheck disable=SC2016 # matching the literal text "$shell" in keybinds.conf
calls="$( { grep -hoE '\$shell [a-z]+ ' "$REPO_DIR/config/hypr/keybinds.conf"; grep -hoE 'ipc [a-z]+ ' "$REPO_DIR/scripts/bin/aether"; } \
    | awk '{print $2}' | grep -vx call | sort -u)"
for t in $calls; do
    if echo "$targets" | grep -qx "$t"; then
        pass "IPC target '$t' exists"
    else
        fail "IPC target '$t' is called but no IpcHandler declares it"
    fi
done

# ── Every new QML import directory resolves (shell.qml) ───────────────
while IFS= read -r imp; do
    if [ -d "$SHELL_DIR/${imp#./}" ]; then pass "shell.qml import $imp resolves"; else fail "shell.qml import $imp missing"; fi
done < <(grep -oE 'import "\./[^"]+"' "$SHELL_DIR/shell.qml" | sed -E 's/import "(.*)"/\1/')

echo
if [ "$failed" -eq 0 ]; then echo "PASS: all configuration checks passed"; else echo "FAIL: see above"; exit 1; fi
