"""Automation rules: validation shared with the shell.

A rule is data, never code:

    {"id": "r1", "name": "Dock on AC", "enabled": true,
     "trigger": {"type": "power-connected"},
     "conditions": [{"type": "time-between", "from": "08:00", "to": "20:00"}],
     "action": {"type": "set-quality", "value": "ultra"}}

Triggers and actions are fixed allowlists. There is deliberately no
"run command" action: importing somebody's rules file can change your
wallpaper, never run their shell script. The same tables live in
automation/Rules.js for the running shell; tests assert they match.
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Tuple

MAX_RULES = 64
MAX_ACTIONS = 5
TIME_RE = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")
NAME_RE = re.compile(r"^[\w .:@+-]{1,128}$", re.U)
APP_RE = re.compile(r"^[\w.+-]{1,128}$")

# param name -> validator kind
TRIGGERS: Dict[str, Dict[str, str]] = {
    "power-connected": {},
    "power-disconnected": {},
    "battery-below": {"value": "percent"},
    "bluetooth-connected": {"device": "name?"},
    "bluetooth-disconnected": {"device": "name?"},
    "app-opened": {"app": "app"},
    "app-closed": {"app": "app"},
    "workspace-active": {"value": "workspace"},
    "monitor-connected": {},
    "monitor-disconnected": {},
    "time": {"at": "time"},
    "network-changed": {},
    "focus-started": {},
    "focus-ended": {},
    "startup": {},
    "profile-applied": {"value": "name?"},
}

CONDITIONS: Dict[str, Dict[str, str]] = {
    "on-battery": {},
    "on-ac": {},
    "time-between": {"from": "time", "to": "time"},
    "battery-below": {"value": "percent"},
    "battery-above": {"value": "percent"},
}

ACTIONS: Dict[str, Dict[str, str]] = {
    "set-quality": {"value": "quality"},
    "set-theme-mode": {"value": "thememode"},
    "set-palette": {"value": "name"},
    "set-profile": {"value": "name"},
    "set-power-profile": {"value": "powerprofile"},
    "set-wallpaper": {"value": "path"},
    "next-wallpaper": {},
    "launch-app": {"app": "app"},
    "switch-workspace": {"value": "workspace"},
    "set-volume": {"value": "percent"},
    "set-dnd": {"value": "bool"},
    "set-dock": {"value": "bool"},
    "notify": {"title": "name", "body": "name?"},
    "set-motion": {"value": "motion"},
    "apply-layout": {"value": "name"},
}

_ENUMS = {
    "quality": ("auto", "eco", "performance", "balanced", "ultra"),
    "thememode": ("dark", "light", "auto"),
    "powerprofile": ("power-saver", "balanced", "performance"),
    "motion": ("none", "reduced", "balanced", "smooth", "premium"),
}


def _check_param(kind: str, value: Any) -> bool:
    optional = kind.endswith("?")
    kind = kind.rstrip("?")
    if value is None or value == "":
        return optional
    if kind == "percent":
        return isinstance(value, (int, float)) and not isinstance(value, bool) and 0 <= value <= 100
    if kind == "workspace":
        return isinstance(value, int) and not isinstance(value, bool) and 1 <= value <= 99
    if kind == "bool":
        return isinstance(value, bool)
    if kind == "time":
        return isinstance(value, str) and bool(TIME_RE.match(value))
    if kind == "name":
        return isinstance(value, str) and bool(NAME_RE.match(value))
    if kind == "app":
        # A desktop-entry id or window class — never a command line.
        return isinstance(value, str) and bool(APP_RE.match(value))
    if kind == "path":
        return isinstance(value, str) and value.startswith("/") and "\x00" not in value and ".." not in value.split("/") and len(value) < 1024
    if kind in _ENUMS:
        return value in _ENUMS[kind]
    return False


def _check_part(part: Any, table: Dict[str, Dict[str, str]], what: str) -> Tuple[Dict[str, Any], str]:
    if not isinstance(part, dict) or not isinstance(part.get("type"), str):
        return {}, "%s must be an object with a type" % what
    kind = part["type"]
    if kind not in table:
        return {}, "unknown %s %r" % (what, kind)
    out: Dict[str, Any] = {"type": kind}
    for name, validator in table[kind].items():
        value = part.get(name)
        if not _check_param(validator, value):
            return {}, "%s %s: bad or missing %r" % (what, kind, name)
        if value not in (None, ""):
            out[name] = value
    extra = set(part) - set(table[kind]) - {"type"}
    if extra:
        return {}, "%s %s: unexpected field(s) %s" % (what, kind, ", ".join(sorted(extra)))
    return out, ""


def validate_rule(rule: Any) -> Tuple[Dict[str, Any], str]:
    """Return (normalised rule, error). The error is '' when the rule is valid."""
    if not isinstance(rule, dict):
        return {}, "rule must be an object"
    rid, name = rule.get("id"), rule.get("name", "")
    if not isinstance(rid, str) or not re.match(r"^[A-Za-z0-9_-]{1,40}$", rid):
        return {}, "rule id must be 1-40 letters, digits, '-' or '_'"
    if not isinstance(name, str) or (name and not NAME_RE.match(name)):
        return {}, "rule %s: bad name" % rid
    trigger, err = _check_part(rule.get("trigger"), TRIGGERS, "trigger")
    if err:
        return {}, "rule %s: %s" % (rid, err)
    # Rules run 1-5 actions in order. The 0.3 form (a single "action") is
    # still accepted and normalised to "actions".
    if "action" in rule and "actions" in rule:
        return {}, "rule %s: use either action or actions" % rid
    raw_actions = rule.get("actions") if "actions" in rule else [rule.get("action")]
    if not isinstance(raw_actions, list) or not 1 <= len(raw_actions) <= MAX_ACTIONS:
        return {}, "rule %s: 1-%d actions" % (rid, MAX_ACTIONS)
    actions = []
    for a in raw_actions:
        good, err = _check_part(a, ACTIONS, "action")
        if err:
            return {}, "rule %s: %s" % (rid, err)
        actions.append(good)
    conds_in = rule.get("conditions", [])
    if not isinstance(conds_in, list) or len(conds_in) > 4:
        return {}, "rule %s: conditions must be a list of at most 4" % rid
    conds = []
    for c in conds_in:
        good, err = _check_part(c, CONDITIONS, "condition")
        if err:
            return {}, "rule %s: %s" % (rid, err)
        conds.append(good)
    extra = set(rule) - {"id", "name", "enabled", "trigger", "conditions", "action", "actions"}
    if extra:
        return {}, "rule %s: unexpected field(s) %s" % (rid, ", ".join(sorted(extra)))
    return {"id": rid, "name": name, "enabled": rule.get("enabled", True) is True,
            "trigger": trigger, "conditions": conds, "actions": actions}, ""


def find_conflicts(rules: List[Dict[str, Any]]) -> List[str]:
    """Pairs of enabled rules that fire on the same trigger and set the same
    thing to different values, and rules that can trigger each other."""
    out: List[str] = []
    live = [r for r in rules if r.get("enabled")]
    for i, a in enumerate(live):
        for b in live[i + 1:]:
            if a["trigger"] != b["trigger"] or a["conditions"] != b["conditions"]:
                continue
            for x in a["actions"]:
                for y in b["actions"]:
                    if x["type"] == y["type"] and x != y:
                        out.append("%s and %s both run %s on the same trigger with different values" % (a["id"], b["id"], x["type"]))
    # Loops: switch-workspace -> workspace-active -> switch-workspace ...
    hops = {r["trigger"].get("value"): a.get("value") for r in live if r["trigger"]["type"] == "workspace-active"
            for a in r["actions"] if a["type"] == "switch-workspace"}
    for start in hops:
        seen, cur = set(), start
        while cur in hops and cur not in seen:
            seen.add(cur)
            cur = hops[cur]
        if cur in seen and cur == start:
            out.append("workspace rules form a loop starting at workspace %s" % start)
    return sorted(set(out))


def validate_rules(rules: Any) -> Tuple[List[Dict[str, Any]], List[str]]:
    if not isinstance(rules, list):
        return [], ["rules must be a list"]
    good: List[Dict[str, Any]] = []
    problems: List[str] = []
    ids = set()
    for rule in rules[:MAX_RULES]:
        clean, err = validate_rule(rule)
        if err:
            problems.append(err)
        elif clean["id"] in ids:
            problems.append("duplicate rule id %s dropped" % clean["id"])
        else:
            ids.add(clean["id"])
            good.append(clean)
    if len(rules) > MAX_RULES:
        problems.append("more than %d rules; the rest were dropped" % MAX_RULES)
    return good, problems
