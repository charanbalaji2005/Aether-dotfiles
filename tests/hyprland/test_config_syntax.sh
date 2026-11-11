#!/usr/bin/bash
# Static checks on the Hyprland config: brace balance, that hyprland.conf
# sources every module file that exists, and the invariants the generated
# per-machine fragments rely on. This is NOT a real Hyprland config parse
# (that needs Hyprland itself — on a real system run `aether hyprland`,
# which uses `Hyprland --verify-config`). It catches the class of error a
# typo or a forgotten `source =` line would cause.

set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HYPR_DIR="$REPO_DIR/config/hypr"
CONF="$HYPR_DIR/hyprland.conf"
failed=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failed=1; }

for f in "$HYPR_DIR"/*.conf; do
    open=$(grep -o '{' "$f" | wc -l || true)
    close=$(grep -o '}' "$f" | wc -l || true)
    if [ "$open" -eq "$close" ]; then
        pass "$(basename "$f") braces balanced ($open/$close)"
    else
        fail "$(basename "$f") braces unbalanced ($open open, $close close)"
    fi
done

echo
for f in "$HYPR_DIR"/*.conf; do
    name="$(basename "$f")"
    [ "$name" = "hyprland.conf" ] && continue
    # Rule files are version-specific and sourced from the generated
    # compat.conf (checked below), never from hyprland.conf.
    if [ "$name" = "rules.conf" ] || [ "$name" = "rules-v2.conf" ]; then
        if grep -q "source = ~/.config/hypr/$name" "$CONF"; then
            fail "hyprland.conf sources $name directly (it must come from compat.conf)"
        else
            pass "$name is version-selected via compat.conf"
        fi
        continue
    fi
    # recovery.conf is a standalone config for `Hyprland -c`, never sourced.
    if [ "$name" = "recovery.conf" ]; then
        if grep -qE '^\s*source\s*=' "$f"; then
            fail "recovery.conf must be self-contained (it sources other files)"
        else
            pass "recovery.conf is self-contained"
        fi
        if grep -q "recovery.conf" <(grep -E '^\s*source\s*=' "$CONF"); then
            fail "hyprland.conf must not source recovery.conf"
        fi
        continue
    fi
    if grep -q "source = ~/.config/hypr/$name" "$CONF"; then
        pass "hyprland.conf sources $name"
    else
        fail "hyprland.conf does NOT source $name — it will never be loaded"
    fi
done

echo
for frag in hardware.conf compat.conf profile.conf; do
    if grep -q "^source = ~/.config/aether-shell/hypr/$frag" "$CONF"; then
        pass "hyprland.conf sources generated fragment $frag"
    else
        fail "hyprland.conf does not source generated fragment $frag"
    fi
    # shellcheck disable=SC2016 # literal text match, $HOME must not expand
    if grep -q 'FRAG_DIR="$HOME/.config/aether-shell/hypr"' "$REPO_DIR/scripts/setup-symlinks.sh" \
        && grep -qE "ensure_fragment \"\\\$FRAG_DIR/$frag\"" "$REPO_DIR/scripts/setup-symlinks.sh"; then
        pass "setup-symlinks.sh creates $frag so the source line can't fail"
    else
        fail "setup-symlinks.sh doesn't create $frag — Hyprland would error on a fresh install"
    fi
done

last_source="$(grep -E '^\s*source\s*=' "$CONF" | tail -1)"
if [[ "$last_source" == *"profile.conf"* ]]; then
    pass "profile.conf is sourced last (profiles override defaults)"
else
    fail "profile.conf must be the last source line (found: $last_source)"
fi

# hardware.conf sets env vars: it must come before anything that might rely on them.
env_line=$(grep -n "source = ~/.config/hypr/env.conf" "$CONF" | cut -d: -f1)
hw_line=$(grep -n "aether-shell/hypr/hardware.conf" "$CONF" | cut -d: -f1)
if [ -n "$env_line" ] && [ -n "$hw_line" ] && [ "$hw_line" -gt "$env_line" ] && [ "$hw_line" -le $((env_line + 2)) ]; then
    pass "hardware.conf is sourced right after env.conf"
else
    fail "hardware.conf should be sourced immediately after env.conf"
fi

# Obsolete NVIDIA workarounds must not creep back into shared config.
if grep -rnE '^\s*(env\s*=\s*(WLR_NO_HARDWARE_CURSORS|GBM_BACKEND)|explicit_sync)' "$HYPR_DIR" >/dev/null; then
    fail "obsolete NVIDIA workaround found in config/hypr (belongs in generated hardware.conf, if anywhere)"
    grep -rnE '^\s*(env\s*=\s*(WLR_NO_HARDWARE_CURSORS|GBM_BACKEND)|explicit_sync)' "$HYPR_DIR" || true
else
    pass "no obsolete NVIDIA workarounds in shared config"
fi
if grep -nE '^\s*env\s*=\s*__GLX_VENDOR_LIBRARY_NAME' "$HYPR_DIR"/*.conf >/dev/null; then
    fail "__GLX_VENDOR_LIBRARY_NAME in shared config would force NVIDIA on hybrid laptops"
else
    pass "shared config doesn't force a GPU vendor"
fi

# Every layer namespace the rules expect must exist in the QML.
SHELL_DIR="$REPO_DIR/config/quickshell/aether-shell"
for ns in bar launcher controlcenter dashboard notifications toasts settings clipboard bluetooth wallpicker wallpaper powermenu osd island dock overview systemcenter layouts edge; do
    if grep -rqiE "namespace: \"aether-$ns\"" "$SHELL_DIR"; then
        pass "layer namespace aether-$ns is set by the shell"
    else
        fail "rules.conf references aether-$ns but no QML surface sets that namespace"
    fi
done

# compat.conf generation sources exactly one rules file, matched to the version.
PYTHONPATH="$REPO_DIR/lib" python3 - "$REPO_DIR" <<'PYEOF' || failed=1
import sys
sys.path.insert(0, sys.argv[1] + "/tests/python")
import fixtures
from aether.graphics import hyprconf
for tag, want, not_want in (("v0.52.0", "rules.conf", "rules-v2.conf"), ("v0.53.0", "rules-v2.conf", "rules.conf")):
    s = fixtures.nvidia_desktop()
    s.cmd("hyprctl version -j", '{"tag": "%s"}' % tag)
    text = hyprconf.generate_compat_conf(s.ctx(), {"workspaceSwipe": True})
    s.cleanup()
    if "source = ~/.config/hypr/%s\n" % want not in text or "source = ~/.config/hypr/%s\n" % not_want in text:
        print("FAIL: compat.conf for %s does not source %s alone" % (tag, want)); sys.exit(1)
    print("PASS: compat.conf for Hyprland %s sources %s" % (tag[1:], want))
PYEOF

# Both rule files must cover the same layer namespaces and window classes/titles.
python3 - "$HYPR_DIR" <<'PYEOF' || failed=1
import re, sys
d = sys.argv[1]
def keys(path):
    t = "\n".join(l.split("#", 1)[0] for l in open(path, encoding="utf-8"))
    ns = set(re.findall(r"aether-\(?([a-z|]+)", t))
    names = set()
    for group in ns:
        names |= set(group.split("|"))
    pats = set(re.findall(r"(?:class|title):?\s*(\^\([^)]*\)[^,\s]*)", t))
    return names, pats
a, b = keys(d + "/rules.conf"), keys(d + "/rules-v2.conf")
if a != b:
    print("FAIL: rules.conf and rules-v2.conf differ:", a[0] ^ b[0], a[1] ^ b[1]); sys.exit(1)
print("PASS: rules.conf and rules-v2.conf cover the same %d namespaces and %d window patterns" % (len(a[0]), len(a[1])))
PYEOF

# Keybinds: no key combination bound twice to different commands, except
# pairs that are intentionally chained (Hyprland runs both).
python3 - "$HYPR_DIR/keybinds.conf" <<'PYEOF' || failed=1
import re, sys
CHAINED = {("ALT", "Tab")}
seen, bad = {}, []
mod = "SUPER"
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.split("#", 1)[0].strip()
    m = re.match(r"^\$mod\s*=\s*(\S+)", line)
    if m:
        mod = m.group(1); continue
    m = re.match(r"^bind[a-z]*\s*=\s*([^,]*),\s*([^,]+),\s*(.*)$", line)
    if not m:
        continue
    mods = " ".join(sorted(m.group(1).replace("$mod", mod).split()))
    key = (mods, m.group(2).strip())
    if key in seen and seen[key] != m.group(3) and key not in CHAINED:
        bad.append("%s+%s: '%s' vs '%s'" % (key[0], key[1], seen[key], m.group(3)))
    seen.setdefault(key, m.group(3))
if bad:
    print("FAIL: conflicting keybinds:\n  " + "\n  ".join(bad)); sys.exit(1)
print("PASS: %d keybinds, no conflicting combinations" % len(seen))
PYEOF

echo
if [ "$failed" -eq 0 ]; then
    echo "PASS: all Hyprland config checks passed"
else
    echo "FAIL: see above"
    exit 1
fi
