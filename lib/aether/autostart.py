"""Startup applications: XDG autostart entries (~/.config/autostart and
/etc/xdg/autostart), managed the standard way so GNOME, KDE and AetherOS
agree on what starts:
  * disable a system entry → a user override with Hidden=true
  * enable it again        → remove that override
  * add an app             → copy its desktop entry into ~/.config/autostart
In a Hyprland session the entries are started by systemd's XDG autostart
generator (`aether autostart run`, from hyprland.conf).
"""

from __future__ import annotations

import os
import re
import shutil
from typing import Any, Dict, List

from . import apps
from .util import Context

ID_RE = re.compile(r"^[\w.+-]{1,200}\.desktop$")
DESKTOP = "Hyprland"


def user_dir() -> str:
    return os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.environ.get("HOME", ""), ".config"), "autostart")


def system_dirs() -> List[str]:
    return [os.path.join(d, "autostart") for d in (os.environ.get("XDG_CONFIG_DIRS") or "/etc/xdg").split(":") if d]


def entries() -> List[Dict[str, Any]]:
    seen: Dict[str, Dict[str, Any]] = {}
    for source, d in [("user", user_dir())] + [("system", s) for s in system_dirs()]:
        try:
            files = sorted(os.listdir(d))
        except OSError:
            continue
        for f in files:
            if not f.endswith(".desktop") or f in seen:
                continue
            e = apps.parse(os.path.join(d, f))
            if e is None:
                continue
            shadowed = source == "user" and any(os.path.exists(os.path.join(s, f)) for s in system_dirs())
            applies = (not e["onlyShowIn"] or DESKTOP in e["onlyShowIn"]) and DESKTOP not in e["notShowIn"]
            seen[f] = {"id": f, "name": e["name"], "exec": e["exec"], "source": "override" if shadowed else source,
                       "enabled": not e["hidden"] and bool(e["autostartEnabled"]), "appliesHere": applies}
    return sorted(seen.values(), key=lambda x: x["name"].lower())


def _set_hidden(entry_id: str, hidden: bool) -> Dict[str, Any]:
    if not ID_RE.match(entry_id):
        return {"ok": False, "error": "bad entry id"}
    user_path = os.path.join(user_dir(), entry_id)
    system_path = next((os.path.join(s, entry_id) for s in system_dirs() if os.path.exists(os.path.join(s, entry_id))), None)
    if not hidden and system_path and os.path.exists(user_path):
        e = apps.parse(user_path)
        if e is not None and e["hidden"]:
            os.remove(user_path)  # only our own Hidden=true override
            return {"ok": True, "enabled": True}
    src = user_path if os.path.exists(user_path) else system_path
    if src is None:
        return {"ok": False, "error": "no autostart entry %s" % entry_id}
    with open(src, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().splitlines()
    out, in_entry, done = [], False, False
    for line in lines:
        if line.startswith("["):
            if in_entry and not done:
                out.append("Hidden=%s" % ("true" if hidden else "false"))
                done = True
            in_entry = line.strip() == "[Desktop Entry]"
        elif in_entry and line.split("=", 1)[0].strip() in ("Hidden", "X-GNOME-Autostart-enabled"):
            continue
        out.append(line)
    if not done:
        out.append("Hidden=%s" % ("true" if hidden else "false"))
    os.makedirs(user_dir(), exist_ok=True)
    tmp = user_path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(out) + "\n")
    os.replace(tmp, user_path)
    return {"ok": True, "enabled": not hidden}


def disable(entry_id: str) -> Dict[str, Any]:
    return _set_hidden(entry_id, True)


def enable(entry_id: str) -> Dict[str, Any]:
    return _set_hidden(entry_id, False)


def add(app_id: str) -> Dict[str, Any]:
    if not ID_RE.match(app_id):
        return {"ok": False, "error": "bad application id"}
    entry = apps.all_apps().get(app_id)
    if entry is None:
        return {"ok": False, "error": "no installed application %s" % app_id}
    os.makedirs(user_dir(), exist_ok=True)
    dest = os.path.join(user_dir(), app_id)
    if os.path.exists(dest):
        return {"ok": False, "error": "%s is already a startup application" % app_id}
    shutil.copyfile(str(entry["path"]), dest)
    return {"ok": True, "path": dest}


def remove(entry_id: str) -> Dict[str, Any]:
    """Delete a user-created entry (never a system file)."""
    if not ID_RE.match(entry_id):
        return {"ok": False, "error": "bad entry id"}
    path = os.path.join(user_dir(), entry_id)
    if any(os.path.exists(os.path.join(s, entry_id)) for s in system_dirs()):
        return {"ok": False, "error": "%s comes with the system: disable it instead" % entry_id}
    if not os.path.isfile(path):
        return {"ok": False, "error": "no user entry %s" % entry_id}
    os.remove(path)
    return {"ok": True}


def run(ctx: Context, enabled: bool) -> Dict[str, Any]:
    """Start XDG autostart entries for this session via systemd (respects
    Hidden, OnlyShowIn/NotShowIn through the generator's ExecCondition)."""
    if not enabled:
        return {"ok": True, "started": False, "reason": "disabled in Settings → Startup applications"}
    if not ctx.which("systemctl"):
        return {"ok": False, "error": "systemctl not found"}
    ctx.run(["systemctl", "--user", "daemon-reload"], timeout=20)
    res = ctx.run(["systemctl", "--user", "start", "xdg-desktop-autostart.target"], timeout=30)
    return {"ok": res.ok, "started": res.ok, "error": None if res.ok else (res.err or "").strip()}
