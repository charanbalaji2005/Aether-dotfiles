#!/usr/bin/python3
"""Check every Quickshell API AetherOS uses against Quickshell's source.

    python3 tools/qs_api_check.py <quickshell-source-dir> [--json]

What it extracts from the C++ headers: every QML-exposed class (QML_ELEMENT /
QML_NAMED_ELEMENT / QML_SINGLETON / QML_ATTACHED), its base classes, Q_PROPERTY
names, signals, Q_INVOKABLE methods and Q_ENUM values. Qt base classes
(QObject, QQuickItem, QQuickWindow, …) are filled in by introspecting Qt's own
metaobjects through PySide6.

What it checks in the shell's QML, for Quickshell types only:
  * every property assignment / signal handler / grouped property written
    directly inside a `Type { … }` block exists on that type or its bases;
  * `Type.member` and `Type.Enum` references (singletons, enums, attached
    properties such as WlrLayershell.layer) exist;
  * `id.member` calls on objects whose id belongs to a Quickshell type.

It is a static API conformance check — it proves names exist in that
Quickshell version, not that the shell behaves correctly at runtime.
Exit 1 when anything doesn't resolve.
"""

import json
import os
import re
import sys

SHELL = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "config", "quickshell", "aether-shell")


# -- extraction ---------------------------------------------------------------

def _body(text, start):
    """Text between the '{' at/after start and its matching '}'."""
    i = text.index("{", start)
    depth = 0
    for j in range(i, len(text)):
        c = text[j]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[i + 1:j]
    return text[i + 1:]


NAMESPACE_RE = re.compile(r"^\s*namespace\s+(\w+)\s*\{", re.M)
CLASS_RE = re.compile(r"^\s*class\s+(?:Q_DECL_EXPORT\s+)?(\w+)\s*(?:final\s*)?(?::\s*([^{;]+))?\{", re.M)


def extract(src):
    classes = {}
    for root, _dirs, files in os.walk(src):
        for f in files:
            if not f.endswith((".hpp", ".h")):
                continue
            text = open(os.path.join(root, f), encoding="utf-8", errors="replace").read()
            text = re.sub(r"//[^\n]*", "", text)
            for m in CLASS_RE.finditer(text):
                name = m.group(1)
                bases = [re.sub(r"^(public|protected|private|virtual)\s+", "", b.strip()).split("<")[0].strip()
                         for b in (m.group(2) or "").split(",") if b.strip()]
                body = _body(text, m.start())
                qml = None
                nm = re.search(r"QML_NAMED_ELEMENT\((\w+)\)", body)
                if nm:
                    qml = nm.group(1)
                elif re.search(r"\bQML_ELEMENT\b", body):
                    qml = name
                props = set(re.findall(r"Q_PROPERTY\([^)]*?\b(\w+)\s+(?:READ|MEMBER|BINDABLE|WRITE)\b", body))
                invokables = set(re.findall(r"Q_INVOKABLE\s+(?:static\s+)?[\w:<>,*& ]+?\b(\w+)\s*\(", body))
                signals = set()
                for sec in re.findall(r"signals:(.*?)(?:\n\s*(?:public|private|protected)(?:\s+slots)?:|\Z)", body, re.S):
                    signals |= set(re.findall(r"void\s+(\w+)\s*\(", sec))
                enums = {}
                for em in re.finditer(r"enum\s+(\w+)\s*(?::\s*[\w:]+)?\s*\{(.*?)\}", body, re.S):
                    vals = [v.split("=")[0].strip() for v in re.sub(r"/\*.*?\*/", "", em.group(2), flags=re.S).split(",")]
                    enums[em.group(1)] = [v for v in vals if re.match(r"^\w+$", v)]
                att = re.search(r"QML_ATTACHED\((\w+)\)", body)
                prev = classes.get(name)
                if prev and not prev["qml"] and qml is None and not props:
                    continue
                classes[name] = {
                    "qml": qml, "bases": bases, "props": props, "signals": signals, "methods": invokables,
                    "enums": enums, "singleton": "QML_SINGLETON" in body, "attached": att.group(1) if att else None,
                }
            # QML enum namespaces: namespace X { Q_NAMESPACE; QML_ELEMENT; enum Enum {...}; Q_ENUM_NS(Enum); }
            for m in NAMESPACE_RE.finditer(text):
                body = _body(text, m.start())
                if "Q_ENUM_NS" not in body or not re.search(r"\bQML_(NAMED_)?ELEMENT\b", body):
                    continue
                nm = re.search(r"QML_NAMED_ELEMENT\((\w+)\)", body)
                enums = {}
                for em in re.finditer(r"enum\s+(\w+)\s*(?::\s*[\w:]+)?\s*\{(.*?)\}", body, re.S):
                    vals = [v.split("=")[0].strip() for v in re.sub(r"/\*.*?\*/", "", em.group(2), flags=re.S).split(",")]
                    enums[em.group(1)] = [v for v in vals if re.match(r"^\w+$", v)]
                classes["ns:" + m.group(1)] = {"qml": nm.group(1) if nm else m.group(1), "bases": [], "props": set(),
                                               "signals": set(), "methods": {"toString"}, "enums": enums,
                                               "singleton": False, "attached": None}
    return classes


def qt_members(cls):
    """Properties, signals and methods of a Qt class via PySide6 (None if unknown)."""
    try:
        from PySide6 import QtCore, QtGui, QtQuick, QtQml  # noqa: F401
    except ImportError:
        return None
    for mod in (QtQuick, QtGui, QtCore, QtQml):
        k = getattr(mod, cls, None)
        if k is None or not hasattr(k, "staticMetaObject"):
            continue
        mo = k.staticMetaObject
        props = {mo.property(i).name() for i in range(mo.propertyCount())}
        sigs, meths = set(), set()
        for i in range(mo.methodCount()):
            m = mo.method(i)
            n = bytes(m.name()).decode()
            (sigs if m.methodType() == QtCore.QMetaMethod.MethodType.Signal else meths).add(n)
        return props, sigs, meths
    return None


class Api:
    def __init__(self, src):
        self.classes = extract(src)
        self.by_qml = {}
        for cname, c in self.classes.items():
            if c["qml"]:
                self.by_qml.setdefault(c["qml"], cname)
        self._qt = {}

    def members(self, cname, seen=None):
        """(props, signals, methods, enum values) incl. bases; None marks unknown Qt base."""
        seen = seen or set()
        if cname in seen:
            return set(), set(), set(), set()
        seen.add(cname)
        c = self.classes.get(cname)
        if c is None:
            if cname not in self._qt:
                self._qt[cname] = qt_members(cname)
            q = self._qt[cname]
            return (set(q[0]), set(q[1]), set(q[2]), set()) if q else (set(), set(), set(), set())
        props, sigs, meths = set(c["props"]), set(c["signals"]), set(c["methods"])
        enums = {v for vals in c["enums"].values() for v in vals}
        for b in c["bases"]:
            p, s, m, e = self.members(b, seen)
            props |= p; sigs |= s; meths |= m; enums |= e
        return props, sigs, meths, enums


# -- checking -----------------------------------------------------------------

QS_IMPORT = re.compile(r"^import\s+(Quickshell(?:\.[\w.]+)?)\s*$", re.M)


def _strip(text):
    """Remove imports, comments and string contents — in one string-aware
    pass, so '//' inside a string (e.g. "trash:///") isn't taken as a comment."""
    text = re.sub(r"(?m)^\s*import\s+[^\n]*$", "", text)
    out, i, n, quote = [], 0, len(text), None
    while i < n:
        c = text[i]
        if quote:
            if c == "\\":
                i += 2
                continue
            if c == quote:
                out.append(c)
                quote = None
            i += 1
            continue
        if c in "\"'`":
            quote = c
            out.append(c)
            i += 1
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def blocks(code):
    """Yield (type, start, body) for every `Type {` object block."""
    for m in re.finditer(r"(?<![\w.])([A-Z]\w*)\s*\{", code):
        yield m.group(1), m.start(), _body(code, m.end() - 1)


def top_level_statements(body):
    """Identifiers assigned or handled at depth 0 of an object body."""
    out, depth, line_start = [], 0, True
    i = 0
    while i < len(body):
        c = body[i]
        if c in "{([":
            depth += 1
        elif c in "})]":
            depth -= 1
        elif depth == 0 and line_start:
            m = re.match(r"\s*(?:readonly\s+|required\s+|default\s+)?(property|signal|function|component|id)\b", body[i:])
            if not m:
                m2 = re.match(r"\s*([a-zA-Z_][\w]*)(?:\.(\w+))?\s*(:|\{)", body[i:])
                if m2 and not re.match(r"[A-Z]", m2.group(1)):
                    out.append((m2.group(1), m2.group(2)))
        line_start = c in "\n;" or (line_start and c in " \t")
        i += 1
    return out


def declared(body):
    """(members, id) a QML file declares on an object itself (depth 0 of its body)."""
    names = set()
    obj_id = None
    depth = 0
    for line in body.split("\n"):
        if depth == 0:
            m = re.match(r"\s*id:\s*(\w+)", line)
            if m and obj_id is None:
                obj_id = m.group(1)
            m = re.match(r"\s*(?:readonly\s+|required\s+|default\s+)*property\s+[\w<>.]+\s+(\w+)", line)
            if m:
                names.add(m.group(1))
            m = re.match(r"\s*(?:signal|function)\s+(\w+)", line)
            if m:
                names.add(m.group(1))
            m = re.match(r"\s*property\s+alias\s+(\w+)", line)
            if m:
                names.add(m.group(1))
        depth += line.count("{") + line.count("(") + line.count("[") - line.count("}") - line.count(")") - line.count("]")
        depth = max(depth, 0)
    return names, obj_id


def check(api, shell=SHELL):
    problems = []
    used_types = set()
    for root, _d, files in os.walk(shell):
        for f in files:
            if not f.endswith(".qml"):
                continue
            path = os.path.join(root, f)
            raw = open(path, encoding="utf-8").read()
            if not QS_IMPORT.search(raw):
                continue
            code = _strip(raw)
            rel = os.path.relpath(path, shell)
            ids = {}
            for t, start, body in blocks(code):
                cname = api.by_qml.get(t)
                if cname is None:
                    continue
                used_types.add(t)
                own, obj_id = declared(body)
                if obj_id and obj_id not in ids:
                    ids[obj_id] = (cname, own)
                props, sigs, meths, _e = api.members(cname)
                props = props | own
                sigs = sigs | own
                for name, sub in top_level_statements(body):
                    if name.startswith("on") and (name[2:3].isupper() or name[2:3] == "_"):
                        # onFooChanged -> fooChanged; on_FooChanged -> _fooChanged (Qt's rule for _props)
                        sig = ("_" + name[3].lower() + name[4:]) if name[2] == "_" else (name[2].lower() + name[3:])
                        base = sig[:-7] if sig.endswith("Changed") else None
                        if sig in sigs or (base and base in props):
                            continue
                        problems.append("%s: %s has no signal for handler %s" % (rel, t, name))
                    elif name not in props and name != "anchors" and not (sub and name in api.by_qml):
                        problems.append("%s: %s has no property '%s'" % (rel, t, name))
            # Type.member references (singletons, enums, attached properties).
            for m in re.finditer(r"(?<![\w.])([A-Z]\w*)\.(\w+)", code):
                t, member = m.group(1), m.group(2)
                cname = api.by_qml.get(t)
                if cname is None:
                    continue
                used_types.add(t)
                c = api.classes[cname]
                props, sigs, meths, enums = api.members(cname)
                att = api.members(c["attached"]) if c["attached"] else (set(), set(), set(), set())
                if member in props | sigs | meths | enums | att[0] | att[1] | att[2]:
                    continue
                problems.append("%s: %s has no member '%s'" % (rel, t, member))
            # id.method(...) on Quickshell objects.
            for m in re.finditer(r"(?<![\w.])(\w+)\.(\w+)\s*\(", code):
                entry = ids.get(m.group(1))
                if entry is None:
                    continue
                cname, own = entry
                props, sigs, meths, _e = api.members(cname)
                if m.group(2) not in meths | sigs | own:
                    problems.append("%s: %s (%s) has no method '%s'" % (rel, m.group(1), api.classes[cname]["qml"], m.group(2)))
    return sorted(set(problems)), sorted(used_types)


def main(argv):
    if not argv or not os.path.isdir(argv[0]):
        sys.stderr.write(__doc__)
        return 2
    api = Api(argv[0])
    problems, used = check(api)
    if "--json" in argv:
        print(json.dumps({"problems": problems, "typesUsed": used}, indent=2))
    else:
        print("Quickshell types used: %s" % ", ".join(used))
        for p in problems:
            print("FAIL: " + p)
        print("%d API problem(s)" % len(problems) if problems else "PASS: every Quickshell API used resolves")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
