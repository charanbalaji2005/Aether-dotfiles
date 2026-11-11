"""User colour themes: create from a built-in palette with overrides, list,
export, import, delete.

A theme file (~/.config/aether-shell/themes/<id>.json) is a complete palette
— every token, all #RRGGBB — so it renders identically everywhere (shell,
terminals, Hyprland borders). Imports are validated token by token; unknown
fields reject the file. Ids can't shadow built-in palettes.
"""

from __future__ import annotations

import json
import os
import re
from typing import Any, Dict, List, Optional, Tuple

from . import palettes
from .util import config_dir

ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{1,39}$")
HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")
FIELDS = set(palettes.TOKENS) | {"label", "dark", "ansi", "aetherTheme", "base"}


def themes_dir() -> str:
    return os.path.join(config_dir(), "themes")


def validate(theme_id: str, data: Any) -> Tuple[Optional[Dict[str, Any]], List[str]]:
    problems: List[str] = []
    if not ID_RE.match(theme_id or ""):
        problems.append("theme ids are 2-40 lowercase letters, digits and '-'")
    elif theme_id in palettes.builtin_ids():
        problems.append("%r is a built-in palette name" % theme_id)
    if not isinstance(data, dict):
        return None, problems + ["a theme must be a JSON object"]
    extra = set(data) - FIELDS
    if extra:
        problems.append("unexpected field(s): %s" % ", ".join(sorted(extra)))
    out: Dict[str, Any] = {}
    label = data.get("label", theme_id)
    if not isinstance(label, str) or not 1 <= len(label) <= 40:
        problems.append("label must be 1-40 characters")
    out["label"] = label
    if not isinstance(data.get("dark"), bool):
        problems.append("dark must be true or false")
    out["dark"] = data.get("dark") is True
    for tok in palettes.TOKENS:
        v = data.get(tok)
        if not isinstance(v, str) or not HEX.match(v):
            problems.append("%s must be #RRGGBB" % tok)
        else:
            out[tok] = v.upper()
    ansi = data.get("ansi")
    if not isinstance(ansi, list) or len(ansi) != 16 or not all(isinstance(c, str) and HEX.match(c) for c in ansi):
        problems.append("ansi must be 16 #RRGGBB colours")
    else:
        out["ansi"] = [c.upper() for c in ansi]
    return (out if not problems else None), problems


def listing() -> Dict[str, Dict[str, Any]]:
    out: Dict[str, Dict[str, Any]] = {}
    try:
        files = sorted(os.listdir(themes_dir()))
    except OSError:
        return out
    for f in files:
        if not f.endswith(".json"):
            continue
        tid = f[:-5]
        try:
            with open(os.path.join(themes_dir(), f), encoding="utf-8") as fh:
                theme, problems = validate(tid, json.load(fh))
        except (OSError, ValueError):
            continue
        if theme is not None:
            out[tid] = theme
    return out


def _write(theme_id: str, theme: Dict[str, Any]) -> str:
    os.makedirs(themes_dir(), exist_ok=True)
    path = os.path.join(themes_dir(), theme_id + ".json")
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(dict(theme, aetherTheme=1), fh, indent=2)
        fh.write("\n")
    os.replace(tmp, path)
    return path


def create(theme_id: str, base: str, overrides: Dict[str, str], label: str = "", dark: Optional[bool] = None) -> Dict[str, Any]:
    table = palettes.load(include_user=True)
    if base not in table:
        return {"ok": False, "problems": ["unknown base palette %r" % base]}
    data = dict(table[base])
    data.update(overrides)
    data["label"] = label or theme_id
    if dark is not None:
        data["dark"] = dark
    theme, problems = validate(theme_id, data)
    if theme is None:
        return {"ok": False, "problems": problems}
    return {"ok": True, "path": _write(theme_id, theme)}


def import_file(src: str, theme_id: str) -> Dict[str, Any]:
    try:
        if os.path.getsize(src) > 64 * 1024:
            return {"ok": False, "problems": ["file too large for a theme"]}
        with open(src, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        return {"ok": False, "problems": [str(exc)]}
    theme, problems = validate(theme_id, data)
    if theme is None:
        return {"ok": False, "problems": problems}
    return {"ok": True, "path": _write(theme_id, theme)}


def export(theme_id: str, dest: str) -> Dict[str, Any]:
    table = palettes.load(include_user=True)
    if theme_id not in table:
        return {"ok": False, "problems": ["unknown palette %r" % theme_id]}
    with open(dest, "w", encoding="utf-8") as fh:
        json.dump(dict(table[theme_id], aetherTheme=1), fh, indent=2)
        fh.write("\n")
    return {"ok": True, "path": dest}


def delete(theme_id: str) -> Dict[str, Any]:
    if not ID_RE.match(theme_id or ""):
        return {"ok": False, "problems": ["bad theme id"]}
    path = os.path.join(themes_dir(), theme_id + ".json")
    if not os.path.isfile(path):
        return {"ok": False, "problems": ["no user theme %r" % theme_id]}
    os.remove(path)
    return {"ok": True}
