"""Desktop widgets: manifest format, discovery, validation, install/remove.

SECURITY MODEL — stated plainly:
Widgets are QML, and QML loaded into the shell runs *in the shell's process*.
There is no in-process sandbox in Qt. AetherOS therefore enforces
capabilities **statically**, at install time and again at load time:

  * imports are restricted to QtQuick, QtQuick.Layouts, QtQuick.Shapes,
    QtQuick.Controls(.Basic) and the widget's own files — no Quickshell
    (process/file/IPC access), no Qt.labs, no QtNetwork, no relative
    imports outside the widget;
  * no XMLHttpRequest, Qt.openUrlExternally, Qt.createQmlObject, Qt.include,
    Qt.createComponent, Loader/Image sources outside the widget directory,
    file:, http(s):, qrc: or data: URLs, or absolute paths;
  * data reaches a widget only through the `api` object the host injects,
    filtered to the permissions in its manifest;
  * size limits (≤ 50 files, ≤ 256 KiB each, ≤ 2 MiB total), no symlinks.

This blocks the obvious ways to read files, run programs or reach the network,
but it is NOT a sandbox against a determined attacker (e.g. a widget can
still spin the CPU or try to hide code in unusual syntax). Install widgets
only from authors you trust. Process-level isolation is future work.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import tempfile
import zipfile
from typing import Any, Dict, List, Optional, Tuple

API_VERSION = 1
PERMISSIONS = {
    "time": "current date and time",
    "system": "CPU, memory, disk and uptime",
    "gpu": "GPU utilisation, VRAM and temperature",
    "media": "current media track and play/pause/next/previous",
    "battery": "battery level and charging state",
    "network": "connection name and up/down speed",
    "theme": "AetherOS colours and fonts (always granted)",
}
ID_RE = re.compile(r"^[a-z0-9][a-z0-9.-]{0,63}$")
SEMVER = re.compile(r"^\d+\.\d+\.\d+$")
MAX_FILES, MAX_FILE, MAX_TOTAL = 50, 256 * 1024, 2 * 1024 * 1024
ALLOWED_EXT = {".qml", ".js", ".json", ".svg", ".png", ".jpg", ".webp", ".md", ".txt"}
ALLOWED_IMPORT = re.compile(r'^\s*import\s+(QtQuick|QtQuick\.Layouts|QtQuick\.Shapes|QtQuick\.Controls|QtQuick\.Controls\.Basic)(\s+\d+(\.\d+)?)?\s*(as\s+\w+)?\s*;?\s*$')
LOCAL_IMPORT = re.compile(r'^\s*import\s+"(?!\.\.)(?!/)[\w./-]+"\s*(as\s+\w+)?\s*;?\s*$')
FORBIDDEN = [
    (re.compile(r"XMLHttpRequest"), "network/file access via XMLHttpRequest"),
    (re.compile(r"Qt\s*\.\s*(openUrlExternally|createQmlObject|include|createComponent)"), "dynamic code or external URLs"),
    (re.compile(r"\b(file|https?|qrc|data|ftp|image)\s*:\s*/"), "URLs outside the widget"),
    (re.compile(r"""["']/[\w.-]+(/[\w.-]*)*["']"""), "absolute paths"),
    (re.compile(r"""["'][^"'\n]*\.\./"""), "paths outside the widget"),
    (re.compile(r"\bQuickshell\b"), "Quickshell APIs"),
    (re.compile(r"\beval\s*\(|\bFunction\s*\("), "eval"),
]


def builtin_dir() -> str:
    here = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    return os.path.join(here, "config", "quickshell", "aether-shell", "widgets")


def user_dir() -> str:
    base = os.environ.get("XDG_DATA_HOME") or os.path.join(os.environ.get("HOME", ""), ".local", "share")
    return os.path.join(base, "aether-shell", "widgets")


def _strip_comments(text: str) -> str:
    """Remove // and /* */ comments but never touch string literals — a
    naive regex would also eat "file:///…" inside a string and hide it
    from the checks below."""
    out, i, n = [], 0, len(text)
    quote = None
    while i < n:
        c = text[i]
        if quote:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == quote:
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


def scan(directory: str) -> List[str]:
    """Static capability check of a widget directory. Returns problems."""
    problems: List[str] = []
    files, total = 0, 0
    for root, dirs, names in os.walk(directory, followlinks=False):
        for d in dirs:
            if os.path.islink(os.path.join(root, d)):
                problems.append("%s: symlinks are not allowed" % d)
        for n in names:
            full = os.path.join(root, n)
            rel = os.path.relpath(full, directory)
            if os.path.islink(full):
                problems.append("%s: symlinks are not allowed" % rel)
                continue
            files += 1
            size = os.path.getsize(full)
            total += size
            if size > MAX_FILE:
                problems.append("%s: larger than %d KiB" % (rel, MAX_FILE // 1024))
            ext = os.path.splitext(n)[1].lower()
            if ext not in ALLOWED_EXT:
                problems.append("%s: file type %s is not allowed" % (rel, ext or "(none)"))
                continue
            if os.access(full, os.X_OK) and ext not in (".svg", ".png", ".jpg", ".webp"):
                pass  # executable bit is harmless for QML; never executed
            if ext in (".qml", ".js"):
                with open(full, encoding="utf-8", errors="replace") as fh:
                    code = _strip_comments(fh.read())
                for line in code.splitlines():
                    if re.match(r"^\s*import\b", line) and not (ALLOWED_IMPORT.match(line) or LOCAL_IMPORT.match(line)):
                        problems.append("%s: import not allowed: %s" % (rel, line.strip()))
                    if ext == ".js" and re.match(r"^\s*\.import\b", line):
                        problems.append("%s: .import not allowed" % rel)
                for pat, why in FORBIDDEN:
                    if pat.search(code):
                        problems.append("%s: %s" % (rel, why))
    if files > MAX_FILES:
        problems.append("more than %d files" % MAX_FILES)
    if total > MAX_TOTAL:
        problems.append("larger than %d MiB in total" % (MAX_TOTAL >> 20))
    return sorted(set(problems))


def read_manifest(directory: str) -> Tuple[Optional[Dict[str, Any]], List[str]]:
    path = os.path.join(directory, "widget.json")
    try:
        with open(path, encoding="utf-8") as fh:
            m = json.load(fh)
    except (OSError, ValueError) as exc:
        return None, ["widget.json: %s" % exc]
    problems = []
    if not isinstance(m, dict):
        return None, ["widget.json must be an object"]
    extra = set(m) - {"aetherWidget", "id", "name", "version", "api", "entry", "description", "author", "license",
                      "size", "permissions", "requires", "settings"}
    if extra:
        problems.append("widget.json: unexpected field(s) %s" % ", ".join(sorted(extra)))
    if m.get("aetherWidget") != 1:
        problems.append("widget.json: aetherWidget must be 1")
    if not isinstance(m.get("id"), str) or not ID_RE.match(m["id"]):
        problems.append("id must be lowercase letters, digits, '.' or '-'")
    if not isinstance(m.get("name"), str) or not 1 <= len(m["name"]) <= 60:
        problems.append("name must be 1-60 characters")
    if not isinstance(m.get("version"), str) or not SEMVER.match(m["version"]):
        problems.append("version must be MAJOR.MINOR.PATCH")
    if not isinstance(m.get("api"), int) or m["api"] > API_VERSION or m["api"] < 1:
        problems.append("api %r is not supported (this AetherOS supports widget API %d)" % (m.get("api"), API_VERSION))
    entry = m.get("entry", "Widget.qml")
    if not isinstance(entry, str) or not re.match(r"^[\w-]+\.qml$", entry) or not os.path.isfile(os.path.join(directory, entry)):
        problems.append("entry must name a .qml file in the widget directory")
    perms = m.get("permissions", [])
    if not isinstance(perms, list) or any(p not in PERMISSIONS for p in perms):
        problems.append("permissions must be from: %s" % ", ".join(sorted(PERMISSIONS)))
    size = m.get("size", {})
    if not isinstance(size, dict) or not all(isinstance(size.get(k, 200), int) and 40 <= size.get(k, 200) <= 2048 for k in ("w", "h")):
        problems.append("size.w/size.h must be 40-2048")
    req = m.get("requires", [])
    if not isinstance(req, list) or not all(isinstance(r, str) and re.match(r"^[\w.+-]{1,64}$", r) for r in req):
        problems.append("requires must be a list of command names")
    if problems:
        return None, problems
    m.setdefault("entry", "Widget.qml")
    m.setdefault("permissions", [])
    m.setdefault("requires", [])
    m.setdefault("size", {"w": 240, "h": 160})
    return m, []


def inspect(directory: str) -> Dict[str, Any]:
    manifest, problems = read_manifest(directory)
    problems += scan(directory)
    missing = [r for r in (manifest or {}).get("requires", []) if shutil.which(r) is None]
    return {"ok": manifest is not None and not problems, "manifest": manifest, "problems": problems,
            "missingRequirements": missing, "path": directory}


def listing() -> List[Dict[str, Any]]:
    out = []
    for source, base in (("builtin", builtin_dir()), ("user", user_dir())):
        try:
            names = sorted(os.listdir(base))
        except OSError:
            continue
        for n in names:
            d = os.path.join(base, n)
            if not os.path.isdir(d) or os.path.islink(d):
                continue
            info = inspect(d)
            m = info["manifest"] or {}
            out.append({"id": m.get("id", n), "name": m.get("name", n), "version": m.get("version"), "source": source,
                        "permissions": m.get("permissions", []), "size": m.get("size"), "entry": m.get("entry"),
                        "description": m.get("description", ""), "valid": info["ok"], "problems": info["problems"],
                        "missingRequirements": info["missingRequirements"], "path": d})
    return out


def install(src: str, force: bool = False) -> Dict[str, Any]:
    tmp = None
    try:
        if os.path.isfile(src) and zipfile.is_zipfile(src):
            tmp = tempfile.mkdtemp(prefix="aether-widget-")
            with zipfile.ZipFile(src) as zf:
                if len(zf.infolist()) > MAX_FILES * 2:
                    return {"ok": False, "problems": ["archive has too many entries"]}
                for info in zf.infolist():
                    name = info.filename
                    if name.startswith("/") or ".." in name.split("/") or (info.external_attr >> 16) & 0o170000 == 0o120000:
                        return {"ok": False, "problems": ["unsafe path in archive: %s" % name]}
                    if info.file_size > MAX_FILE:
                        return {"ok": False, "problems": ["%s is too large" % name]}
                zf.extractall(tmp)
            entries = [e for e in os.listdir(tmp) if not e.startswith(".")]
            src_dir = os.path.join(tmp, entries[0]) if len(entries) == 1 and os.path.isdir(os.path.join(tmp, entries[0])) else tmp
        elif os.path.isdir(src):
            src_dir = src
        else:
            return {"ok": False, "problems": ["%s is neither a widget directory nor a .zip" % src]}
        info = inspect(src_dir)
        if not info["ok"]:
            return {"ok": False, "problems": info["problems"]}
        wid = info["manifest"]["id"]
        if any(w["id"] == wid and w["source"] == "builtin" for w in listing()):
            return {"ok": False, "problems": ["%s is a built-in widget id" % wid]}
        dest = os.path.join(user_dir(), wid)
        if os.path.exists(dest):
            if not force:
                return {"ok": False, "problems": ["%s is already installed (use --force to replace)" % wid]}
            shutil.rmtree(dest)
        os.makedirs(user_dir(), exist_ok=True)
        shutil.copytree(src_dir, dest, symlinks=False)
        return {"ok": True, "id": wid, "path": dest, "permissions": info["manifest"]["permissions"],
                "missingRequirements": info["missingRequirements"]}
    finally:
        if tmp:
            shutil.rmtree(tmp, ignore_errors=True)


def remove(widget_id: str) -> Dict[str, Any]:
    if not ID_RE.match(widget_id or ""):
        return {"ok": False, "problems": ["bad widget id"]}
    dest = os.path.join(user_dir(), widget_id)
    if not os.path.isdir(dest) or os.path.islink(dest):
        return {"ok": False, "problems": ["no user-installed widget %s (built-in widgets can't be removed)" % widget_id]}
    shutil.rmtree(dest)
    return {"ok": True}
