#!/usr/bin/env python3
"""Every QML file that uses a type defined in one of the shell's directories
(components/, graphics/, animation/, core/, services/, theme/) must import that
directory. qmllint can't check this for relative directory imports, and the
failure only shows up at runtime as "X is not a type"."""
import os
import re
import sys

shell = sys.argv[1]
dirs = {d: {f[:-4] for f in os.listdir(os.path.join(shell, d)) if f.endswith(".qml")}
        for d in ("components", "graphics", "animation", "core", "services", "theme")}
problems = []
for base, _, files in os.walk(shell):
    for f in files:
        if not f.endswith(".qml"):
            continue
        path = os.path.join(base, f)
        text = open(path, encoding="utf-8").read()
        code = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', re.sub(r"//[^\n]*", "", text))
        imports = re.findall(r'^import "([^"]+)"', text, re.M)
        own = os.path.basename(base)
        for d, types in dirs.items():
            if own == d:
                continue
            used = sorted(t for t in types if re.search(r"(?<![\w.])%s\s*[{.]" % t, code))
            if used and not any(i.rstrip("/").endswith(d) for i in imports):
                problems.append("%s uses %s but doesn't import \"%s\"" % (os.path.relpath(path, shell), ", ".join(used[:4]), d))
for p in problems:
    print("FAIL: " + p)
print("PASS: every shell type used is imported" if not problems else "%d file(s) with missing imports" % len(problems))
sys.exit(1 if problems else 0)
