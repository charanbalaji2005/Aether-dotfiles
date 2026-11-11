"""Desktop profiles: named bundles of shell settings.

A profile is a sparse config patch (validated against the same schema as
config.json) plus, optionally, the name of a Hyprland visual profile.
Applying one changes only the keys it lists; it never touches files
outside ~/.config/aether-shell and always snapshots first.
"""

from __future__ import annotations

import json
import os
import re
from typing import Any, Dict, List, Optional, Tuple

from . import config as config_mod
from . import performance, snapshots
from .util import config_dir

NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,39}$")

BUILTIN: Dict[str, Dict[str, Any]] = {
    "aether": {
        "label": "AetherOS Default", "summary": "Floating glass bar, balanced effects, the built-in palette.",
        "hyprland": "balanced",
        "config": {
            "bar": {"position": "top", "style": "floating", "height": 38},
            "appearance": {"palette": "aether", "glassStyle": "medium", "barOpacity": 0.72, "cornerScale": 1.0, "accentBorders": True},
            "effects": {"quality": "auto", "particles": True, "glow": True},
            "wallpaper": {"transition": "fade", "ambient": "none", "parallax": False},
            "dock": {"enabled": False}, "island": {"enabled": True},
        }},
    "glass": {
        "label": "Deep Glass", "summary": "Heavier frosted surfaces, a magnifying dock and a circular wallpaper reveal.",
        "hyprland": "quality",
        "config": {
            "bar": {"position": "top", "style": "floating", "height": 36},
            "appearance": {"glassStyle": "heavy", "barOpacity": 0.55, "cornerScale": 1.15},
            "effects": {"quality": "auto", "glow": True},
            "wallpaper": {"transition": "circle"},
            "dock": {"enabled": True, "position": "bottom", "magnification": 1.5, "autoHide": False, "opacity": 0.55},
            "island": {"enabled": True},
        }},
    "minimal": {
        "label": "Minimal", "summary": "Opaque edge-to-edge bar, no dock or island, no ambient effects.",
        "hyprland": "balanced",
        "config": {
            "bar": {"style": "full", "height": 32, "showStats": False, "showNetSpeed": False, "showMedia": False},
            "appearance": {"glassStyle": "opaque", "barOpacity": 1.0, "cornerScale": 0.6, "accentBorders": False},
            "effects": {"quality": "eco", "particles": False, "glow": False},
            "wallpaper": {"transition": "fade", "ambient": "none", "parallax": False},
            "dock": {"enabled": False}, "island": {"enabled": False},
        }},
    "developer": {
        "label": "Developer", "summary": "Dense top bar with CPU/RAM/GPU and network speed, Tokyo Night palette, no dock.",
        "hyprland": "balanced",
        "config": {
            "bar": {"position": "top", "style": "full", "height": 34, "showStats": True, "showTemperatures": True, "showNetSpeed": True},
            "appearance": {"palette": "tokyo-night", "glassStyle": "light", "cornerScale": 0.8},
            "effects": {"quality": "balanced", "particles": False},
            "dock": {"enabled": False}, "island": {"enabled": True, "visualizer": False},
            "performance": {"telemetryInterval": 1500},
        }},
    "productivity": {
        "label": "Productivity", "summary": "Auto-hiding dock, quiet bar, short notification timeouts.",
        "hyprland": "balanced",
        "config": {
            "bar": {"style": "floating", "showStats": False, "showNetSpeed": False},
            "appearance": {"glassStyle": "medium"},
            "dock": {"enabled": True, "autoHide": True, "magnification": 1.25},
            "island": {"enabled": True, "showTimers": True},
            "notifications": {"timeoutLow": 3000, "timeoutNormal": 5000, "maxVisible": 3},
        }},
    "gaming": {
        "label": "Gaming", "summary": "Everything decorative off, compositor in low-latency mode, slower telemetry.",
        "hyprland": "low-latency",
        "config": {
            "appearance": {"glassStyle": "opaque", "animatedWallpapers": False},
            "effects": {"quality": "eco", "particles": False, "glow": False},
            "wallpaper": {"transition": "none", "ambient": "none", "parallax": False},
            "dock": {"enabled": False}, "island": {"enabled": False},
            "performance": {"telemetryInterval": 4000},
        }},
    "cinematic": {
        "label": "Cinematic", "summary": "Maximum effects: shader glass, starfield, parallax, random wallpaper transitions.",
        "hyprland": "quality",
        "config": {
            "appearance": {"glassStyle": "heavy", "cornerScale": 1.2},
            "effects": {"quality": "ultra", "particles": True, "glow": True, "shaders": True},
            "wallpaper": {"transition": "random", "transitionDuration": 1400, "ambient": "stars", "parallax": True},
            "dock": {"enabled": True, "magnification": 1.6}, "island": {"enabled": True, "visualizer": True},
        }},
    "neon": {
        "label": "Neon", "summary": "Near-transparent panels with a cyan accent and glowing edges.",
        "hyprland": "quality",
        "config": {
            "appearance": {"palette": "aether", "theme": "dark", "accent": "#22E4FF", "accentMode": "manual",
                           "glassStyle": "ultra", "accentBorders": True},
            "effects": {"quality": "auto", "glow": True},
            "wallpaper": {"transition": "wipe"},
        }},
    "battery-saver": {
        "label": "Battery Saver", "summary": "No shaders, particles, parallax or blur; telemetry sampled half as often.",
        "hyprland": "battery",
        "config": {
            "appearance": {"glassStyle": "opaque", "animatedWallpapers": False},
            "effects": {"quality": "eco", "particles": False, "glow": False},
            "wallpaper": {"transition": "none", "ambient": "none", "parallax": False, "schedule": "off"},
            "island": {"visualizer": False},
            "performance": {"telemetryInterval": 4000, "pauseOnBattery": True},
        }},
    "transparent": {
        "label": "Transparent", "summary": "The lightest glass AetherOS offers; relies on compositor blur for legibility.",
        "hyprland": "quality",
        "config": {
            "appearance": {"glassStyle": "ultra", "barOpacity": 0.35, "compositorBlur": "on"},
            "dock": {"opacity": 0.35},
        }},
    "classic": {
        "label": "Classic Linux", "summary": "Solid full-width bottom panel, square-ish corners, no dock or island.",
        "hyprland": "balanced",
        "config": {
            "bar": {"position": "bottom", "style": "full", "height": 40, "showActiveWindow": True},
            "appearance": {"glassStyle": "opaque", "barOpacity": 1.0, "cornerScale": 0.4},
            "dock": {"enabled": False}, "island": {"enabled": False},
            "effects": {"quality": "balanced", "glow": False},
        }},
}


def user_dir() -> str:
    return os.path.join(config_dir(), "profiles")


def _load_user(name: str) -> Tuple[Optional[Dict[str, Any]], str]:
    path = os.path.join(user_dir(), name + ".json")
    try:
        with open(path, "r", encoding="utf-8") as fh:
            raw = json.load(fh)
    except (OSError, ValueError) as exc:
        return None, str(exc)
    return check(raw)


def check(raw: Any) -> Tuple[Optional[Dict[str, Any]], str]:
    """Validate a profile document (from disk or an import). Returns
    (profile, error). Unknown fields are an error, not ignored: a profile
    someone shares should contain exactly what it appears to."""
    if not isinstance(raw, dict):
        return None, "profile must be a JSON object"
    extra = set(raw) - {"label", "summary", "hyprland", "config", "aetherProfile"}
    if extra:
        return None, "unexpected field(s): %s" % ", ".join(sorted(extra))
    label = raw.get("label", "")
    summary = raw.get("summary", "")
    if not isinstance(label, str) or not isinstance(summary, str) or len(label) > 60 or len(summary) > 300:
        return None, "label/summary must be short text"
    hypr = raw.get("hyprland")
    if hypr is not None and hypr not in performance.HYPR_PROFILES:
        return None, "hyprland must be one of %s" % ", ".join(performance.HYPR_PROFILES)
    clean, problems = config_mod.validate(raw.get("config", {}))
    if problems:
        return None, "; ".join(problems)
    clean.pop("meta", None)
    clean.get("automation", {}).pop("rules", None)  # rules are imported separately, on purpose
    return {"label": label, "summary": summary, "hyprland": hypr, "config": clean}, ""


def listing() -> List[Dict[str, Any]]:
    out = [{"name": n, "label": p["label"], "summary": p["summary"], "builtin": True} for n, p in BUILTIN.items()]
    try:
        names = sorted(f[:-5] for f in os.listdir(user_dir()) if f.endswith(".json"))
    except OSError:
        names = []
    for n in names:
        if not NAME_RE.match(n) or n in BUILTIN:
            continue
        prof, err = _load_user(n)
        out.append({"name": n, "label": (prof or {}).get("label") or n, "summary": (prof or {}).get("summary", ""),
                    "builtin": False, "error": err or None})
    return out


def get(name: str) -> Tuple[Optional[Dict[str, Any]], str]:
    if name in BUILTIN:
        return check(BUILTIN[name])
    if not NAME_RE.match(name):
        return None, "bad profile name"
    return _load_user(name)


def apply(name: str, dry_run: bool = False) -> Dict[str, Any]:
    prof, err = get(name)
    if prof is None:
        return {"ok": False, "error": err}
    if dry_run:
        return {"ok": True, "dryRun": True, "config": prof["config"], "hyprland": prof["hyprland"]}
    undo = snapshots.create("pre-profile")
    ok, problems = config_mod.set_keys(prof["config"])
    if not ok:
        return {"ok": False, "error": "; ".join(problems)}
    return {"ok": True, "applied": name, "hyprland": prof["hyprland"], "undo": undo}


def save_current(name: str, label: str = "", sections: Optional[List[str]] = None) -> Dict[str, Any]:
    """Save the appearance-related part of the current config as a profile."""
    if not NAME_RE.match(name) or name in BUILTIN:
        return {"ok": False, "error": "name must be lowercase letters/digits/'-' and not a built-in profile"}
    data, err = config_mod.load()
    if data is None:
        return {"ok": False, "error": err}
    keep = sections or ["bar", "appearance", "effects", "wallpaper", "dock", "island", "battery", "lock"]
    body = {s: dict(v) for s, v in data.items() if s in keep and isinstance(v, dict)}
    # Machine-specific values don't belong in something you might share.
    for key in ("wallpaper", "wallpapers"):
        body.get("appearance", {}).pop(key, None)
    for key in ("dayWallpaper", "nightWallpaper", "video", "favorites"):
        body.get("wallpaper", {}).pop(key, None)
    prof, err = check({"label": label or name, "summary": "Saved from the running desktop.", "config": body})
    if prof is None:
        return {"ok": False, "error": err}
    os.makedirs(user_dir(), exist_ok=True)
    path = os.path.join(user_dir(), name + ".json")
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(dict(prof, aetherProfile=1), fh, indent=2)
        fh.write("\n")
    return {"ok": True, "path": path}


def import_file(src: str, name: str) -> Dict[str, Any]:
    if not NAME_RE.match(name) or name in BUILTIN:
        return {"ok": False, "error": "bad or reserved profile name"}
    try:
        if os.path.getsize(src) > 256 * 1024:
            return {"ok": False, "error": "file is too large to be a profile"}
        with open(src, "r", encoding="utf-8") as fh:
            raw = json.load(fh)
    except (OSError, ValueError) as exc:
        return {"ok": False, "error": str(exc)}
    prof, err = check(raw)
    if prof is None:
        return {"ok": False, "error": err}
    os.makedirs(user_dir(), exist_ok=True)
    path = os.path.join(user_dir(), name + ".json")
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(dict(prof, aetherProfile=1), fh, indent=2)
        fh.write("\n")
    return {"ok": True, "path": path}
