"""Smart window layouts: arrange real windows into named regions.

A layout is a list of slots, each a role (terminal, editor, browser, …)
and a rectangle in fractions of the monitor's usable area. Applying one:

1. reads monitors and windows from Hyprland (`hyprctl -j`),
2. matches an existing window to each slot by window class,
3. optionally launches the first *installed* app for unmatched roles and
   waits for its window,
4. floats, moves and resizes each window with validated geometry.

Floating geometry is used because it is the only arrangement Hyprland lets
a client specify exactly; `aether layout undo` re-tiles what was tiled.
Nothing is forced: slots that would be smaller than MIN_W×MIN_H on the
target monitor are skipped and reported.
"""

from __future__ import annotations

import json
import os
import re
import time
from typing import Any, Dict, List, Optional, Tuple

from .util import Context, config_dir, state_dir

MIN_W, MIN_H = 320, 200
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,39}$")
ADDR_RE = re.compile(r"^0x[0-9a-fA-F]{1,16}$")

# role -> [(window class regex, launch argv)], first installed one wins.
ROLES: Dict[str, List[Tuple[str, List[str]]]] = {
    "terminal": [(r"^kitty$", ["kitty"]), (r"^com\.mitchellh\.ghostty$", ["ghostty"]), (r"^foot$", ["foot"]),
                 (r"^Alacritty$", ["alacritty"]), (r"^org\.wezfurlong\.wezterm$", ["wezterm"]), (r"^org\.gnome\.Ptyxis$", ["ptyxis"])],
    "editor": [(r"^(code|code-url-handler|Code)$", ["code"]), (r"^(codium|VSCodium)$", ["codium"]), (r"^dev\.zed\.Zed$", ["zed"]),
               (r"^org\.gnome\.TextEditor$", ["gnome-text-editor"]), (r"^org\.kde\.kate$", ["kate"])],
    "browser": [(r"^(firefox|org\.mozilla\.firefox)$", ["firefox"]), (r"^(chromium-browser|chromium)$", ["chromium-browser"]),
                (r"^google-chrome$", ["google-chrome"]), (r"^brave-browser$", ["brave-browser"]), (r"^org\.gnome\.Epiphany$", ["epiphany"])],
    "files": [(r"^org\.gnome\.Nautilus$", ["nautilus"]), (r"^org\.kde\.dolphin$", ["dolphin"]), (r"^thunar$", ["thunar"])],
    "notes": [(r"^obsidian$", ["obsidian"]), (r"^org\.gnome\.TextEditor$", ["gnome-text-editor"]), (r"^org\.gnome\.Notes$", ["bijiben"])],
    "pdf": [(r"^org\.gnome\.(Papers|Evince)$", ["papers"]), (r"^(evince|org\.gnome\.Evince)$", ["evince"]),
            (r"^org\.kde\.okular$", ["okular"]), (r"^org\.pwmt\.zathura$", ["zathura"])],
    "chat": [(r"^(discord|vesktop)$", ["discord"]), (r"^org\.telegram\.desktop$", ["telegram-desktop"]),
             (r"^(Element|element)$", ["element-desktop"]), (r"^(Slack|slack)$", ["slack"])],
    "media": [(r"^(Spotify|spotify)$", ["spotify"]), (r"^mpv$", ["mpv", "--idle", "--force-window"]), (r"^vlc$", ["vlc"])],
    "monitor": [(r"^(btop|htop)$", ["kitty", "--class", "btop", "-e", "btop"]), (r"^org\.gnome\.SystemMonitor$", ["gnome-system-monitor"])],
}

BUILTIN: Dict[str, Dict[str, Any]] = {
    "developer": {"label": "Developer", "summary": "Terminal left, editor centre, browser right.",
                  "slots": [{"role": "terminal", "x": 0.0, "y": 0.0, "w": 0.26, "h": 1.0},
                            {"role": "editor", "x": 0.26, "y": 0.0, "w": 0.44, "h": 1.0},
                            {"role": "browser", "x": 0.70, "y": 0.0, "w": 0.30, "h": 1.0}]},
    "research": {"label": "Research", "summary": "Browser and PDF side by side, notes and terminal below.",
                 "slots": [{"role": "browser", "x": 0.0, "y": 0.0, "w": 0.55, "h": 0.62},
                           {"role": "pdf", "x": 0.55, "y": 0.0, "w": 0.45, "h": 0.62},
                           {"role": "notes", "x": 0.0, "y": 0.62, "w": 0.55, "h": 0.38},
                           {"role": "terminal", "x": 0.55, "y": 0.62, "w": 0.45, "h": 0.38}]},
    "productivity": {"label": "Productivity", "summary": "Browser as the main window, files and notes stacked on the right.",
                     "slots": [{"role": "browser", "x": 0.0, "y": 0.0, "w": 0.64, "h": 1.0},
                               {"role": "files", "x": 0.64, "y": 0.0, "w": 0.36, "h": 0.5},
                               {"role": "notes", "x": 0.64, "y": 0.5, "w": 0.36, "h": 0.5}]},
    "multitasking": {"label": "Multitasking", "summary": "Four equal quadrants.",
                     "slots": [{"role": "browser", "x": 0.0, "y": 0.0, "w": 0.5, "h": 0.5},
                               {"role": "editor", "x": 0.5, "y": 0.0, "w": 0.5, "h": 0.5},
                               {"role": "terminal", "x": 0.0, "y": 0.5, "w": 0.5, "h": 0.5},
                               {"role": "files", "x": 0.5, "y": 0.5, "w": 0.5, "h": 0.5}]},
    "communication": {"label": "Communication", "summary": "Chat beside the browser with media in the corner.",
                      "slots": [{"role": "browser", "x": 0.0, "y": 0.0, "w": 0.6, "h": 1.0},
                                {"role": "chat", "x": 0.6, "y": 0.0, "w": 0.4, "h": 0.66},
                                {"role": "media", "x": 0.6, "y": 0.66, "w": 0.4, "h": 0.34}]},
    "presentation": {"label": "Presentation", "summary": "One centred window with wide margins.",
                     "slots": [{"role": "browser", "x": 0.08, "y": 0.06, "w": 0.84, "h": 0.88}]},
    "minimal": {"label": "Minimal", "summary": "A single centred terminal.",
                "slots": [{"role": "terminal", "x": 0.2, "y": 0.15, "w": 0.6, "h": 0.7}]},
}


def user_file() -> str:
    return os.path.join(config_dir(), "layouts.json")


def undo_file() -> str:
    return os.path.join(state_dir(), "layout-undo.json")


def check(raw: Any) -> Tuple[Optional[Dict[str, Any]], str]:
    if not isinstance(raw, dict) or not isinstance(raw.get("slots"), list) or not (1 <= len(raw["slots"]) <= 8):
        return None, "a layout needs 1-8 slots"
    slots = []
    for s in raw["slots"]:
        if not isinstance(s, dict) or s.get("role") not in ROLES:
            return None, "slot role must be one of %s" % ", ".join(ROLES)
        try:
            x, y, w, h = (float(s[k]) for k in ("x", "y", "w", "h"))
        except (KeyError, TypeError, ValueError):
            return None, "slot needs numeric x, y, w, h"
        if not (0 <= x < 1 and 0 <= y < 1 and 0.05 <= w <= 1 and 0.05 <= h <= 1 and x + w <= 1.0001 and y + h <= 1.0001):
            return None, "slot rectangle must lie inside the screen (fractions 0-1)"
        slots.append({"role": s["role"], "x": x, "y": y, "w": w, "h": h})
    label = raw.get("label", "")
    summary = raw.get("summary", "")
    if not isinstance(label, str) or not isinstance(summary, str) or len(label) > 60 or len(summary) > 200:
        return None, "label/summary must be short text"
    return {"label": label, "summary": summary, "slots": slots}, ""


def _user() -> Dict[str, Any]:
    try:
        with open(user_file(), "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return {}
    out = {}
    if isinstance(data, dict):
        for name, raw in data.items():
            if isinstance(name, str) and NAME_RE.match(name) and name not in BUILTIN:
                lay, _err = check(raw)
                if lay:
                    out[name] = lay
    return out


def listing() -> List[Dict[str, Any]]:
    out = [dict(name=n, builtin=True, **v) for n, v in BUILTIN.items()]
    out += [dict(name=n, builtin=False, **v) for n, v in sorted(_user().items())]
    return out


def get(name: str) -> Optional[Dict[str, Any]]:
    if name in BUILTIN:
        return BUILTIN[name]
    return _user().get(name)


# -- Hyprland ------------------------------------------------------------------

def _hypr_json(ctx: Context, what: str) -> Optional[Any]:
    res = ctx.run(["hyprctl", "-j", what], timeout=5)
    if not res.ok:
        return None
    try:
        return json.loads(res.out)
    except ValueError:
        return None


def usable_area(mon: Dict[str, Any]) -> Tuple[int, int, int, int]:
    """Logical (x, y, w, h) of a monitor minus the space reserved by panels."""
    scale = float(mon.get("scale") or 1.0) or 1.0
    w, h = float(mon.get("width", 0)), float(mon.get("height", 0))
    if int(mon.get("transform", 0)) % 2 == 1:  # 90°/270°: the mode is rotated
        w, h = h, w
    w, h = w / scale, h / scale
    res = mon.get("reserved") or [0, 0, 0, 0]
    left, top, right, bottom = (int(v) for v in (list(res) + [0, 0, 0, 0])[:4])
    return (int(mon.get("x", 0)) + left, int(mon.get("y", 0)) + top, int(w) - left - right, int(h) - top - bottom)


def plan(ctx: Context, name: str, monitor: Optional[str] = None, gap: int = 8) -> Dict[str, Any]:
    """Compute what applying ``name`` would do. Changes nothing."""
    layout = get(name)
    if layout is None:
        return {"ok": False, "error": "unknown layout %r" % name}
    monitors = _hypr_json(ctx, "monitors")
    clients = _hypr_json(ctx, "clients")
    if not isinstance(monitors, list) or not monitors or not isinstance(clients, list):
        return {"ok": False, "error": "Hyprland is not running (hyprctl returned nothing)"}
    mon = next((m for m in monitors if m.get("name") == monitor), None) if monitor else None
    if monitor and mon is None:
        return {"ok": False, "error": "no monitor named %r (connected: %s)" % (monitor, ", ".join(m.get("name", "?") for m in monitors))}
    mon = mon or next((m for m in monitors if m.get("focused")), monitors[0])
    ax, ay, aw, ah = usable_area(mon)
    ws = (mon.get("activeWorkspace") or {}).get("id")
    used: set = set()
    slots = []
    for s in layout["slots"]:
        x, y = ax + int(s["x"] * aw) + gap, ay + int(s["y"] * ah) + gap
        w, h = int(s["w"] * aw) - 2 * gap, int(s["h"] * ah) - 2 * gap
        entry: Dict[str, Any] = {"role": s["role"], "x": x, "y": y, "w": w, "h": h, "window": None, "launch": None, "skip": None}
        if w < MIN_W or h < MIN_H:
            entry["skip"] = "region would be %dx%d on %s — too small" % (w, h, mon.get("name"))
            slots.append(entry)
            continue
        # Prefer a window already on this workspace, then any mapped window.
        cands = []
        for pattern, _argv in ROLES[s["role"]]:
            rx = re.compile(pattern, re.I)
            for c in clients:
                addr = c.get("address", "")
                if addr in used or not ADDR_RE.match(addr) or not c.get("mapped", True):
                    continue
                if rx.match(c.get("class", "") or ""):
                    cands.append(((c.get("workspace") or {}).get("id") != ws, c))
        if cands:
            cands.sort(key=lambda t: t[0])
            win = cands[0][1]
            used.add(win["address"])
            entry["window"] = {"address": win["address"], "class": win.get("class"), "title": win.get("title"),
                               "floating": bool(win.get("floating")), "workspace": (win.get("workspace") or {}).get("id"),
                               "at": win.get("at"), "size": win.get("size")}
        else:
            argv = next((a for _p, a in ROLES[s["role"]] if ctx.which(a[0])), None)
            if argv:
                entry["launch"] = argv
            else:
                entry["skip"] = "no %s application is installed" % s["role"]
        slots.append(entry)
    return {"ok": True, "layout": name, "label": layout["label"], "monitor": mon.get("name"), "workspace": ws,
            "area": {"x": ax, "y": ay, "w": aw, "h": ah}, "slots": slots}


def _place(ctx: Context, addr: str, ws: Any, x: int, y: int, w: int, h: int, floating: bool) -> List[str]:
    errs = []
    cmds = []
    if ws is not None:
        cmds.append(["movetoworkspacesilent", "%s,address:%s" % (ws, addr)])
    if not floating:
        cmds.append(["setfloating", "address:%s" % addr])
    cmds.append(["resizewindowpixel", "exact %d %d,address:%s" % (w, h, addr)])
    cmds.append(["movewindowpixel", "exact %d %d,address:%s" % (x, y, addr)])
    for c in cmds:
        res = ctx.run(["hyprctl", "dispatch"] + c, timeout=5)
        if not res.ok or (res.out.strip() and res.out.strip() != "ok"):
            errs.append("%s: %s" % (c[0], (res.err or res.out).strip() or "failed"))
    return errs


def apply(ctx: Context, name: str, monitor: Optional[str] = None, launch: bool = True,
          wait: float = 6.0, sleep=time.sleep) -> Dict[str, Any]:
    p = plan(ctx, name, monitor)
    if not p["ok"]:
        return p
    undo = []
    placed, launched, skipped, errors = [], [], [], []
    for s in p["slots"]:
        if s["skip"]:
            skipped.append("%s: %s" % (s["role"], s["skip"]))
            continue
        win = s["window"]
        if win is None and s["launch"] and launch:
            before = {c.get("address") for c in (_hypr_json(ctx, "clients") or [])}
            res = ctx.run(["hyprctl", "dispatch", "exec", " ".join(s["launch"])], timeout=5)
            if not res.ok:
                errors.append("%s: could not launch %s" % (s["role"], s["launch"][0]))
                continue
            deadline, found = wait, None
            while deadline > 0 and found is None:
                sleep(0.25)
                deadline -= 0.25
                for c in _hypr_json(ctx, "clients") or []:
                    if c.get("address") not in before and ADDR_RE.match(c.get("address", "")) and c.get("mapped", True):
                        found = c
                        break
            if found is None:
                skipped.append("%s: %s did not open a window within %.0fs" % (s["role"], s["launch"][0], wait))
                continue
            launched.append(s["launch"][0])
            win = {"address": found["address"], "floating": bool(found.get("floating")), "new": True}
        elif win is None:
            skipped.append("%s: not running (launching disabled)" % s["role"])
            continue
        if not win.get("new"):
            undo.append({"address": win["address"], "floating": win["floating"], "workspace": win.get("workspace"),
                         "at": win.get("at"), "size": win.get("size")})
        errs = _place(ctx, win["address"], p["workspace"], s["x"], s["y"], s["w"], s["h"], win["floating"])
        if errs:
            errors += ["%s: %s" % (s["role"], e) for e in errs]
        else:
            placed.append(s["role"])
    try:
        os.makedirs(state_dir(), exist_ok=True)
        with open(undo_file(), "w", encoding="utf-8") as fh:
            json.dump({"layout": name, "windows": undo}, fh)
    except OSError:
        pass
    return {"ok": not errors, "layout": name, "monitor": p["monitor"], "placed": placed, "launched": launched,
            "skipped": skipped, "errors": errors}


def undo(ctx: Context) -> Dict[str, Any]:
    """Put windows moved by the last `apply` back (re-tile or old geometry).
    Windows that have since closed are skipped silently."""
    try:
        with open(undo_file(), "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return {"ok": False, "error": "nothing to undo"}
    alive = {c.get("address") for c in (_hypr_json(ctx, "clients") or [])}
    restored = 0
    for w in data.get("windows", []):
        addr = w.get("address", "")
        if addr not in alive or not ADDR_RE.match(addr):
            continue
        if w.get("workspace") is not None:
            ctx.run(["hyprctl", "dispatch", "movetoworkspacesilent", "%s,address:%s" % (w["workspace"], addr)], timeout=5)
        if not w.get("floating"):
            ctx.run(["hyprctl", "dispatch", "settiled", "address:%s" % addr], timeout=5)
        elif isinstance(w.get("at"), list) and isinstance(w.get("size"), list) and len(w["at"]) == 2 and len(w["size"]) == 2:
            ctx.run(["hyprctl", "dispatch", "resizewindowpixel", "exact %d %d,address:%s" % (w["size"][0], w["size"][1], addr)], timeout=5)
            ctx.run(["hyprctl", "dispatch", "movewindowpixel", "exact %d %d,address:%s" % (w["at"][0], w["at"][1], addr)], timeout=5)
        restored += 1
    try:
        os.remove(undo_file())
    except OSError:
        pass
    return {"ok": True, "restored": restored}


def save_current(ctx: Context, name: str, label: str = "") -> Dict[str, Any]:
    """Save the focused workspace's window arrangement as a layout. Only
    windows whose class maps to a known role are kept."""
    if not NAME_RE.match(name) or name in BUILTIN:
        return {"ok": False, "error": "name must be lowercase letters/digits/'-' and not a built-in layout"}
    monitors, clients = _hypr_json(ctx, "monitors"), _hypr_json(ctx, "clients")
    if not isinstance(monitors, list) or not monitors or not isinstance(clients, list):
        return {"ok": False, "error": "Hyprland is not running"}
    mon = next((m for m in monitors if m.get("focused")), monitors[0])
    ax, ay, aw, ah = usable_area(mon)
    ws = (mon.get("activeWorkspace") or {}).get("id")
    slots = []
    for c in clients:
        if (c.get("workspace") or {}).get("id") != ws or not c.get("mapped", True):
            continue
        role = next((r for r, opts in ROLES.items() if any(re.match(p, c.get("class", "") or "", re.I) for p, _a in opts)), None)
        at, size = c.get("at"), c.get("size")
        if role is None or not at or not size or aw <= 0 or ah <= 0:
            continue
        x = min(max((at[0] - ax) / aw, 0.0), 0.95)
        y = min(max((at[1] - ay) / ah, 0.0), 0.95)
        slots.append({"role": role, "x": round(x, 4), "y": round(y, 4),
                      "w": round(min(max(size[0] / aw, 0.05), 1 - x), 4), "h": round(min(max(size[1] / ah, 0.05), 1 - y), 4)})
    lay, err = check({"label": label or name, "summary": "Saved from workspace %s." % ws, "slots": slots[:8]})
    if lay is None:
        return {"ok": False, "error": err if slots else "no recognised application windows on this workspace"}
    data = _user()
    data[name] = lay
    os.makedirs(os.path.dirname(user_file()), exist_ok=True)
    with open(user_file(), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    return {"ok": True, "name": name, "slots": len(lay["slots"])}
