#!/usr/bin/bash
# Static and isolated-$HOME checks of the classic interface (Waybar, Rofi,
# SwayNC, Wlogout, Hyprlock/Hypridle, aether-* helpers). Real parsers are
# used where the host has them — GTK 3 for every generated stylesheet, Rofi
# (under Xvfb) for every theme — and are reported as SKIP when missing,
# never as PASS. Nothing here needs or touches a running Hyprland session.

# shellcheck disable=SC2015 # `test && pass || fail`: pass never fails
set -uo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
failed=0
skipped=()
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failed=1; }
skip() { echo "  (skip) $1"; skipped+=("$1"); }

TEST_HOME="$(mktemp -d)"
trap 'rm -rf "$TEST_HOME"' EXIT
export HOME="$TEST_HOME"
unset XDG_CONFIG_HOME XDG_CACHE_HOME XDG_STATE_HOME HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY

# ── install into the isolated home ─────────────────────────────────────
if bash "$REPO_DIR/scripts/setup-symlinks.sh" >/dev/null 2>"$TEST_HOME/setup.err"; then
    pass "setup-symlinks.sh links the classic interface"
else
    fail "setup-symlinks.sh failed: $(cat "$TEST_HOME/setup.err")"
fi
for app in waybar rofi swaync wlogout wallust fastfetch; do
    [ "$(readlink "$HOME/.config/$app")" = "$REPO_DIR/config/$app" ] || fail "$HOME/.config/$app is not linked"
done
[ "$(cat "$HOME/.config/aether-shell/interface" 2>/dev/null)" = classic ] && pass "default interface is classic" || fail "default interface is not classic"
grep -q "interfaces/classic.conf" "$HOME/.config/aether-shell/hypr/interface.conf" && pass "interface.conf sources interfaces/classic.conf" \
    || fail "interface.conf doesn't select classic"
grep -q "col.active_border" "$HOME/.config/aether-shell/hypr/interface-theme.conf" && pass "classic border colours generated" \
    || fail "interface-theme.conf has no colours"

# An existing choice survives a re-run (update) of setup-symlinks.sh.
bash "$REPO_DIR/scripts/bin/aether-interface" set aether --no-reload --no-services >/dev/null
bash "$REPO_DIR/scripts/setup-symlinks.sh" --interface classic >/dev/null 2>&1
if [ "$(cat "$HOME/.config/aether-shell/interface")" = aether ] && grep -q "interfaces/aether.conf" "$HOME/.config/aether-shell/hypr/interface.conf" \
    && ! grep -q col.active_border "$HOME/.config/aether-shell/hypr/interface-theme.conf"; then
    pass "re-running setup keeps the user's interface choice (aether)"
else
    fail "setup-symlinks.sh overrode an existing interface choice"
fi
bash "$REPO_DIR/scripts/bin/aether-interface" set classic --no-reload --no-services >/dev/null
[ "$(bash "$REPO_DIR/scripts/bin/aether-interface" status)" = classic ] && pass "aether-interface switches back to classic" || fail "switch back failed"
bash "$REPO_DIR/scripts/bin/aether-interface" set rainbow >/dev/null 2>&1 && fail "aether-interface accepted an unknown interface" \
    || pass "aether-interface rejects unknown interfaces"

# ── Waybar ──────────────────────────────────────────────────────────────
python3 - "$REPO_DIR/config/waybar" <<'PY' || failed=1
import json, os, re, sys
root = sys.argv[1]
def strip(t):
    out, i, s = [], 0, False
    while i < len(t):
        c = t[i]
        if s:
            out.append(c)
            if c == "\\":
                out.append(t[i + 1]); i += 1
            elif c == '"':
                s = False
        elif c == '"':
            s = True; out.append(c)
        elif t.startswith("//", i):
            j = t.find("\n", i); i = len(t) if j < 0 else j; continue
        elif t.startswith("/*", i):
            i = t.find("*/", i) + 2; continue
        else:
            out.append(c)
        i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))
bad = False
mods = json.loads(strip(open(os.path.join(root, "modules.jsonc"), encoding="utf-8").read()))
for name, conf in mods.items():
    if name.startswith("group/"):
        for child in conf["modules"]:
            if child not in mods:
                print("FAIL: %s uses undefined module %s" % (name, child)); bad = True
layouts = sorted(f for f in os.listdir(os.path.join(root, "layouts")) if f.endswith(".jsonc"))
for f in layouts:
    data = json.loads(strip(open(os.path.join(root, "layouts", f), encoding="utf-8").read()))
    bars = data if isinstance(data, list) else [data]
    for bar in bars:
        inc = bar.get("include", [])
        if not inc or inc[0] != "~/.config/waybar/modules.jsonc" or any(
                i not in ("~/.config/waybar/modules.jsonc", "~/.config/aether-shell/classic/waybar/dock-modules.jsonc") for i in inc):
            print("FAIL: %s must include modules.jsonc (and at most the generated dock modules)" % f); bad = True
        dock = "~/.config/aether-shell/classic/waybar/dock-modules.jsonc" in inc
        for side in ("modules-left", "modules-center", "modules-right"):
            for m in bar.get(side, []):
                builtin_ok = m.split("#")[0] in ("tray",) and m in mods
                if m not in mods and not builtin_ok and not (dock and m in ("group/dock-pins", "custom/launchpad", "wlr/taskbar#dock")):
                    print("FAIL: %s: module %s is not defined in modules.jsonc" % (f, m)); bad = True
if not bad:
    print("PASS: modules.jsonc and %d layouts parse; every module they use is defined" % len(layouts))
sys.exit(1 if bad else 0)
PY

# Every aether-* program the configs call exists in scripts/bin.
missing="$(grep -rhoE 'aether-[a-z-]+' "$REPO_DIR/config/waybar" "$REPO_DIR/config/swaync" "$REPO_DIR/config/wlogout" \
        "$REPO_DIR/config/hypr/interfaces/classic.conf" "$REPO_DIR/config/hypr/hyprlock.conf" "$REPO_DIR/config/hypr/hypridle.conf" \
    | sort -u | grep -vE -- '-$|^aether-(shell|dropterm|blink|osd-low-priority|wall|looks)$|^aether-(clipboard|idle|media-last-player)$' \
    | while read -r cmd; do [ -x "$REPO_DIR/scripts/bin/$cmd" ] || echo "$cmd"; done)"
[ -x "$REPO_DIR/scripts/bin/aether-wall" ] || missing="$missing aether-wall"
if [ -z "$missing" ]; then pass "every aether-* command referenced by the classic configs exists"; else fail "missing helpers: $missing"; fi

# ── stylesheets through the real GTK 3 parser ──────────────────────────
if python3 -c 'import gi; gi.require_version("Gtk", "3.0"); from gi.repository import Gtk' 2>/dev/null; then
    for style in $(bash "$REPO_DIR/scripts/bin/aether-waybar" styles); do
        bash "$REPO_DIR/scripts/bin/aether-colors" waybar-style "$style" --no-reload >/dev/null 2>&1
        python3 - "$HOME/.config/aether-shell/classic/waybar/style.css" "waybar/$style" <<'PY' || failed=1
import sys, gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk
p, errs = Gtk.CssProvider(), []
p.connect("parsing-error", lambda _p, sec, err: errs.append("%s:%d %s" % (sec.get_file().get_path() if sec.get_file() else "?", sec.get_start_line() + 1, err.message)))
try:
    p.load_from_path(sys.argv[1])
except Exception as e:  # noqa: BLE001
    errs.append(str(e))
print(("FAIL: %s: %s" % (sys.argv[2], errs)) if errs else "PASS: %s stylesheet parses (GTK 3) with the live palette" % sys.argv[2])
sys.exit(1 if errs else 0)
PY
    done
    for app in swaync wlogout; do
        python3 - "$HOME/.config/aether-shell/classic/$app/style.css" "$app" <<'PY' || failed=1
import sys, gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk
p, errs = Gtk.CssProvider(), []
p.connect("parsing-error", lambda _p, sec, err: errs.append("%d %s" % (sec.get_start_line() + 1, err.message)))
try:
    p.load_from_path(sys.argv[1])
except Exception as e:  # noqa: BLE001
    errs.append(str(e))
print(("FAIL: %s: %s" % (sys.argv[2], errs)) if errs else "PASS: %s stylesheet parses (GTK 3) with the live palette" % sys.argv[2])
sys.exit(1 if errs else 0)
PY
    done
    # The parser check must be able to fail: a broken sheet is rejected.
    printf 'window { colr: red; }\n' > "$TEST_HOME/broken.css"
    if python3 -c 'import sys, gi; gi.require_version("Gtk", "3.0"); from gi.repository import Gtk
p = Gtk.CssProvider(); e = []
p.connect("parsing-error", lambda *a: e.append(1))
try: p.load_from_path(sys.argv[1])
except Exception: e.append(1)
sys.exit(0 if e else 1)' "$TEST_HOME/broken.css"; then pass "GTK check rejects an invalid stylesheet"; else fail "GTK check accepted an invalid stylesheet"; fi
else
    skip "GTK 3 Python bindings not installed (Fedora: python3-gobject gtk3) — stylesheets not parsed"
fi

# ── Rofi themes through real Rofi ──────────────────────────────────────
if command -v rofi >/dev/null && command -v xvfb-run >/dev/null; then
    for t in "$REPO_DIR"/config/rofi/themes/*.rasi; do
        out="$(xvfb-run -a rofi -no-config -theme "$t" -dump-theme 2>&1)"
        if grep -qiE "error|failed to parse|unknown" <<< "$out" || ! grep -q "accent" <<< "$out"; then
            fail "rofi theme $(basename "$t"): $(grep -iE 'error|parse|unknown' <<< "$out" | head -2)"
        else
            pass "rofi parses theme $(basename "$t")"
        fi
    done
    bash "$REPO_DIR/scripts/bin/aether-colors" source preset ember --no-reload >/dev/null 2>&1
    if xvfb-run -a rofi -no-config -theme "$REPO_DIR/config/rofi/themes/menu.rasi" -dump-theme 2>&1 | grep -qE "accent: +rgba \( 255, 180, 84"; then
        pass "rofi picks up the generated palette (ember accent)"
    else
        fail "rofi themes don't use ~/.config/aether-shell/classic/colors/rofi.rasi"
    fi
    out="$(xvfb-run -a rofi -config "$REPO_DIR/config/rofi/config.rasi" -dump-config 2>&1)"
    grep -qiE "error|failed" <<< "$out" && fail "rofi config.rasi: $(grep -iE 'error|failed' <<< "$out" | head -1)" || pass "rofi parses config.rasi"
else
    skip "rofi and/or xvfb-run not installed — Rofi themes not parsed"
fi

# ── SwayNC, wlogout, pyprland, wallust ─────────────────────────────────
python3 - "$REPO_DIR/config" <<'PY' || failed=1
import json, os, re, sys, tomllib
c = sys.argv[1]
bad = False
cfg = json.load(open(os.path.join(c, "swaync/config.json"), encoding="utf-8"))
for w in cfg["widgets"]:
    base = w.split("#")[0]
    if base not in ("title", "dnd", "notifications") and w not in cfg.get("widget-config", {}):
        print("FAIL: swaync widget %s has no widget-config" % w); bad = True
print("PASS: swaync config.json parses (%d widgets)" % len(cfg["widgets"]))
txt = open(os.path.join(c, "wlogout/layout"), encoding="utf-8").read()
objs = [json.loads(o) for o in re.findall(r"\{[^{}]*\}", txt)]
labels = {o["label"] for o in objs}
for o in objs:
    if not os.path.isfile(os.path.join(c, "wlogout/icons", o["label"] + ".svg")):
        print("FAIL: wlogout button %s has no icon" % o["label"]); bad = True
css = open(os.path.join(c, "wlogout/style.css"), encoding="utf-8").read()
for l in labels:
    if "#%s" % l not in css:
        print("FAIL: wlogout style has no rule for #%s" % l); bad = True
print("PASS: wlogout layout parses (%d buttons, each with an icon and a style)" % len(objs))
tomllib.load(open(os.path.join(c, "hypr/pyprland.toml"), "rb"))
tomllib.load(open(os.path.join(c, "wallust/wallust.toml"), "rb"))
keys = json.loads(open(os.path.join(c, "wallust/templates/aether.json"), encoding="utf-8").read().replace("{{", "").replace("}}", ""))
if len(keys) != 19:
    print("FAIL: wallust template should export 19 colours"); bad = True
print("PASS: pyprland.toml, wallust.toml and the wallust template parse")
sys.exit(1 if bad else 0)
PY

# ── looks: every row points at things that exist, and applying one works ──
python3 - "$REPO_DIR" <<'PY' || failed=1
import os, sys
sys.path.insert(0, os.path.join(sys.argv[1], "lib"))
from aether.classic_colors import PRESETS
r = sys.argv[1]
bad, n = False, 0
for line in open(os.path.join(r, "config/aether-looks.tsv"), encoding="utf-8"):
    if line.startswith("#") or not line.strip():
        continue
    f = line.rstrip("\n").split("\t")
    if len(f) != 11:
        print("FAIL: look line has %d columns: %r" % (len(f), line)); bad = True; continue
    n += 1
    name, layout, style, launcher, palette = f[:5]
    checks = [("layout", "config/waybar/layouts/%s.jsonc" % layout), ("style", "config/waybar/styles/%s.css" % style),
              ("launcher", "config/rofi/themes/%s.rasi" % launcher), ("lock design", "config/hypr/hyprlock/%s.conf" % f[9])]
    for what, path in checks:
        if not os.path.isfile(os.path.join(r, path)):
            print("FAIL: look %s: %s %s missing" % (name, what, path)); bad = True
    if palette != "wallpaper" and palette not in PRESETS:
        print("FAIL: look %s: unknown palette %s" % (name, palette)); bad = True
    if not all(x.isdigit() for x in f[5:9]):
        print("FAIL: look %s: gaps/border/rounding must be numbers" % name); bad = True
print("PASS: %d looks reference existing layouts, styles, launchers and palettes" % n if not bad else "FAIL: looks table")
sys.exit(1 if bad else 0)
PY
if bash "$REPO_DIR/scripts/bin/aether-look" apply blocks >/dev/null 2>&1 \
    && [ "$(bash "$REPO_DIR/scripts/bin/aether-look" current)" = blocks ] \
    && grep -q "rounding = 3" "$HOME/.config/aether-shell/hypr/look.conf" \
    && grep -q "styles/blocks.css" "$HOME/.config/aether-shell/classic/waybar/style.css" \
    && grep -q "^source=preset" "$HOME/.config/aether-shell/classic/state.conf" \
    && grep -q "^rofi_launcher=aether" "$HOME/.config/aether-shell/classic/state.conf"; then
    pass "aether-look apply writes layout, style, launcher, palette and spacing"
else
    fail "aether-look apply blocks did not record everything"
fi
bash "$REPO_DIR/scripts/bin/aether-look" apply nosuchlook >/dev/null 2>&1 && fail "aether-look accepted an unknown look" || pass "aether-look rejects unknown looks"
bash "$REPO_DIR/scripts/bin/aether-look" apply default >/dev/null 2>&1
bash "$REPO_DIR/scripts/bin/aether-waybar" styles | grep -q '^_' && fail "the shared _base.css is offered as a style" || pass "style list hides shared partials"

# ── lock designs: balanced, only known widgets, never sourced elsewhere, PAM field present ──
python3 - "$REPO_DIR/config/hypr/hyprlock" <<'PY' || failed=1
import os, re, sys
d = sys.argv[1]
WIDGETS = {"background", "label", "input-field", "shape", "image"}
bad, n = False, 0
for f in sorted(os.listdir(d)):
    t = open(os.path.join(d, f), encoding="utf-8").read()
    n += 1
    if t.count("{") != t.count("}"):
        print("FAIL: %s braces unbalanced" % f); bad = True
    for w in re.findall(r"^([a-z-]+)\s*\{", t, re.M):
        if w not in WIDGETS:
            print("FAIL: %s uses unknown hyprlock widget %s" % (f, w)); bad = True
    if t.count("input-field {") != 1:
        print("FAIL: %s must have exactly one password field" % f); bad = True
    for v in set(re.findall(r"\$([a-z0-9]+)", t)) - {"wallpaper", "bg", "surface", "text", "subtext", "accent", "accent2", "urgent", "ok", "font", "USER", "FAIL", "ATTEMPTS"}:
        print("FAIL: %s uses undefined variable $%s" % (f, v)); bad = True
print("PASS: %d lock designs: balanced, known widgets, one PAM password field, only defined variables" % n if not bad else "FAIL: lock designs")
sys.exit(1 if bad else 0)
PY
bash "$REPO_DIR/scripts/bin/aether-lock" design cyber >/dev/null 2>&1 \
    && grep -q 'Lock design "cyber"' "$HOME/.config/aether-shell/classic/colors/hyprlock-design.conf" \
    && pass "aether-lock design writes the design hyprlock.conf sources" || fail "aether-lock design did not take effect"
bash "$REPO_DIR/scripts/bin/aether-lock" design nonexistent >/dev/null 2>&1 && fail "aether-lock accepted an unknown design" || pass "aether-lock rejects unknown designs"

# Every lock design renders with the preview tool (catches broken positions/colours).
if python3 -c 'import PIL' 2>/dev/null; then
    okl=1
    for d in "$REPO_DIR"/config/hypr/hyprlock/*.conf; do
        python3 "$REPO_DIR/tools/preview-lockscreen.py" "$d" "$TEST_HOME/lock.png" --size 640x360 \
            --colors "$HOME/.config/aether-shell/classic/colors/hyprlock.conf" >/dev/null 2>&1 && [ -s "$TEST_HOME/lock.png" ] || okl=0
    done
    [ "$okl" = 1 ] && pass "every lock design renders in the preview tool" || fail "a lock design failed to render"
else
    skip "Pillow not installed — lock previews not rendered"
fi

# ── keybinding tool: clean on both interfaces, and it can fail ──────────
for i in classic aether; do
    bash "$REPO_DIR/scripts/bin/aether-bindings" check --interface "$i" >/dev/null 2>&1 \
        && pass "aether-bindings check: no conflicts or unknown dispatchers ($i)" || fail "aether-bindings check reported errors ($i)"
done
mkdir -p "$HOME/.config/aether-shell/hypr"
printf 'bind = SUPER, D, exec, something-else\nbind = SUPER, K, frobnicate\n' > "$HOME/.config/aether-shell/hypr/user-binds.conf"
out="$(bash "$REPO_DIR/scripts/bin/aether-bindings" check --interface classic 2>&1)"
if grep -q "conflict: SUPER + D" <<< "$out" && grep -q "unknown dispatcher 'frobnicate'" <<< "$out"; then
    pass "aether-bindings check catches a conflicting user bind and an unknown dispatcher"
else
    fail "aether-bindings check missed injected errors: $out"
fi
rm -f "$HOME/.config/aether-shell/hypr/user-binds.conf"

# ── wallpaper gallery ordering: favourites, then recent, then the rest ──
mkdir -p "$HOME/Pictures/Wallpapers/space" "$HOME/Pictures/Wallpapers/city"
for n in space/a city/b city/c; do cp "$REPO_DIR/config/wlogout/icons/lock.svg" "$HOME/Pictures/Wallpapers/$n.png"; done
bash "$REPO_DIR/scripts/bin/aether-wall" favourite "$HOME/Pictures/Wallpapers/city/c.png" >/dev/null
# (no history yet: the ordering must still list every wallpaper — this once stopped after the favourites)
order="$(bash -c '. "$1"; gallery_order all' _ <(sed -n '/^cmd="\${1:-help}"/,$d; p' "$REPO_DIR/scripts/bin/aether-wall" | sed "s|\$(dirname \"\$(readlink -f \"\${BASH_SOURCE\[0\]}\")\")|$REPO_DIR/scripts/bin|") 2>/dev/null | head -1)"
cats="$(bash -c '. "$1"; gallery_order space' _ <(sed -n '/^cmd="\${1:-help}"/,$d; p' "$REPO_DIR/scripts/bin/aether-wall" | sed "s|\$(dirname \"\$(readlink -f \"\${BASH_SOURCE\[0\]}\")\")|$REPO_DIR/scripts/bin|") 2>/dev/null)"
count="$(bash -c '. "$1"; gallery_order all' _ <(sed -n '/^cmd="\${1:-help}"/,$d; p' "$REPO_DIR/scripts/bin/aether-wall" | sed "s|\$(dirname \"\$(readlink -f \"\${BASH_SOURCE\[0\]}\")\")|$REPO_DIR/scripts/bin|") 2>/dev/null | grep -c "Wallpapers/")"
if [ "$order" = "$HOME/Pictures/Wallpapers/city/c.png" ] && [ "$cats" = "$HOME/Pictures/Wallpapers/space/a.png" ] && [ "$count" -ge 3 ]; then
    pass "gallery lists favourites first and filters by sub-folder category"
else
    fail "gallery order/category wrong: first='$order' space='$cats' count='$count'"
fi

# ── custom Rofi keys never collide with Rofi's own defaults ─────────────
python3 - "$REPO_DIR/scripts/bin" <<'PY' || failed=1
import os, re, sys
DEFAULTS = {"alt+s", "alt+b", "alt+d", "alt+f", "alt+h", "alt+1", "alt+2", "alt+3", "alt+4", "alt+5", "alt+6",
            "alt+7", "alt+8", "alt+9", "alt+0", "control+c", "control+v", "control+a", "control+e", "control+f",
            "control+b", "control+d", "control+h", "control+k", "control+u", "control+w", "control+n", "control+p",
            "control+j", "control+m", "control+g", "control+i", "control+l", "control+space", "control+tab"}
bad = []
for f in sorted(os.listdir(sys.argv[1])):
    t = open(os.path.join(sys.argv[1], f), encoding="utf-8", errors="replace").read()
    for key in re.findall(r'-kb-custom-\d+\s+"([^"]+)"', t):
        if key.lower() in DEFAULTS:
            bad.append("%s: %s" % (f, key))
print("FAIL: custom Rofi keys clash with Rofi defaults: " + ", ".join(bad) if bad else "PASS: custom Rofi keys don't clash with Rofi's default bindings")
sys.exit(1 if bad else 0)
PY

# ── dock: pins resolve to real icons, generated modules parse, bad IDs refused ──
if bash "$REPO_DIR/scripts/bin/aether-dock" generate >/dev/null 2>&1 \
    && python3 -c 'import json, re, sys
t = open(sys.argv[1], encoding="utf-8").read()
d = json.loads(re.sub(r"^//.*$", "", t, flags=re.M))
assert "group/dock-pins" in d and "custom/launchpad" in d
for k, v in d.items():
    if k.startswith("image#dock-"):
        import os; assert os.path.isfile(v["path"]) and v["on-click"].startswith("aether-dock activate ")' "$HOME/.config/aether-shell/classic/waybar/dock-modules.jsonc"; then
    pass "aether-dock generates valid dock modules (every icon is a real file, every click focuses or launches via aether-dock activate)"
else
    fail "aether-dock generate produced invalid modules"
fi
bash "$REPO_DIR/scripts/bin/aether-dock" add 'x;rm -rf ~' >/dev/null 2>&1 && fail "aether-dock accepted an unsafe ID" || pass "aether-dock refuses unsafe app IDs"
bash "$REPO_DIR/scripts/bin/aether-dock" size 500 >/dev/null 2>&1 && fail "aether-dock accepted a silly icon size" || pass "aether-dock validates icon size"
idle='{"text": "", "class": "idle", "alt": "idle", "tooltip": ""}'
ok=1
for sub in title artist "ctl play" "ev 1" osd; do
    # shellcheck disable=SC2086 # sub holds a sub-command and its argument
    [ "$(bash "$REPO_DIR/scripts/bin/aether-island" $sub)" = "$idle" ] || ok=0
done
[ "$ok" = 1 ] && pass "island shows no track, controls or events when no player is running" || fail "island invented data without a player"
cstate_osd_home="$HOME/.config/aether-shell/classic/state.conf"
bash "$REPO_DIR/scripts/bin/aether-island" show-osd "󰕾" 60 Volume
out="$(bash "$REPO_DIR/scripts/bin/aether-island" osd)"
grep -q '"text": "󰕾  ━━━━━━────  60%"' <<< "$out" && pass "volume key shows a level bar in the island" || fail "island OSD wrong: $out"
sleep 2.5
[ "$(bash "$REPO_DIR/scripts/bin/aether-island" osd)" = "$idle" ] && pass "island level bar collapses after ~2 s" || fail "island OSD did not expire"
: "$cstate_osd_home"

# ── Settings window: builds every page against the real helpers ─────────
if python3 -c 'import gi; gi.require_version("Gtk", "3.0"); from gi.repository import Gtk' 2>/dev/null && command -v xvfb-run >/dev/null; then
    out="$(xvfb-run -a python3 - "$REPO_DIR/lib" <<'PY' 2>&1
import sys
sys.path.insert(0, sys.argv[1])
from aether import settings_app as sa
win = sa.Settings("looks")
bad = []
for key, *_ in sa.PAGES:
    try:
        w = win.page(key)
        assert w is not None
    except Exception as e:  # noqa: BLE001
        bad.append("%s: %r" % (key, e))
print("BAD " + "; ".join(bad) if bad else "OK %d" % len(sa.PAGES))
PY
)"
    if grep -q "^OK " <<< "$out"; then pass "Settings window builds all $(sed -n 's/^OK //p' <<< "$out") pages"; else fail "Settings window: $out"; fi
else
    skip "GTK 3 Python bindings or xvfb-run missing — Settings window not built"
fi

# ── glass levels and the Control Centre panel ───────────────────────────
for lvl in off subtle acrylic deep; do
    bash "$REPO_DIR/scripts/bin/aether-glass" "$lvl" >/dev/null 2>&1 || fail "aether-glass $lvl failed"
done
bash "$REPO_DIR/scripts/bin/aether-glass" acrylic >/dev/null 2>&1
f="$HOME/.config/aether-shell/hypr/glass.conf"
if grep -q "active_opacity = 0.90" "$f" && grep -q "passes = 3" "$f" && [ "$(grep -o '{' "$f" | wc -l)" = "$(grep -o '}' "$f" | wc -l)" ] \
    && grep -q "rgba(.*0.74)" "$HOME/.config/aether-shell/classic/colors/rofi.rasi" \
    && grep -q "^background_opacity    0.72" "$HOME/.config/aether-shell/terminal/kitty-theme.conf"; then
    pass "aether-glass writes the Hyprland glass fragment and matching translucent colours"
else
    fail "aether-glass output is wrong"
fi
bash "$REPO_DIR/scripts/bin/aether-glass" cloudy >/dev/null 2>&1 && fail "aether-glass accepted an unknown level" || pass "aether-glass rejects unknown levels"
if python3 -c 'import gi; gi.require_version("Gtk", "3.0"); from gi.repository import Gtk' 2>/dev/null && command -v xvfb-run >/dev/null; then
    out="$(xvfb-run -a python3 - "$REPO_DIR/lib" <<'PY' 2>&1
import sys
sys.path.insert(0, sys.argv[1])
from aether import control_center as ccp, controls as ctl
ccp.load_css(0.72)
p = ccp.Panel(list(ctl.CONTROLS), interactive=False)
states = {cid: c.state() if c.available() else {"disabled": True, "label": "Not installed"} for cid, c in ctl.CONTROLS.items()}
p.apply_states(states)
print("OK %d" % len(p.widgets))
PY
)"
    grep -q "^OK $(python3 -c "import sys; sys.path.insert(0, '$REPO_DIR/lib'); from aether import controls; print(len(controls.CONTROLS))")" <<< "$out" \
        && pass "Control Centre panel builds every control and applies real states" || fail "Control Centre panel: $out"
fi

# ── helpers that can run without a session ─────────────────────────────
n="$(bash "$REPO_DIR/scripts/bin/aether-menu" keys-list | wc -l)"
if [ "$n" -ge 60 ] && bash "$REPO_DIR/scripts/bin/aether-menu" keys-list | grep -q "SUPER + H .*Keyboard shortcuts"; then
    pass "keybinding reference lists $n bindings with descriptions"
else
    fail "keybinding reference is short or lacks descriptions ($n rows)"
fi
calc() { PATH="/usr/bin:/bin" bash -c '. "$1"; calc_eval "$2"' _ "$TEST_HOME/calc.sh" "$1"; }
sed -n '/^calc_eval() {/,/^}/p' "$REPO_DIR/scripts/bin/aether-menu" | sed 's/if have qalc; then/if false; then/' > "$TEST_HOME/calc.sh"
# shellcheck disable=SC2016 # written literally into the sourced file
echo 'have() { command -v "$1" >/dev/null 2>&1; }' >> "$TEST_HOME/calc.sh"
if [ "$(calc '2^10 + sqrt(16)')" = 1028 ] && [ "$(calc '7/2')" = 3.5 ] && calc '__import__("os").system("true")' | grep -q '^error'; then
    pass "built-in calculator evaluates arithmetic and refuses code"
else
    fail "built-in calculator: '$(calc '2^10 + sqrt(16)')' / '$(calc '__import__("os")')'"
fi
w="$(bash "$REPO_DIR/scripts/bin/aether-weather")"
[ "$w" = '{"text": ""}' ] && pass "weather is opt-in (no network request by default)" || fail "weather made a request without being enabled: $w"
bash "$REPO_DIR/scripts/bin/aether-colors" waybar-json | python3 -c 'import json, sys; d = json.load(sys.stdin); assert d["alt"] in ("dark", "light")' \
    && pass "theme module JSON is valid" || fail "aether-colors waybar-json is not valid JSON"
mkdir -p "$HOME/Pictures/Wallpapers"
cp "$REPO_DIR/config/wlogout/icons/lock.svg" "$HOME/Pictures/Wallpapers/a b.png"
[ "$(bash "$REPO_DIR/scripts/bin/aether-wall" list | grep -c 'a b.png')" = 1 ] && pass "wallpaper discovery handles spaces in names" || fail "aether-wall list missed a file with spaces"
for s in "$REPO_DIR"/scripts/bin/aether-{wall,menu,osd,toggle,powermenu,shot,waybar,weather,interface,classic-start,colors,look,lock,bindings,dock,island,settings,glass,control}; do
    bash "$s" --help >/dev/null 2>&1 || bash "$s" help >/dev/null 2>&1 || { [ $? -eq 2 ] || fail "$(basename "$s") --help crashed"; }
done
pass "every classic helper answers --help"

echo
for s in "${skipped[@]}"; do echo "SKIP: $s"; done
if [ "$failed" -eq 0 ]; then echo "PASS: classic interface checks passed"; else echo "FAIL: see above"; exit 1; fi
