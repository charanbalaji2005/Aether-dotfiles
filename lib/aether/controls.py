"""Controls of the AetherOS Control Centre (classic interface).

One registry used by the Control Centre panel and by its editor in Settings.
Every control reads its state from the real system and acts through the same
helpers as the menus and keys (aether-toggle, aether-osd, aether-shot, …).
If the program behind a control is missing, the control says so ("unavailable")
instead of pretending.

The layout (which controls, in which order) lives in
~/.config/aether-shell/classic/control-centre.json.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

REPO = Path(__file__).resolve().parents[2]
BIN = REPO / "scripts" / "bin"


def sh(*args: str, timeout: int = 6) -> tuple[int, str]:
    cmd = list(args)
    if (BIN / cmd[0]).is_file():
        cmd = ["bash", str(BIN / cmd[0])] + cmd[1:]
    elif not shutil.which(cmd[0]):
        return 127, "%s is not installed" % cmd[0]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=False)
        return p.returncode, (p.stdout + p.stderr).strip()
    except (OSError, subprocess.TimeoutExpired) as e:
        return 1, str(e)


def spawn(*args: str) -> None:
    cmd = list(args)
    if (BIN / cmd[0]).is_file():
        cmd = ["bash", str(BIN / cmd[0])] + cmd[1:]
    try:
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError:
        pass


@dataclass
class Control:
    cid: str
    name: str
    glyph: str
    category: str
    kind: str                      # toggle | slider | button | media | cluster
    needs: tuple[str, ...] = ()
    size: str = "small"            # small (1x1) | wide (2x1) | tall (1x2) | big (2x2)
    state: Callable[[], dict] = field(default=lambda: {})
    act: Callable[..., tuple[int, str]] = field(default=lambda *a: (0, ""))
    tint: str = "#0a84ff"          # orb colour when on (iOS-like per-control colours)
    members: tuple[str, ...] = ()  # for a cluster: the controls grouped in one card

    def available(self) -> bool:
        return all(shutil.which(n) or (BIN / n).is_file() for n in self.needs)


# ── state readers ───────────────────────────────────────────────────────
def _toggle_state(name: str) -> dict:
    rc, out = sh("aether-toggle", "status", name)
    on = out.strip().splitlines()[-1:] == ["on"] if rc == 0 else False
    return {"on": on, "label": "On" if on else "Off"}


def _wifi_state() -> dict:
    rc, out = sh("nmcli", "-t", "-f", "WIFI", "radio")
    if rc != 0:
        return {"on": False, "label": "Unavailable", "disabled": True}
    on = out.strip() == "enabled"
    ssid = ""
    if on:
        _, act = sh("nmcli", "-t", "-f", "ACTIVE,SSID", "dev", "wifi")
        ssid = next((l.split(":", 1)[1] for l in act.splitlines() if l.startswith("yes:")), "")
    return {"on": on, "label": ssid or ("Not connected" if on else "Off")}


def _bt_state() -> dict:
    rc, out = sh("bluetoothctl", "show")
    if rc != 0 or "Controller" not in out:
        return {"on": False, "label": "No adapter", "disabled": True}
    on = "Powered: yes" in out
    return {"on": on, "label": "On" if on else "Off"}


def _dark_state() -> dict:
    from aether import classic_colors as cc
    dark = cc.read_state().get("mode", "dark") == "dark"
    return {"on": dark, "label": "Dark" if dark else "Light"}


def _volume_state() -> dict:
    rc, out = sh("wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@")
    m = re.search(r"([\d.]+)", out) if rc == 0 else None
    if not m:
        return {"value": 0, "disabled": True, "label": "No audio"}
    return {"value": round(float(m.group(1)) * 100), "muted": "MUTED" in out}


def _brightness_state() -> dict:
    rc, out = sh("brightnessctl", "-m", "-c", "backlight")
    m = re.search(r",(\d+)%", out) if rc == 0 else None
    if not m:
        return {"value": 0, "disabled": True, "label": "No backlight (external screens need ddcutil)"}
    return {"value": int(m.group(1))}


def _media_state() -> dict:
    rc, st = sh("playerctl", "status")
    if rc != 0 or st not in ("Playing", "Paused"):
        return {"playing": False, "title": "Nothing playing", "artist": ""}
    _, meta = sh("playerctl", "metadata", "--format", "{{ title }}\t{{ artist }}\t{{ mpris:artUrl }}")
    t, a, art = (meta.split("\t") + ["", "", ""])[:3]
    return {"playing": st == "Playing", "title": t or "Unknown", "artist": a, "art": art}


def _profile_state() -> dict:
    rc, out = sh("powerprofilesctl", "get")
    if rc != 0:
        return {"on": False, "label": "Unavailable", "disabled": True}
    return {"on": out.strip() != "balanced", "label": out.strip().replace("-", " ").title()}


# ── actions ─────────────────────────────────────────────────────────────
def _set_volume(v: float) -> tuple[int, str]:
    return sh("wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", "%d%%" % int(v))


def _set_brightness(v: float) -> tuple[int, str]:
    return sh("brightnessctl", "-c", "backlight", "set", "%d%%" % max(1, int(v)))


def _cycle_profile() -> tuple[int, str]:
    order = ["power-saver", "balanced", "performance"]
    _, cur = sh("powerprofilesctl", "get")
    nxt = order[(order.index(cur.strip()) + 1) % 3] if cur.strip() in order else "balanced"
    return sh("powerprofilesctl", "set", nxt)


CONTROLS: dict[str, Control] = {c.cid: c for c in [
    Control("wifi", "Wi-Fi", "󰖩", "Connectivity", "toggle", ("nmcli",), "wide", _wifi_state,
            lambda: sh("nmcli", "radio", "wifi", "off" if _wifi_state().get("on") else "on")),
    Control("bluetooth", "Bluetooth", "󰂯", "Connectivity", "toggle", ("bluetoothctl",), "small", _bt_state,
            lambda: sh("bluetoothctl", "power", "off" if _bt_state().get("on") else "on")),
    Control("airplane", "Airplane mode", "󰀝", "Connectivity", "toggle", ("rfkill",), "small",
            lambda: _toggle_state("airplane"), lambda: sh("aether-toggle", "airplane")),
    Control("connectivity", "Connectivity", "󰖩", "Connectivity", "cluster", (), "big", lambda: {},
            lambda: (0, ""), members=("airplane", "power", "wifi", "bluetooth")),
    Control("music", "Now playing", "󰎆", "Media", "media", ("playerctl",), "big", _media_state,
            lambda what="play-pause": sh("playerctl", what)),
    Control("dnd", "Focus", "󰖔", "Focus", "toggle", ("swaync-client",), "wide",
            lambda: _toggle_state("dnd"), lambda: sh("aether-toggle", "dnd"), tint="#5e5ce6"),
    Control("gamemode", "Game mode", "󰊴", "Focus", "toggle", (), "small",
            lambda: _toggle_state("gamemode"), lambda: sh("aether-toggle", "gamemode"), tint="#30d158"),
    Control("idle", "Keep awake", "󰅶", "Focus", "toggle", ("hypridle",), "small",
            lambda: _toggle_state("idle"), lambda: sh("aether-toggle", "idle"), tint="#ff9f0a"),
    Control("brightness", "Display", "󰃠", "Display", "slider", ("brightnessctl",), "tall", _brightness_state, _set_brightness),
    Control("nightlight", "Night light", "󰛨", "Display", "toggle", ("hyprsunset",), "small",
            lambda: _toggle_state("nightlight"), lambda: sh("aether-toggle", "nightlight"), tint="#ff9f0a"),
    Control("darkmode", "Dark mode", "󰔎", "Display", "toggle", (), "small", _dark_state,
            lambda: sh("aether-colors", "mode", "toggle", timeout=40), tint="#5e5ce6"),
    Control("volume", "Sound", "󰕾", "Sound", "slider", ("wpctl",), "tall", _volume_state, _set_volume),
    Control("mixer", "Sound mixer", "󰓃", "Sound", "button", ("pavucontrol",), "small", lambda: {},
            lambda: (spawn("pavucontrol"), (0, ""))[1]),
    Control("power", "Power profile", "󰾅", "Battery", "toggle", ("powerprofilesctl",), "small", _profile_state, _cycle_profile,
            tint="#30d158"),
    Control("screenshot", "Screenshot", "󰄀", "System", "button", ("grim", "slurp"), "small", lambda: {},
            lambda: (spawn("aether-shot", "area"), (0, ""))[1]),
    Control("record", "Screen recording", "󰻃", "System", "button", ("wf-recorder",), "small", lambda: {},
            lambda: (spawn("aether-record", "toggle", "full"), (0, ""))[1]),
    Control("lock", "Lock screen", "󰌾", "System", "button", (), "small", lambda: {},
            lambda: (spawn("aether-lock"), (0, ""))[1]),
    Control("wallpaper", "Wallpaper", "󰸉", "Appearance", "button", (), "small", lambda: {},
            lambda: (spawn("aether-wall", "select"), (0, ""))[1]),
    Control("look", "Looks", "󰔉", "Appearance", "button", (), "small", lambda: {},
            lambda: (spawn("aether-look"), (0, ""))[1]),
    Control("calculator", "Calculator", "󰃬", "Utilities", "button", (), "small", lambda: {},
            lambda: (spawn("aether-menu", "calc"), (0, ""))[1]),
    Control("clipboard", "Clipboard", "󰅌", "Utilities", "button", ("cliphist",), "small", lambda: {},
            lambda: (spawn("aether-menu", "clipboard"), (0, ""))[1]),
    Control("notifications", "Notifications", "󰂚", "Utilities", "button", ("swaync-client",), "small", lambda: {},
            lambda: sh("swaync-client", "-t", "-sw")),
    Control("settings", "Settings", "󰒓", "Utilities", "button", (), "small", lambda: {},
            lambda: (spawn("aether-settings"), (0, ""))[1]),
]}

# Arranged like a phone control centre: a connectivity card and the player on
# top, two small toggles beside tall brightness/volume sliders, the Focus pill,
# then a row of round buttons.
DEFAULT_LAYOUT = ["connectivity", "music", "nightlight", "darkmode", "brightness", "volume", "dnd",
                  "lock", "screenshot", "calculator", "record"]


def layout_path() -> Path:
    base = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    return base / "aether-shell" / "classic" / "control-centre.json"


def load_layout() -> list[str]:
    try:
        ids = json.loads(layout_path().read_text(encoding="utf-8")).get("controls", [])
        ids = [i for i in ids if i in CONTROLS]
        return ids or list(DEFAULT_LAYOUT)
    except (OSError, ValueError, AttributeError):
        return list(DEFAULT_LAYOUT)


def save_layout(ids: list[str]) -> None:
    clean = []
    for i in ids:
        if i in CONTROLS and i not in clean:
            clean.append(i)
    p = layout_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps({"version": 1, "controls": clean}, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, p)


def add(cid: str, pos: int | None = None) -> list[str]:
    ids = load_layout()
    if cid in CONTROLS and cid not in ids:
        ids.insert(len(ids) if pos is None else max(0, min(pos, len(ids))), cid)
        save_layout(ids)
    return ids


def remove(cid: str) -> list[str]:
    ids = [i for i in load_layout() if i != cid]
    save_layout(ids)
    return ids


def move(cid: str, delta: int) -> list[str]:
    ids = load_layout()
    if cid in ids:
        i = ids.index(cid)
        j = max(0, min(len(ids) - 1, i + delta))
        ids[i], ids[j] = ids[j], ids[i]
        save_layout(ids)
    return ids


def reset() -> list[str]:
    save_layout(list(DEFAULT_LAYOUT))
    return list(DEFAULT_LAYOUT)
