#!/usr/bin/env bash
# ULTRON RECOVERY — validator tests (isolated fake $HOME; see helpers.sh).
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/helpers.sh"
echo "test-validation"
setup_home
UR_HOME="$UR_TEST_ROOT"
for f in ui logging validation detection; do . "$UR_TEST_ROOT/core/$f.sh"; done
V="$T/v"; mkdir -p "$V"
no() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$d"; else pass "$d"; fi; }

# JSONC
printf '// c\n{ "a": "http://x/*y*/", /* b */ "c": [1, 2,], }\n' > "$V/ok.jsonc"
printf '{ "a": 1 "b": 2 }\n' > "$V/bad.jsonc"
check "JSONC with comments, URLs and trailing commas is valid" validate_jsonc "$V/ok.jsonc"
no "JSONC missing a comma is rejected" validate_jsonc "$V/bad.jsonc"

# CSS
printf '/* x { */ a { color: red; }\nb { content: "}"; }\n' > "$V/ok.css"
printf 'a { color: red;\n' > "$V/bad.css"
check "CSS with braces in comments and strings is valid" validate_css "$V/ok.css"
no "CSS with an unclosed block is rejected" validate_css "$V/bad.css"

# RASI
mkdir -p "$V/themes"; printf '* { bg: #000; }\n' > "$V/themes/base.rasi"
printf '@import "themes/base.rasi"\nwindow { width: 50%%; }\n' > "$V/ok.rasi"
printf '@theme "does-not-exist"\n' > "$V/missing.rasi"
check "RASI with a resolvable @import is valid" validate_rasi "$V/ok.rasi"
no "RASI with a missing @theme is rejected" validate_rasi "$V/missing.rasi"

# QML (regex literals must not count as brackets)
printf 'Item {\n  property var r: /[(]/\n  function f() { return /\\)/.test(x) ? (1 + 2) / 3 : 0; }\n}\n' > "$V/ok.qml"
printf 'Item {\n  Text { text: "a"\n}\n' > "$V/bad.qml"
check "QML with regex literals and division is valid" validate_qml "$V/ok.qml"
no "QML with an unclosed block is rejected" validate_qml "$V/bad.qml"
mkdir -p "$V/tree"; cp "$V/ok.qml" "$V/tree/A.qml"; cp "$V/bad.qml" "$V/tree/B.qml"
out="$(validate_qml_tree "$V/tree")"
check "tree check names only the bad QML file" sh -c "printf '%s' '$out' | grep -q 'B.qml' && ! printf '%s' '$out' | grep -q 'A.qml'"

# Shell
printf '#!/usr/bin/bash\nif true; then echo ok; fi\n' > "$V/ok.sh"
printf '#!/usr/bin/bash\nif true; then echo ok\n' > "$V/bad.sh"
check "valid bash script passes" validate_shell "$V/ok.sh"
no "bash script with a syntax error fails" validate_shell "$V/bad.sh"

# Hyprland's own verifier (only where Hyprland is installed)
if command -v Hyprland >/dev/null 2>&1; then
    mkdir -p "$V/hypr-ok" "$V/hypr-bad"
    printf 'monitor = , preferred, auto, 1\n' > "$V/hypr-ok/hyprland.conf"
    printf 'monitor = , preferred, auto, 1\nthis is not = a valid { line\n' > "$V/hypr-bad/hyprland.conf"
    out="$(validate_hyprland "$V/hypr-bad")"; rc=$?
    if [ "$rc" = 1 ]; then pass "Hyprland verifier rejects a broken config"; else fail "Hyprland verifier rejects a broken config (rc=$rc)"; fi
else
    echo "  (skip) Hyprland not installed — verifier not tested"
fi

# Links, permissions, commands
mkdir -p "$V/links"; ln -s "$V/nowhere" "$V/links/dangling"; ln -s "$V/ok.sh" "$V/links/fine"
check "broken symlink is found" sh -c "[ \"\$(bash -c '. $UR_TEST_ROOT/core/validation.sh; broken_symlinks $V/links')\" = '$V/links/dangling' ]"
mkdir -p "$V/perm/scripts"; printf '#!/bin/sh\n' > "$V/perm/scripts/x.sh"; chmod 644 "$V/perm/scripts/x.sh"
printf 'x\n' > "$V/perm/open.txt"; chmod 666 "$V/perm/open.txt"
out="$(permission_problems "$V/perm")"
check "non-executable script is reported" grep -q 'script not executable' <<< "$out"
check "world-writable file is reported" grep -q 'world-writable' <<< "$out"
check "existing command is found" command_exists "bash -c true"
no "missing command is reported" command_exists "definitely-not-a-command-ultron --flag"
check "env-style and quoted commands are not flagged" command_exists "[ -f x ] && foo"

# Whole components on the fake home
out="$(bash "$UR" --no-color --diagnose 2>&1)"
check "diagnostics run on a clean fake home" grep -q 'Report saved' <<< "$out"
check "diagnostics report a missing GTK settings file" grep -q 'gtk-3.0/settings.ini is missing' <<< "$out"
printf '{ "broken": }\n' > "$HOME/.config/waybar/config.jsonc"
out="$(bash "$UR" --no-color --diagnose 2>&1)"
check "diagnostics catch a broken Waybar config" grep -q 'invalid JSONC config.jsonc' <<< "$out"
check "diagnostics exit non-zero when something is wrong" sh -c "! bash '$UR' --no-color --diagnose >/dev/null 2>&1"

finish
