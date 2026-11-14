#!/usr/bin/bash
# Security invariants of the shell's QML, checked statically:
#
#  1. Lock screen: exactly one statement unlocks (`root.locked = false`),
#     and it sits inside the PamResult.Success branch of PamContext's
#     onCompleted. Any other path must leave the session locked.
#  2. No shell script is ever built by string concatenation: every
#     `sh -c` / `bash -c` takes a constant script and receives values as
#     positional arguments ("$1" …), so a file or network name can't become
#     shell syntax.
#  3. Automation and gestures can only trigger allowlisted actions — no
#     "exec"/"command" action type exists in the shell's rule table.

set -uo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHELL_DIR="$REPO_DIR/config/quickshell/aether-shell"

python3 - "$SHELL_DIR" <<'PYEOF'
import os, re, sys
root = sys.argv[1]
failed = False
def fail(msg):
    global failed
    failed = True
    print("FAIL: " + msg)

# 1. Lock screen
lock = open(os.path.join(root, "shell/lockscreen/LockScreen.qml"), encoding="utf-8").read()
code = re.sub(r"//[^\n]*", "", lock)
unlocks = [m.start() for m in re.finditer(r"\blocked\s*=\s*false\b", code)]
if len(unlocks) != 1:
    fail("LockScreen.qml has %d unlock statements (want exactly 1)" % len(unlocks))
else:
    pos = unlocks[0]
    branch = code.rfind("if (result === PamResult.Success) {", 0, pos)
    handler = code.rfind("onCompleted:", 0, pos)
    pam = code.rfind("PamContext {", 0, pos)
    # Brace depth from the branch's "{" to the unlock must never drop to 0,
    # i.e. the unlock is still inside that block.
    inside = branch >= 0
    if inside:
        depth = 0
        for ch in code[code.index("{", branch):pos]:
            depth += ch == "{"
            depth -= ch == "}"
            if depth <= 0:
                inside = False
                break
    if pam >= 0 and pam < handler < branch and inside:
        print("PASS: lock screen unlocks only in the PAM success branch")
    else:
        fail("the unlock statement is not inside PamContext.onCompleted's PamResult.Success branch")
# The session-lock surface must be driven by root.locked alone.
decl = re.findall(r"WlSessionLock \{[^}]*?locked:\s*([^\n]+)", code)
if decl != ["root.locked"]:
    fail("WlSessionLock.locked must be bound to root.locked only (found %s)" % decl)
if re.search(r"sessionLock\.locked\s*=", code):
    fail("sessionLock.locked is assigned directly")

# 1b. PamContext.start() returns false without emitting a signal when PAM
# can't start; the result must be checked, and an in-flight conversation
# aborted when the lock screen goes away.
if not re.search(r"if\s*\(\s*!\s*pam\.start\(\)\s*\)", code):
    fail("LockScreen.qml ignores the result of pam.start()")
elif "pam.abort()" not in code:
    fail("LockScreen.qml never aborts an in-flight PAM conversation")
else:
    print("PASS: pam.start() failure is handled; conversations are aborted on teardown")
if not re.search(r"pamTimeout", code):
    fail("no timeout guards a PAM conversation that never answers")

# 2. sh -c scripts are constants
bad = []
for d, _, files in os.walk(root):
    for f in files:
        if not f.endswith(".qml"):
            continue
        path = os.path.join(d, f)
        text = open(path, encoding="utf-8").read()
        for m in re.finditer(r'"(?:sh|bash)",\s*"-c",\s*', text):
            rest = text[m.end():m.end() + 400]
            # The script argument: a string literal or a named constant property.
            lit = re.match(r"""("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')\s*([,\]])""", rest)
            ident = re.match(r"root\.(_\w+)\s*([,\]])", rest)
            if lit:
                continue
            if ident:
                defn = re.search(r"property string %s:\s*\[(.*?)\]\.join" % ident.group(1), text, re.S)
                if defn and "root." not in defn.group(1) and "+" not in re.sub(r"""("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')""", "", defn.group(1)):
                    continue
            bad.append("%s: %s" % (os.path.relpath(path, root), rest[:70].replace("\n", " ")))
if bad:
    for b in bad:
        fail("non-constant shell script: " + b)
else:
    print("PASS: every sh -c / bash -c script is a constant (values passed positionally)")

# 3. Rule table has no command action
rules = open(os.path.join(root, "automation/Rules.js"), encoding="utf-8").read()
acts = re.search(r"var ACTIONS = \{(.*?)\n\};", rules, re.S).group(1)
names = re.findall(r'^\s*"([a-z-]+)":\s*\{', acts, re.M)
if any(re.search(r"exec|command|shell|run", n) for n in names):
    fail("automation ACTIONS contains a command-like action: %s" % names)
else:
    print("PASS: %d automation actions, none runs a command" % len(names))

sys.exit(1 if failed else 0)
PYEOF
