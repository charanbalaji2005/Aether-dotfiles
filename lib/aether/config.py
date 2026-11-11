"""config.json: schema validation, migrations, import/export.

The schema itself is generated from the shell's Config.qml (see
tools/gen_schema.py); this module adds the constraints QML can't express
(numeric ranges, a few enums) and everything that must be safe to run on a
file the user — or someone they got a profile from — edited by hand:

* ``validate``   never raises on bad input; it reports and repairs.
* ``migrate``    upgrades older files step by step, keeping a backup.
* ``import``     accepts *only* known keys with valid values. Nothing in a
                 config file is ever executed: there is no key whose value
                 is a command line.
"""

from __future__ import annotations

import copy
import json
import os
import re
import shutil
import time
from typing import Any, Callable, Dict, List, Optional, Tuple

from ._schema_data import SCHEMA
from .util import config_dir

SCHEMA_VERSION = 4

# Constraints that Config.qml only states in comments.
RANGES: Dict[Tuple[str, str], Tuple[float, float]] = {
    ("bar", "height"): (28, 64),
    ("appearance", "autoLightFrom"): (0, 23),
    ("appearance", "autoDarkFrom"): (0, 23),
    ("appearance", "barOpacity"): (0.0, 1.0),
    ("appearance", "panelOpacity"): (0.2, 1.0),
    ("appearance", "wallpaperDim"): (0.0, 0.9),
    ("appearance", "wallpaperBlur"): (0.0, 1.0),
    ("appearance", "cornerScale"): (0.0, 1.5),
    ("general", "animationSpeed"): (0.5, 2.0),
    ("notifications", "timeoutLow"): (1000, 60000),
    ("notifications", "timeoutNormal"): (1000, 120000),
    ("notifications", "maxVisible"): (1, 8),
    ("launcher", "recentLimit"): (1, 30),
    ("performance", "telemetryInterval"): (500, 30000),
    ("nightLight", "temperature"): (1000, 6500),
    ("wallpaper", "transitionDuration"): (0, 5000),
    ("wallpaper", "parallaxStrength"): (0.0, 1.0),
    ("wallpaper", "ambientDensity"): (0.0, 1.0),
    ("wallpaper", "intervalMinutes"): (1, 1440),
    ("dock", "iconSize"): (28, 72),
    ("dock", "magnification"): (1.0, 2.0),
    ("dock", "opacity"): (0.0, 1.0),
    ("battery", "lowThreshold"): (5, 50),
    ("battery", "criticalThreshold"): (2, 25),
    ("lock", "idleLockMinutes"): (0, 240),
    ("lock", "idleDisplayOffMinutes"): (0, 240),
    ("lock", "idleSuspendMinutes"): (0, 480),
    ("gestures", "edgeDwellMs"): (0, 2000),
    ("accessibility", "uiScale"): (0.85, 1.5),
    ("terminal", "opacity"): (0.3, 1.0),
    ("terminal", "fontSize"): (6.0, 32.0),
    ("terminal", "padding"): (0, 48),
    ("effects", "vramThreshold"): (0.5, 0.99),
    ("effects", "gpuThreshold"): (0.5, 0.99),
    ("island", "eventSeconds"): (2, 30),
    ("input", "repeatRate"): (5, 100),
    ("input", "repeatDelay"): (150, 1000),
    ("input", "sensitivity"): (-1.0, 1.0),
    ("input", "scrollFactor"): (0.2, 5.0),
    ("launcher", "historyLimit"): (0, 100),
    ("widgets", "grid"): (4, 64),
    ("power", "autoSaverThreshold"): (5, 50),
    ("power", "dimAfterMinutes"): (0, 120),
    ("privacy", "clipboardRetentionHours"): (0, 720),
}

EXTRA_CHOICES: Dict[Tuple[str, str], Tuple[str, ...]] = {
    ("bar", "style"): ("full", "floating", "dock"),
    ("appearance", "compositorBlur"): ("profile", "on", "off"),
}

WORKSPACE_MAPS = {("workspaces", "names"), ("workspaces", "icons"), ("wallpaper", "perWorkspace")}
APP_ID_RE = re.compile(r"^[\w.+-]{1,128}$")


def _check_objects(where, value, fields, limit=64):
    """Validate a list of small objects: fields = {name: (validator, required)}."""
    if not isinstance(value, list):
        return [], "%s: expected a list" % where
    good, problems = [], []
    for item in value[:limit]:
        if not isinstance(item, dict) or set(item) - set(fields):
            problems.append("%s: entry %r has unknown fields" % (where, item))
            continue
        ok = True
        for name, (check, required) in fields.items():
            if name not in item:
                if required:
                    ok = False
                continue
            if not check(item[name]):
                ok = False
        if ok:
            good.append(item)
        else:
            problems.append("%s: invalid entry %r" % (where, item))
    if len(value) > limit:
        problems.append("%s: more than %d entries" % (where, limit))
    return good, ("; ".join(problems) if problems else None)


def _is_ws(v):
    return isinstance(v, int) and not isinstance(v, bool) and 1 <= v <= 99


STRUCTURED_LISTS = {
    ("notifications", "appRules"): lambda w, v: _check_objects(w, v, {
        "app": (lambda x: isinstance(x, str) and bool(APP_ID_RE.match(x)), True),
        "mode": (lambda x: x in ("normal", "priority", "mute"), True),
        "sound": (lambda x: isinstance(x, bool), False)}),
    ("workspaces", "appRules"): lambda w, v: _check_objects(w, v, {
        "app": (lambda x: isinstance(x, str) and bool(APP_ID_RE.match(x)), True),
        "workspace": (_is_ws, True),
        "silent": (lambda x: isinstance(x, bool), False)}),
    ("widgets", "placed"): lambda w, v: _check_objects(w, v, {
        "id": (lambda x: isinstance(x, str) and bool(re.match(r"^[a-z0-9-]{1,40}$", x)), True),
        "widget": (lambda x: isinstance(x, str) and bool(re.match(r"^[a-z0-9][a-z0-9.-]{0,63}$", x)), True),
        "screen": (lambda x: isinstance(x, str) and len(x) <= 64, False),
        "x": (lambda x: isinstance(x, (int, float)) and not isinstance(x, bool) and 0 <= x <= 16384, True),
        "y": (lambda x: isinstance(x, (int, float)) and not isinstance(x, bool) and 0 <= x <= 16384, True),
        "w": (lambda x: isinstance(x, (int, float)) and not isinstance(x, bool) and 40 <= x <= 4096, False),
        "h": (lambda x: isinstance(x, (int, float)) and not isinstance(x, bool) and 40 <= x <= 4096, False)}),
    ("widgets", "trusted"): lambda w, v: _check_objects(w, v, {
        "id": (lambda x: isinstance(x, str) and bool(re.match(r"^[a-z0-9][a-z0-9.-]{0,63}$", x)), True),
        "digest": (lambda x: isinstance(x, str) and bool(re.match(r"^[0-9a-f]{64}$", x)), True)}),
    ("launcher", "history"): lambda w, v: (([q for q in v if isinstance(q, str) and 0 < len(q) <= 200][:100], None)
                                           if isinstance(v, list) else ([], "%s: expected a list" % w)),
    ("privacy", "clipboardExcludeApps"): lambda w, v: (([a for a in v if isinstance(a, str) and APP_ID_RE.match(a)][:64], None)
                                                      if isinstance(v, list) else ([], "%s: expected a list" % w)),
}

# Action ids a gesture/edge/automation may trigger. Mirrors
# services/ActionService.qml (tests assert the two lists match).
ACTIONS = (
    "none", "launcher", "controlcenter", "dashboard", "notifications", "overview", "clipboard",
    "settings", "powermenu", "lock", "dock", "wallpaper-next", "systemcenter", "assistant", "layouts",
)
ACTION_KEYS = {("gestures", k) for k in ("edgeLeft", "edgeRight", "edgeTop", "edgeBottom", "swipeUp", "swipeDown")}

COLOR_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")
COLOR_KEYS = {("appearance", "accent")}
OPTIONAL_COLOR_KEYS = {("battery", k) for k in ("colorCharging", "colorNormal", "colorLow", "colorCritical")}
MAX_STR = 4096


def config_file() -> str:
    return os.path.join(config_dir(), "config.json")


def defaults() -> Dict[str, Dict[str, Any]]:
    out = {s: {k: copy.deepcopy(spec["default"]) for k, spec in fields.items()} for s, fields in SCHEMA.items()}
    out["meta"]["schemaVersion"] = SCHEMA_VERSION
    return out


def choices_for(section: str, key: str) -> Optional[Tuple[str, ...]]:
    spec = SCHEMA[section][key]
    if "choices" in spec:
        return tuple(spec["choices"])
    if (section, key) in EXTRA_CHOICES:
        return EXTRA_CHOICES[(section, key)]
    if (section, key) in ACTION_KEYS:
        return ACTIONS
    return None


def _check_value(section: str, key: str, value: Any) -> Tuple[Any, Optional[str]]:
    """Return (usable value, problem). The value is the default when unusable."""
    spec = SCHEMA[section][key]
    kind, default = spec["type"], copy.deepcopy(spec["default"])
    where = "%s.%s" % (section, key)

    if kind == "bool":
        if isinstance(value, bool):
            return value, None
        return default, "%s: expected true/false, got %r" % (where, value)
    if kind in ("int", "real"):
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return default, "%s: expected a number, got %r" % (where, value)
        if value != value or value in (float("inf"), float("-inf")):
            return default, "%s: not a finite number" % where
        if kind == "int":
            if isinstance(value, float) and not value.is_integer():
                return default, "%s: expected a whole number, got %r" % (where, value)
            value = int(value)
        lo_hi = RANGES.get((section, key))
        if lo_hi and not (lo_hi[0] <= value <= lo_hi[1]):
            clamped = min(max(value, lo_hi[0]), lo_hi[1])
            clamped = int(clamped) if kind == "int" else float(clamped)
            return clamped, "%s: %r is outside %s-%s, clamped to %r" % (where, value, lo_hi[0], lo_hi[1], clamped)
        return value, None
    if kind == "str":
        if not isinstance(value, str):
            return default, "%s: expected text, got %r" % (where, value)
        if len(value) > MAX_STR or "\x00" in value:
            return default, "%s: text too long or contains NUL" % where
        ch = choices_for(section, key)
        if ch is not None and value not in ch:
            return default, "%s: %r is not one of %s" % (where, value, ", ".join(ch))
        if (section, key) == ("terminal", "fontFamily") and not re.match(r"^[\w .+-]{1,64}$", value):
            return default, "%s: %r is not a font family name" % (where, value)
        if (section, key) == ("terminal", "customProfile") and value and (
                not value.startswith("/") or ".." in value.split("/") or "\n" in value or len(value) > 512):
            return default, "%s: must be an absolute path to a file" % where
        if (section, key) == ("appearance", "palette"):
            from . import palettes
            if value not in palettes.ids():
                return default, "%s: unknown palette %r" % (where, value)
        if (section, key) in COLOR_KEYS and not COLOR_RE.match(value):
            return default, "%s: %r is not a #RRGGBB colour" % (where, value)
        if (section, key) in OPTIONAL_COLOR_KEYS and value and not COLOR_RE.match(value):
            return default, "%s: %r is not a #RRGGBB colour (or empty)" % (where, value)
        return value, None
    if kind == "list":
        if not isinstance(value, list):
            return default, "%s: expected a list, got %s" % (where, type(value).__name__)
        if (section, key) == ("automation", "rules"):
            from . import automation
            good, problems = automation.validate_rules(value)
            return good, ("%s: %s" % (where, "; ".join(problems))) if problems else None
        if (section, key) in STRUCTURED_LISTS:
            return STRUCTURED_LISTS[(section, key)](where, value)
        if not all(isinstance(v, str) and len(v) <= MAX_STR for v in value):
            return [v for v in value if isinstance(v, str) and len(v) <= MAX_STR], "%s: non-text entries dropped" % where
        return value, None
    if kind == "map":
        if not isinstance(value, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in value.items()):
            return default, "%s: expected an object of text values" % where
        if (section, key) in WORKSPACE_MAPS:
            bad = [k for k in value if not re.match(r"^([1-9]|[1-9][0-9])$", k)]
            if bad:
                return {k: v for k, v in value.items() if k not in bad}, "%s: keys must be workspace numbers 1-99" % where
            if key == "names" and any(not re.match(r"^[\w .:@+-]{1,32}$", v, re.U) for v in value.values()):
                return default, "%s: names are 1-32 letters, digits, spaces or . : @ + -" % where
            if key == "icons" and any(not re.match(r"^[a-z-]{1,32}$", v) for v in value.values()):
                return default, "%s: icon names are lowercase words" % where
            if key == "perWorkspace" and any(not v.startswith("/") or ".." in v.split("/") for v in value.values()):
                return default, "%s: wallpapers must be absolute paths" % where
        return value, None
    return default, "%s: unknown schema type %s" % (where, kind)  # pragma: no cover


def validate(data: Any, fill_defaults: bool = False) -> Tuple[Dict[str, Dict[str, Any]], List[str]]:
    """Return (clean config, problems).

    Unknown sections/keys are dropped and reported; bad values are replaced
    by the default (or clamped) and reported. With ``fill_defaults`` the
    result contains every key, otherwise only keys present in ``data`` —
    a sparse file stays sparse, exactly like the shell writes it.
    """
    problems: List[str] = []
    clean: Dict[str, Dict[str, Any]] = defaults() if fill_defaults else {}
    if not isinstance(data, dict):
        return clean, ["top level must be a JSON object, got %s" % type(data).__name__]
    for section, body in data.items():
        if section not in SCHEMA:
            problems.append("unknown section %r dropped" % section)
            continue
        if not isinstance(body, dict):
            problems.append("section %r must be an object, dropped" % section)
            continue
        for key, value in body.items():
            if key not in SCHEMA[section]:
                problems.append("unknown key %s.%s dropped" % (section, key))
                continue
            good, problem = _check_value(section, key, value)
            if problem:
                problems.append(problem)
            clean.setdefault(section, {})[key] = good
    return clean, problems


# -- migrations ---------------------------------------------------------------

def _glass_from_opacity(opacity: float) -> str:
    if opacity >= 0.97:
        return "opaque"
    if opacity >= 0.86:
        return "light"
    if opacity >= 0.70:
        return "medium"
    if opacity >= 0.50:
        return "heavy"
    return "ultra"


def _v1_to_v2(cfg: Dict[str, Any], notes: List[str]) -> None:
    """Schema 1 → 2 (AetherOS 0.3.0): glass presets replace the bare panel-opacity slider.

    The preset that matches the user's existing opacity is selected so the
    desktop looks the same after the upgrade."""
    app = cfg.setdefault("appearance", {})
    if "glassStyle" not in app and isinstance(app.get("panelOpacity"), (int, float)):
        app["glassStyle"] = _glass_from_opacity(float(app["panelOpacity"]))
        notes.append("appearance.glassStyle set to %r to match panelOpacity %.2f" % (app["glassStyle"], app["panelOpacity"]))


def _v2_to_v3(cfg: Dict[str, Any], notes: List[str]) -> None:
    """Schema 2 → 3 (AetherOS 0.3.0): `animatedWallpapers` implied motion on the desktop; the new
    effects engine has its own switch. Carry reduced-motion over so nobody
    who turned motion off gets particles or parallax after upgrading."""
    if cfg.get("general", {}).get("reducedMotion") is True:
        eff = cfg.setdefault("effects", {})
        eff.setdefault("particles", False)
        eff.setdefault("glow", False)
        cfg.setdefault("wallpaper", {}).setdefault("parallax", False)
        notes.append("reduced motion was on: particles, glow and parallax start disabled")


def _v3_to_v4(cfg: Dict[str, Any], notes: List[str]) -> None:
    """Schema 3 → 4 (AetherOS 1.0): reduced motion becomes a motion profile;
    automation rules gain multi-action support (single `action` kept valid)."""
    gen = cfg.setdefault("general", {})
    if gen.get("reducedMotion") is True and "motionProfile" not in gen:
        gen["motionProfile"] = "none"
        notes.append("general.motionProfile set to 'none' (reduced motion was on)")


MIGRATIONS: List[Tuple[int, Callable[[Dict[str, Any], List[str]], None]]] = [(1, _v1_to_v2), (2, _v2_to_v3), (3, _v3_to_v4)]


def version_of(cfg: Any) -> int:
    if isinstance(cfg, dict) and isinstance(cfg.get("meta"), dict):
        v = cfg["meta"].get("schemaVersion")
        if isinstance(v, int) and not isinstance(v, bool) and v >= 1:
            return v
    return 1  # files written before versioning existed


def migrate(cfg: Dict[str, Any]) -> Tuple[Dict[str, Any], List[str]]:
    """Upgrade ``cfg`` to SCHEMA_VERSION. Raises ValueError for a file from
    a *newer* AetherOS — downgrading silently would drop settings."""
    cfg = copy.deepcopy(cfg)
    notes: List[str] = []
    ver = version_of(cfg)
    if ver > SCHEMA_VERSION:
        raise ValueError(
            "config.json is version %d but this AetherOS understands up to %d. "
            "Update AetherOS, or restore a snapshot made by this version." % (ver, SCHEMA_VERSION)
        )
    for from_ver, step in MIGRATIONS:
        if ver == from_ver:
            step(cfg, notes)
            ver = from_ver + 1
    cfg.setdefault("meta", {})["schemaVersion"] = SCHEMA_VERSION
    return cfg, notes


# -- file access --------------------------------------------------------------

def load(path: Optional[str] = None) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
    """Return (data, error). A missing file is ({}, None): defaults apply."""
    path = path or config_file()
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except FileNotFoundError:
        return {}, None
    except ValueError as exc:
        return None, "%s is not valid JSON (%s)" % (path, exc)
    except OSError as exc:
        return None, str(exc)
    if not isinstance(data, dict):
        return None, "%s does not contain a JSON object" % path
    return data, None


def save(data: Dict[str, Any], path: Optional[str] = None, backup: bool = True) -> Optional[str]:
    """Atomic write (0600 — the file can name private paths). Returns the
    backup path of the previous file, if one was made."""
    path = path or config_file()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    saved = None
    if backup and os.path.exists(path):
        saved = "%s.bak-%s" % (path, time.strftime("%Y%m%d-%H%M%S"))
        shutil.copy2(path, saved)
        _prune(path, keep=5)
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(data, fh, indent=4, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, path)
    return saved


def _prune(path: str, keep: int) -> None:
    d, base = os.path.split(path)
    try:
        old = sorted(f for f in os.listdir(d) if f.startswith(base + ".bak-"))
    except OSError:
        return
    for name in old[:-keep]:
        try:
            os.remove(os.path.join(d, name))
        except OSError:
            pass


def set_keys(changes: Dict[str, Dict[str, Any]], path: Optional[str] = None) -> Tuple[bool, List[str]]:
    """Validate and merge ``changes`` into config.json. All-or-nothing: if any
    value is rejected nothing is written."""
    clean, problems = validate(changes)
    if problems:
        return False, problems
    data, err = load(path)
    if data is None:
        return False, [err or "cannot read config"]
    for section, body in clean.items():
        data.setdefault(section, {})
        if not isinstance(data[section], dict):
            data[section] = {}
        data[section].update(body)
    save(data, path)
    return True, []
