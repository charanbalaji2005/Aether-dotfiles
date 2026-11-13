# shellcheck shell=bash
# ULTRON RECOVERY — validators. Each prints a short reason on failure and
# returns non-zero; none of them changes anything.

# Strip // and /* */ comments outside strings, and trailing commas, then parse.
validate_jsonc() {
    python3 -I - "$1" <<'PY'
import json, sys
src = open(sys.argv[1], encoding="utf-8").read()
out, i, n, s = [], 0, len(src), None
while i < n:
    ch = src[i]
    if s:
        out.append(ch)
        if ch == "\\" and i + 1 < n: out.append(src[i + 1]); i += 1
        elif ch == s: s = None
    elif ch == '"': s = ch; out.append(ch)
    elif src.startswith("//", i):
        j = src.find("\n", i); i = n if j < 0 else j; continue
    elif src.startswith("/*", i):
        j = src.find("*/", i + 2)
        if j < 0: print("unclosed /* comment"); sys.exit(1)
        i = j + 2; continue
    else: out.append(ch)
    i += 1
import re
text = re.sub(r",(\s*[}\]])", r"\1", "".join(out))
try:
    json.loads(text)
except ValueError as e:
    print(str(e)); sys.exit(1)
PY
}

# Balanced braces/brackets/parens outside strings and comments (CSS, RASI, QML).
validate_balance() {  # validate_balance FILE css|rasi|qml
    python3 -I - "$1" "$2" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8", errors="replace").read()
kind = sys.argv[2]
kind_js = kind == "qml"
def prev_allows_regex(src, i):
    j = i - 1
    while j >= 0 and src[j] in " \t": j -= 1
    if j < 0 or src[j] in "(,=:[!&|?{};\n": return True
    return src[max(0, j - 5):j + 1].endswith("return")
pairs = {"}": "{", "]": "[", ")": "("}
stack, i, n, s, line = [], 0, len(src), None, 1
while i < n:
    ch = src[i]
    if ch == "\n": line += 1
    if s:
        if ch == "\\": i += 2; continue
        if ch == s: s = None
    elif ch in "\"'": s = ch
    elif src.startswith("/*", i):
        j = src.find("*/", i + 2)
        if j < 0: print("line %d: unclosed comment" % line); sys.exit(1)
        line += src.count("\n", i, j); i = j + 2; continue
    elif kind in ("qml", "rasi") and src.startswith("//", i):
        j = src.find("\n", i); i = n if j < 0 else j; continue
    elif ch == "/" and kind_js and not src.startswith("//", i) and not src.startswith("/*", i) and prev_allows_regex(src, i):
        j, cls = i + 1, False
        while j < n and src[j] != "\n":
            if src[j] == "\\": j += 2; continue
            if src[j] == "[": cls = True
            elif src[j] == "]": cls = False
            elif src[j] == "/" and not cls: break
            j += 1
        i = j + 1; continue
    elif ch in "{[(": stack.append((ch, line))
    elif ch in "}])":
        if not stack or stack[-1][0] != pairs[ch]:
            print("line %d: unexpected '%s'" % (line, ch)); sys.exit(1)
        stack.pop()
    i += 1
if s: print("unterminated string"); sys.exit(1)
if stack: print("line %d: '%s' never closed" % (stack[-1][1], stack[-1][0])); sys.exit(1)
PY
}

validate_css()  { validate_balance "$1" css; }
validate_qml()  { validate_balance "$1" qml; }

# RASI: balanced, and every @import / @theme target exists.
validate_rasi() {
    local f="$1" dir ref path
    validate_balance "$f" rasi || return 1
    dir="$(dirname "$f")"
    while IFS= read -r ref; do
        [ -n "$ref" ] || continue
        path="${ref/#\~/$HOME}"
        case "$path" in /*) ;; *) path="$dir/$path" ;; esac
        [ -f "$path" ] || [ -f "$path.rasi" ] || [ -f "$HOME/.config/rofi/themes/$ref.rasi" ] \
            || [ -f "$HOME/.local/share/rofi/themes/$ref.rasi" ] || [ -f "/usr/share/rofi/themes/$ref.rasi" ] \
            || { echo "missing theme reference: $ref"; return 1; }
    done < <(sed -nE 's/^[[:space:]]*@(import|theme)[[:space:]]+"([^"]+)".*/\2/p' "$f")
}

# Hyprland's own parser. 0.57+ reads configs as Lua, so the Lua entry point is
# checked when it exists (it loads hyprland.conf); success is "config ok".
validate_hyprland() {
    local dir="$1" entry out
    command -v Hyprland >/dev/null 2>&1 || { echo "Hyprland not installed — cannot verify"; return 2; }
    entry="$dir/hyprland.lua"; [ -f "$entry" ] || entry="$dir/hyprland.conf"
    [ -f "$entry" ] || { echo "no hyprland.lua or hyprland.conf"; return 1; }
    out="$(timeout 30 Hyprland --verify-config -c "$entry" 2>&1)"
    if grep -q 'config ok' <<< "$out"; then return 0; fi
    sed -n '/Config parsing result/,$p' <<< "$out" | grep -v '^=*\s*Config parsing result' | sed '/^\s*$/d' | head -5
    return 1
}

validate_shell() {  # bash/sh/zsh syntax by shebang or extension
    local f="$1" sh=bash first
    first="$(head -c 64 "$f" 2>/dev/null | head -1)"
    case "$first$f" in *zsh*) sh=zsh ;; esac
    command -v "$sh" >/dev/null 2>&1 || return 0
    "$sh" -n "$f" 2>&1 | head -3
    return "${PIPESTATUS[0]}"
}

# broken_symlinks DIR [DEPTH] — dangling links under DIR
broken_symlinks() { find -L "$1" -maxdepth "${2:-4}" -type l 2>/dev/null; }

# permission_problems DIR — files not yours, world-writable, or scripts without +x
permission_problems() {
    local d="$1" f
    find -L "$d" -maxdepth 4 \( -name .git -o -name node_modules \) -prune -o ! -user "$(id -u)" -print 2>/dev/null | head -20 | sed 's/^/not owned by you: /'
    find -L "$d" -maxdepth 4 -type f -perm -0002 2>/dev/null | head -20 | sed 's/^/world-writable: /'
    while IFS= read -r f; do
        head -c 2 "$f" 2>/dev/null | grep -q '#!' && [ ! -x "$f" ] && echo "script not executable: $f"
    done < <(find -L "$d" -maxdepth 4 -type f \( -name '*.sh' -o -path '*/scripts/*' -o -path '*/bin/*' \) 2>/dev/null)
}

# command_exists "CMDLINE" — first word of a command line is runnable
command_exists() {
    local w
    read -r w _ <<< "$1"
    w="${w/#\~/$HOME}"
    case "$w" in ''|'['*|'{'*|'('*|*=*) return 0 ;; esac
    [ -x "$w" ] || command -v "$w" >/dev/null 2>&1
}

# validate_qml_tree DIR — bracket balance of every .qml under DIR in one pass;
# prints "file: reason" for each bad file.
validate_qml_tree() {
    python3 -I - "$1" <<'PY'
import os, sys
pairs = {"}": "{", "]": "[", ")": "("}
kind_js = True
def prev_allows_regex(src, i):
    j = i - 1
    while j >= 0 and src[j] in " \t": j -= 1
    if j < 0 or src[j] in "(,=:[!&|?{};\n": return True
    return src[max(0, j - 5):j + 1].endswith("return")
def check(src):
    stack, i, n, s, line = [], 0, len(src), None, 1
    while i < n:
        ch = src[i]
        if ch == "\n": line += 1
        if s:
            if ch == "\\": i += 2; continue
            if ch == s: s = None
        elif ch in "\"'`": s = ch
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            if j < 0: return "line %d: unclosed comment" % line
            line += src.count("\n", i, j); i = j + 2; continue
        elif src.startswith("//", i):
            j = src.find("\n", i); i = n if j < 0 else j; continue
        elif ch == "/" and kind_js and not src.startswith("//", i) and not src.startswith("/*", i) and prev_allows_regex(src, i):
            j, cls = i + 1, False
            while j < n and src[j] != "\n":
                if src[j] == "\\": j += 2; continue
                if src[j] == "[": cls = True
                elif src[j] == "]": cls = False
                elif src[j] == "/" and not cls: break
                j += 1
            i = j + 1; continue
        elif ch in "{[(": stack.append((ch, line))
        elif ch in "}])":
            if not stack or stack[-1][0] != pairs[ch]: return "line %d: unexpected '%s'" % (line, ch)
            stack.pop()
        i += 1
    if stack: return "line %d: '%s' never closed" % (stack[-1][1], stack[-1][0])
    return None
bad = 0
for root, dirs, files in os.walk(sys.argv[1], followlinks=True):
    dirs[:] = [d for d in dirs if d not in (".git", "node_modules")]
    for f in files:
        if f.endswith(".qml"):
            p = os.path.join(root, f)
            try: r = check(open(p, encoding="utf-8", errors="replace").read())
            except OSError as e: r = str(e)
            if r: print("%s: %s" % (p, r)); bad += 1
sys.exit(1 if bad else 0)
PY
}
