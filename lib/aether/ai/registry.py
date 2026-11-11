"""The assistant's action registry.

Each action: id, description (shown to the model and the user), parameters
with validators, and a `check` against the live system (the app must be
installed, the layout must exist…). The model proposes actions in a fenced
```aether-actions JSON block; anything not in this registry, or failing
validation, is rejected and reported back. Every accepted action still
requires the user to click Run in the shell, which executes it through its
own allowlisted ActionService / CLI paths — never a shell.
"""

from __future__ import annotations

import json
import re
from typing import Any, Callable, Dict, List, Optional, Tuple

PANELS = ("launcher", "controlcenter", "dashboard", "notifications", "overview", "settings", "systemcenter", "layouts", "clipboard")
SETTINGS_SECTIONS = ("appearance", "style", "effects", "bar", "dockisland", "notifications", "wallpaper", "wallfx", "battery",
                     "lock", "gestures", "automation", "profiles", "terminal", "accessibility", "performance", "about",
                     "keyboard", "mouse", "displays", "gpu", "privacy", "ai", "startup", "workspaces", "widgets", "backup", "developer")

Validator = Callable[[Any], bool]


def _enum(*vals: str) -> Validator:
    return lambda v: v in vals


def _int(lo: int, hi: int) -> Validator:
    return lambda v: isinstance(v, int) and not isinstance(v, bool) and lo <= v <= hi


_ID = re.compile(r"^[\w.+-]{1,200}$")

ACTIONS: Dict[str, Dict[str, Any]] = {
    "open-panel": {"description": "Open a desktop panel", "params": {"panel": _enum(*PANELS)}},
    "open-settings": {"description": "Open Settings at a section", "params": {"section": _enum(*SETTINGS_SECTIONS)}},
    "launch-app": {"description": "Launch an installed application by desktop id (e.g. firefox.desktop)",
                   "params": {"app": lambda v: isinstance(v, str) and bool(_ID.match(v))}, "check": "app"},
    "switch-workspace": {"description": "Switch to workspace N (1-99)", "params": {"workspace": _int(1, 99)}},
    "apply-layout": {"description": "Arrange windows with a saved layout", "params": {"name": lambda v: isinstance(v, str) and bool(re.match(r"^[a-z0-9-]{1,40}$", v))}, "check": "layout"},
    "apply-profile": {"description": "Apply a desktop profile (snapshot taken first)", "params": {"name": lambda v: isinstance(v, str) and bool(re.match(r"^[a-z0-9-]{1,40}$", v))}, "check": "profile"},
    "set-quality": {"description": "Set visual quality", "params": {"value": _enum("auto", "eco", "performance", "balanced", "ultra")}},
    "set-theme-mode": {"description": "Set dark/light/auto theme", "params": {"value": _enum("dark", "light", "auto")}},
    "set-palette": {"description": "Set the colour palette", "params": {"value": lambda v: isinstance(v, str) and bool(re.match(r"^[a-z0-9-]{1,40}$", v))}, "check": "palette"},
    "set-volume": {"description": "Set output volume (0-100)", "params": {"value": _int(0, 100)}},
    "set-dnd": {"description": "Turn Do Not Disturb on/off", "params": {"value": lambda v: isinstance(v, bool)}},
    "set-dock": {"description": "Show/hide the dock", "params": {"value": lambda v: isinstance(v, bool)}},
    "set-power-profile": {"description": "Set the power profile", "params": {"value": _enum("power-saver", "balanced", "performance")}},
    "lock-screen": {"description": "Lock the screen", "params": {}},
}


def _checks() -> Dict[str, Callable[[str], bool]]:
    from .. import apps, layouts, palettes, profiles
    return {
        "app": lambda v: v in apps.all_apps(),
        "layout": lambda v: layouts.get(v) is not None,
        "profile": lambda v: profiles.get(v)[0] is not None,
        "palette": lambda v: v in palettes.load(include_user=True) and v != "aether-light",
    }


def validate(proposal: Any, checks: Optional[Dict[str, Callable[[str], bool]]] = None) -> Tuple[Optional[Dict[str, Any]], str]:
    if not isinstance(proposal, dict) or not isinstance(proposal.get("action"), str):
        return None, "not an action object"
    spec = ACTIONS.get(proposal["action"])
    if spec is None:
        return None, "unknown action %r" % proposal["action"]
    args = proposal.get("args", {})
    if not isinstance(args, dict):
        return None, "args must be an object"
    extra = set(args) - set(spec["params"])
    if extra:
        return None, "%s: unexpected argument(s) %s" % (proposal["action"], ", ".join(sorted(extra)))
    for name, ok in spec["params"].items():
        if name not in args or not ok(args[name]):
            return None, "%s: bad or missing %r" % (proposal["action"], name)
    if spec.get("check"):
        checks = checks if checks is not None else _checks()
        key = next(iter(spec["params"]))
        if not checks[spec["check"]](args[key]):
            return None, "%s: %r doesn't exist on this system" % (proposal["action"], args[key])
    return {"action": proposal["action"], "args": args, "description": spec["description"]}, ""


FENCE = re.compile(r"```aether-actions\s*\n(.*?)\n```", re.S)


def extract(text: str, checks=None) -> Tuple[str, List[Dict[str, Any]], List[str]]:
    """Split a model reply into (visible text, accepted actions, rejections)."""
    accepted: List[Dict[str, Any]] = []
    rejected: List[str] = []
    for block in FENCE.findall(text):
        try:
            data = json.loads(block)
        except ValueError:
            rejected.append("an action block was not valid JSON")
            continue
        for item in (data if isinstance(data, list) else [data])[:5]:
            ok, why = validate(item, checks)
            if ok:
                accepted.append(ok)
            else:
                rejected.append(why)
    return FENCE.sub("", text).strip(), accepted, rejected


def system_prompt(context: str = "") -> str:
    lines = [
        "You are the AetherOS desktop assistant on a Fedora Linux computer running Hyprland.",
        "Answer briefly and concretely. You cannot run shell commands and must never suggest that you can.",
        "When the user asks you to do something on the desktop, you may propose actions from this list only,",
        "in ONE fenced block exactly like:",
        "```aether-actions",
        '[{"action": "open-panel", "args": {"panel": "settings"}}]',
        "```",
        "The user must confirm every action. Available actions:",
    ]
    for aid, spec in ACTIONS.items():
        lines.append("- %s(%s): %s" % (aid, ", ".join(spec["params"]), spec["description"]))
    lines.append("Panels: %s. Settings sections: %s." % (", ".join(PANELS), ", ".join(SETTINGS_SECTIONS)))
    if context:
        lines += ["", "Current system information (for answering questions; do not invent other values):", context]
    return "\n".join(lines)
