"""Desktop entries (freedesktop Desktop Entry Specification), parsed the way
the shell's launcher does — used by session restore, autostart and the AI
assistant's "launch app" action to resolve an app *id* to a command."""

from __future__ import annotations

import configparser
import os
import re
import shlex
from typing import Dict, List, Optional

ID_RE = re.compile(r"^[\w.+-]{1,200}\.desktop$")


def data_dirs() -> List[str]:
    home = os.environ.get("HOME", "")
    first = os.environ.get("XDG_DATA_HOME") or os.path.join(home, ".local", "share")
    rest = (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    flatpak = [os.path.join(home, ".local/share/flatpak/exports/share"), "/var/lib/flatpak/exports/share"]
    out, seen = [], set()
    for d in [first] + flatpak + rest:
        if d and d not in seen:
            seen.add(d)
            out.append(d)
    return out


def parse(path: str) -> Optional[Dict[str, object]]:
    cp = configparser.RawConfigParser(strict=False, interpolation=None, delimiters=("=",))
    cp.optionxform = str  # keys are case-sensitive
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            cp.read_file(fh)
    except (OSError, configparser.Error):
        return None
    if not cp.has_section("Desktop Entry"):
        return None
    e = dict(cp.items("Desktop Entry"))
    if e.get("Type", "Application") != "Application":
        return None
    return {
        "id": os.path.basename(path), "path": path, "name": e.get("Name", os.path.basename(path)),
        "exec": e.get("Exec", ""), "icon": e.get("Icon", ""), "terminal": e.get("Terminal", "false").lower() == "true",
        "wmClass": e.get("StartupWMClass", ""), "noDisplay": e.get("NoDisplay", "false").lower() == "true",
        "hidden": e.get("Hidden", "false").lower() == "true", "tryExec": e.get("TryExec", ""),
        "onlyShowIn": [x for x in e.get("OnlyShowIn", "").split(";") if x],
        "notShowIn": [x for x in e.get("NotShowIn", "").split(";") if x],
        "autostartEnabled": e.get("X-GNOME-Autostart-enabled", "true").lower() != "false",
    }


def all_apps() -> Dict[str, Dict[str, object]]:
    """id -> entry; earlier data dirs win (user overrides system), per spec."""
    out: Dict[str, Dict[str, object]] = {}
    for d in data_dirs():
        apps_dir = os.path.join(d, "applications")
        for root, _dirs, files in os.walk(apps_dir):
            for f in files:
                if not f.endswith(".desktop"):
                    continue
                rel = os.path.relpath(os.path.join(root, f), apps_dir).replace(os.sep, "-")
                if rel in out:
                    continue
                e = parse(os.path.join(root, f))
                if e is not None:
                    e["id"] = rel
                    out[rel] = e
    return out


def argv(entry: Dict[str, object]) -> List[str]:
    """Exec line → argv: quoting per the spec, field codes (%f %U …) removed,
    %% unescaped. Raises ValueError on an unparsable line."""
    raw = str(entry.get("exec", ""))
    try:
        parts = shlex.split(raw, posix=True)
    except ValueError as exc:
        raise ValueError("unparsable Exec line in %s: %s" % (entry.get("id"), exc))
    out = []
    for p in parts:
        if re.fullmatch(r"%[fFuUdDnNickvm]", p):
            continue
        out.append(re.sub(r"%[fFuUdDnNickvm]", "", p).replace("%%", "%"))
    if not out:
        raise ValueError("empty Exec line in %s" % entry.get("id"))
    return out


def for_class(cls: str, apps: Optional[Dict[str, Dict[str, object]]] = None) -> Optional[Dict[str, object]]:
    """The entry a window class belongs to (same rules as the shell's
    ApplicationService.forClass)."""
    apps = apps if apps is not None else all_apps()
    c = (cls or "").lower()
    if not c:
        return None
    for test in (lambda a: str(a["wmClass"]).lower() == c,
                 lambda a: str(a["id"]).lower() == c + ".desktop",
                 lambda a: str(a["id"]).lower()[:-8].split(".")[-1] == c.split(".")[-1],
                 lambda a: str(a["name"]).lower() == c):
        for a in apps.values():
            if test(a):
                return a
    return None
