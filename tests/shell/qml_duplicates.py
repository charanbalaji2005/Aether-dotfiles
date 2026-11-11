#!/usr/bin/python3
"""No QML object assigns the same property or handler twice at its top level
(e.g. two `Component.onCompleted:`). qmllint's syntax check accepts this, but
QML refuses to load the component at runtime ("Property value set multiple
times"), which for a singleton service takes the whole feature down."""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "tools"))
import qs_api_check as q  # noqa: E402  (reuses its string-aware stripper and block parser)

shell = sys.argv[1]
problems = []
for base, _d, files in os.walk(shell):
    for f in files:
        if not f.endswith(".qml"):
            continue
        path = os.path.join(base, f)
        code = q._strip(open(path, encoding="utf-8").read())
        for t, _start, body in q.blocks(code):
            seen = {}
            depth = 0
            for line in body.split("\n"):
                if depth == 0:
                    m = re.match(r"\s*((?:[a-zA-Z_]\w*\.)*[a-zA-Z_]\w*)\s*:(?!:)", line)
                    if m and not re.match(r"\s*(case|default)\b", line):
                        key = m.group(1)
                        if key in seen:
                            problems.append("%s: %s assigns '%s' twice" % (os.path.relpath(path, shell), t, key))
                        seen[key] = True
                depth += line.count("{") + line.count("(") + line.count("[") - line.count("}") - line.count(")") - line.count("]")
                depth = max(depth, 0)
for p in sorted(set(problems)):
    print("FAIL: " + p)
print("PASS: no property or handler is assigned twice on one object" if not problems else "%d duplicate assignment(s)" % len(set(problems)))
sys.exit(1 if problems else 0)
