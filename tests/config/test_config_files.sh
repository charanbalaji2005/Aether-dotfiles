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
    for sect in Unit Service; do
        grep -q "^\[$sect\]" "$unit" || fail "$name has no [$sect] section"
    done
    # [Install] is required unless the unit is only ever started by another
    # unit's OnFailure= (the safe-mode fallback must never be enabled itself).
    if ! grep -q "^\[Install\]" "$unit"; then
        if grep -qs "^OnFailure=$name" "$REPO_DIR"/system/systemd/*.service; then
            pass "$name has no [Install] on purpose (started via OnFailure=)"
        else
            fail "$name has no [Install] section"
        fi
    fi
    grep -q "^ExecStart=" "$unit" || fail "$name has no ExecStart"
    # StartLimit* belong to [Unit]; in [Service] systemd ignores them with a warning.
    if awk '/^\[Service\]/{s=1;next} /^\[/{s=0} s && /^StartLimit/' "$unit" | grep -q .; then
        fail "$name sets StartLimit* in [Service] (must be in [Unit])"
    fi
    pass "$name structurally valid (systemd-analyze verification: below)"
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

# ── systemd units pass systemd-analyze verify (system mode: a user manager
#    isn't available in CI containers; user-only semantics like %h are
#    exercised on real hardware). A deliberately broken unit must fail, so a
#    silently non-working verifier can't pass this. ─────────────────────
if command -v systemd-analyze >/dev/null 2>&1; then
    vt="$(mktemp -d)"
    printf '[Service]\nExecStart=relative/path\n' > "$vt/aether-broken-probe.service"
    if systemd-analyze verify "$vt/aether-broken-probe.service" >/dev/null 2>&1; then
        echo "NOTE: systemd-analyze can't verify units here (accepted a broken unit); not run"
    else
        cp "$REPO_DIR"/system/systemd/*.service "$vt/"
        rm -f "$vt/aether-broken-probe.service"
        unit_ok=1
        for u in "$vt"/*.service; do
            # Only lines about our units: verify also loads the host's units,
            # whose own problems (ordering cycles…) are not ours to fail on.
            out="$(systemd-analyze verify "$u" 2>&1 | grep -i aether || true)"
            if [ -n "$out" ]; then echo "$out"; unit_ok=0; fi
        done
        if [ "$unit_ok" -eq 1 ]; then pass "systemd units verify cleanly (systemd-analyze, system mode)"; else fail "systemd-analyze reported problems"; fi
    fi
    rm -rf "$vt"
else
    echo "NOTE: systemd-analyze not installed; unit verification not run"
fi

# ── Generated files are current (schema data, CLI reference) ──────────
if "$PY" "$REPO_DIR/tools/gen_schema.py" --check && "$PY" "$REPO_DIR/tools/gen_cli_reference.py" --check; then
    pass "generated files are up to date"
else
    failed=1
fi

# ── IPC functions: every "target function" pair called from keybinds, the
#    CLI, hypridle and generated touchpad gestures is declared by an IpcHandler.
if PYTHONPATH="$REPO_DIR/lib" "$PY" - "$REPO_DIR" <<'PYEOF'
import os, re, sys
repo = sys.argv[1]
shell = os.path.join(repo, "config/quickshell/aether-shell")
handlers = {}
for d, _, fs in os.walk(shell):
    for f in fs:
        if f.endswith(".qml"):
            t = open(os.path.join(d, f), encoding="utf-8").read()
            for m in re.finditer(r"IpcHandler\s*\{\s*target:\s*\"([a-z]+)\"(.*?)\n    \}", t, re.S):
                handlers.setdefault(m.group(1), set()).update(re.findall(r"function (\w+)\(", m.group(2)))
calls = set(re.findall(r"\$shell ([a-z]+) ([a-z]+)", open(os.path.join(repo, "config/hypr/interfaces/aether.conf")).read()))
calls |= set(re.findall(r"ipc call ([a-z]+) ([a-z]+)", open(os.path.join(repo, "scripts/bin/aether")).read()))
from aether.graphics import hyprconf
calls |= {tuple(v.split()) for v in hyprconf._SWIPE_IPC.values()}
calls |= set(re.findall(r"ipc call ([a-z]+) ([a-z]+)", hyprconf.generate_idle_conf(1, 1, 1)))
bad = sorted("%s %s" % c for c in calls if c[1] not in handlers.get(c[0], set()))
if bad:
    print("FAIL: IPC calls with no matching IpcHandler function: " + ", ".join(bad)); sys.exit(1)
print("PASS: %d IPC calls (keybinds, CLI, gestures, hypridle) all resolve to a handler function" % len(calls))
PYEOF
then :; else failed=1; fi

# ── IPC targets used by keybinds / CLI exist in the shell ─────────────
targets="$(grep -rhoE 'target: "[a-z]+"' "$SHELL_DIR" --include=*.qml | sed -E 's/target: "([a-z]+)"/\1/' | sort -u)"
# shellcheck disable=SC2016 # matching the literal text "$shell" in the aether interface's keybinds
calls="$( { grep -hoE '\$shell [a-z]+ ' "$REPO_DIR/config/hypr/interfaces/aether.conf"; grep -hoE 'ipc [a-z]+ ' "$REPO_DIR/scripts/bin/aether"; } \
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
