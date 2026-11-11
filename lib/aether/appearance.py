"""Icon and cursor themes: detect what is installed, apply a choice.

Detection reads the XDG icon directories (a theme is a directory with an
index.theme; a cursor theme is one with a cursors/ subdirectory) — nothing
is assumed to be installed. Applying sets:
  * GTK / libadwaita:   gsettings org.gnome.desktop.interface icon-theme / cursor-theme / cursor-size
  * Qt (qt6ct):         icon_theme in ~/.config/qt6ct/qt6ct.conf ([Appearance]), edited in place
  * Hyprland cursor:    `hyprctl setcursor` now, and env lines in cursor.conf for the next login
Nothing is downloaded or installed here; theme packages come from dnf.
"""

from __future__ import annotations

import configparser
import os
import re
import time
from typing import Any, Dict, List, Optional

from .util import Context, config_dir

NAME_RE = re.compile(r"^[\w .+-]{1,80}$")


def _dirs() -> List[str]:
    home = os.environ.get("HOME", "")
    data_home = os.environ.get("XDG_DATA_HOME") or os.path.join(home, ".local", "share")
    dirs = [os.path.join(home, ".icons"), os.path.join(data_home, "icons")]
    for d in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":"):
        if d:
            dirs.append(os.path.join(d, "icons"))
    seen, out = set(), []
    for d in dirs:
        if d not in seen:
            seen.add(d)
            out.append(d)
    return out


def _theme_name(path: str) -> str:
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        cp.read(os.path.join(path, "index.theme"), encoding="utf-8")
        return cp.get("Icon Theme", "Name", fallback=os.path.basename(path))
    except (configparser.Error, OSError, UnicodeDecodeError):
        return os.path.basename(path)


def themes(ctx: Context) -> Dict[str, List[Dict[str, str]]]:
    icons: Dict[str, Dict[str, str]] = {}
    cursors: Dict[str, Dict[str, str]] = {}
    for base in _dirs():
        try:
            entries = sorted(os.listdir(base))
        except OSError:
            continue
        for e in entries:
            full = os.path.join(base, e)
            if not os.path.isdir(full) or not NAME_RE.match(e):
                continue
            if os.path.isdir(os.path.join(full, "cursors")) and e not in cursors:
                cursors[e] = {"id": e, "name": _theme_name(full), "path": full}
            if os.path.isfile(os.path.join(full, "index.theme")) and e not in icons:
                # Cursor-only themes also carry an index.theme; an icon theme
                # has at least one size/context directory besides cursors/.
                subdirs = [d for d in os.listdir(full) if os.path.isdir(os.path.join(full, d)) and d != "cursors"]
                if subdirs and e not in ("default", "hicolor", "locolor"):
                    icons[e] = {"id": e, "name": _theme_name(full), "path": full}
    return {"icons": list(icons.values()), "cursors": list(cursors.values()), "current": current(ctx)}


def current(ctx: Context) -> Dict[str, Optional[str]]:
    out: Dict[str, Optional[str]] = {"icons": None, "cursor": None, "cursorSize": None}
    if ctx.which("gsettings"):
        for key, name in (("icons", "icon-theme"), ("cursor", "cursor-theme"), ("cursorSize", "cursor-size")):
            r = ctx.run(["gsettings", "get", "org.gnome.desktop.interface", name], timeout=5)
            if r.ok:
                out[key] = r.out.strip().strip("'")
    return out


def _qt6ct_set(key: str, value: str) -> Optional[str]:
    path = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.environ.get("HOME", ""), ".config"), "qt6ct", "qt6ct.conf")
    lines: List[str] = []
    try:
        with open(path, "r", encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError:
        pass
    out, in_app, done = [], False, False
    for line in lines:
        if line.startswith("["):
            if in_app and not done:
                out.append("%s=%s" % (key, value))
                done = True
            in_app = line.strip() == "[Appearance]"
        elif in_app and line.split("=", 1)[0].strip() == key:
            if not done:
                out.append("%s=%s" % (key, value))
                done = True
            continue
        out.append(line)
    if not done:
        if not in_app:
            out.append("[Appearance]")
        out.append("%s=%s" % (key, value))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(out) + "\n")
    os.replace(tmp, path)
    return path


def set_icons(ctx: Context, theme_id: str) -> Dict[str, Any]:
    known = {t["id"] for t in themes(ctx)["icons"]}
    if theme_id not in known:
        return {"ok": False, "error": "icon theme %r is not installed (installed: %s)" % (theme_id, ", ".join(sorted(known)) or "none")}
    done = []
    if ctx.which("gsettings") and ctx.run(["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", theme_id], timeout=5).ok:
        done.append("GTK")
    if _qt6ct_set("icon_theme", theme_id):
        done.append("Qt (qt6ct)")
    return {"ok": True, "applied": done, "note": "Restart the shell (aether shell-reload) and open apps to see the new icons."}


def set_cursor(ctx: Context, theme_id: str, size: int) -> Dict[str, Any]:
    known = {t["id"] for t in themes(ctx)["cursors"]}
    if theme_id not in known:
        return {"ok": False, "error": "cursor theme %r is not installed (installed: %s)" % (theme_id, ", ".join(sorted(known)) or "none")}
    if not (16 <= size <= 96):
        return {"ok": False, "error": "cursor size must be 16-96"}
    done = []
    if ctx.which("gsettings"):
        ok1 = ctx.run(["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", theme_id], timeout=5).ok
        ok2 = ctx.run(["gsettings", "set", "org.gnome.desktop.interface", "cursor-size", str(size)], timeout=5).ok
        if ok1 and ok2:
            done.append("GTK")
    if ctx.env.get("HYPRLAND_INSTANCE_SIGNATURE") and ctx.which("hyprctl"):
        if ctx.run(["hyprctl", "setcursor", theme_id, str(size)], timeout=5).ok:
            done.append("Hyprland (now)")
    # Persist for the next login: sourced by hyprland.conf after env.conf.
    path = os.path.join(config_dir(), "hypr", "cursor.conf")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("# Generated by `aether theme cursor` on %s.\n" % time.strftime("%Y-%m-%d %H:%M"))
        for var in ("XCURSOR_THEME", "HYPRCURSOR_THEME"):
            fh.write("env = %s,%s\n" % (var, theme_id))
        for var in ("XCURSOR_SIZE", "HYPRCURSOR_SIZE"):
            fh.write("env = %s,%d\n" % (var, size))
    done.append("next login (cursor.conf)")
    return {"ok": True, "applied": done}
