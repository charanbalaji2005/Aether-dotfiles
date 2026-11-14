"""aether-dock — the macOS-style app dock of the classic interface.

The dock is a Waybar bar (layouts "home" and "desk") whose pinned apps are
generated from a list of desktop-file IDs, so every icon is the app's real
icon from your icon theme. A click brings the app's open window forward
(switching workspace) and launches the app only when it has no window.

  aether-dock list                    pinned apps (and whether each is installed)
  aether-dock add ID [POSITION]       pin an app, e.g. firefox or org.gnome.Nautilus
  aether-dock remove ID               unpin it
  aether-dock move ID left|right      reorder
  aether-dock size PIXELS             icon size (24–96)
  aether-dock autohide auto|smart|off hide until the pointer touches the bottom edge |
                                      hide only while a window overlaps it | always shown
  aether-dock magnify FACTOR          icon growth under the pointer (1.0 = off … 2.0)
  aether-dock activate ID             focus the app's open window (on any workspace;
                                      again: its next window) or launch it if none is open
  aether-dock apps                    installed apps you could pin (ID and name)
  aether-dock generate                rewrite the Waybar modules (done automatically)

State: ~/.config/aether-shell/classic/dock.json. Generated modules:
~/.config/aether-shell/classic/waybar/dock-modules.jsonc (included by the layouts).
Standard library only.
"""

from __future__ import annotations

import configparser
import json
import os
import re
import socket
import subprocess
import sys
from pathlib import Path

# First-run pins (the order of the dock), each only if installed. Several IDs
# per slot cover distro packages and Flatpaks of the same app.
DEFAULT_SLOTS = [
    ["firefox", "org.mozilla.firefox", "brave-browser", "chromium-browser", "google-chrome"],
    ["thunar", "org.gnome.Nautilus", "org.kde.dolphin", "nemo"],
    ["kitty", "org.gnome.Ptyxis", "org.gnome.Console", "foot", "org.codeberg.dnkl.foot", "Alacritty"],
    ["code", "com.visualstudio.code", "codium", "com.vscodium.codium", "dev.zed.Zed"],
    ["discord", "com.discordapp.Discord", "vesktop", "dev.vencord.Vesktop"],
    ["spotify", "com.spotify.Client", "org.gnome.Rhythmbox3", "org.gnome.Music", "io.bassi.Amberol"],
    ["org.gnome.TextEditor", "org.gnome.gedit", "obsidian", "md.obsidian.Obsidian", "org.kde.kate"],
    ["org.gnome.Calendar", "org.gnome.Settings", "nwg-look"],
    ["btop", "org.gnome.SystemMonitor"],
    ["gimp", "org.gimp.GIMP", "org.inkscape.Inkscape"],
]
ID_RE = re.compile(r"^[A-Za-z0-9._+-]{1,120}$")
ICON_EXTS = (".svg", ".png", ".xpm")


def config_home() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")


def data_dirs() -> list[Path]:
    home = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share")
    rest = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    dirs = [home] + [Path(d) for d in rest.split(":") if d]
    dirs += [Path("/var/lib/flatpak/exports/share"), Path.home() / ".local/share/flatpak/exports/share"]
    return dirs


def state_path() -> Path:
    return config_home() / "aether-shell" / "classic" / "dock.json"


def modules_path() -> Path:
    return config_home() / "aether-shell" / "classic" / "waybar" / "dock-modules.jsonc"


def desktop_file(app_id: str) -> Path | None:
    for d in data_dirs():
        p = d / "applications" / (app_id + ".desktop")
        if p.is_file():
            return p
    return None


def read_entry(path: Path) -> dict:
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    cp.optionxform = str
    try:
        cp.read(path, encoding="utf-8")
        e = cp["Desktop Entry"]
    except (configparser.Error, KeyError, UnicodeDecodeError):
        return {}
    return {"Name": e.get("Name", path.stem), "Icon": e.get("Icon", ""), "NoDisplay": e.get("NoDisplay", "false"),
            "Type": e.get("Type", "Application"), "StartupWMClass": e.get("StartupWMClass", "")}


# ── Hyprland IPC ─────────────────────────────────────────────────────────
# Hyprland 0.57+ (Lua configuration) evaluates `dispatch` arguments as Lua, so
# the legacy "focuswindow address:0x…" form fails there; older releases only
# know the legacy form. hypr_dispatch tries Lua first and remembers which works.
_lua_dispatch: bool | None = None


def hypr_path(name: str) -> str:
    rt = os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid()
    return os.path.join(rt, "hypr", os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", ""), name)


def hypr(cmd: str) -> str:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(1.0)
    try:
        s.connect(hypr_path(".socket.sock"))
        s.sendall(cmd.encode())
        chunks = []
        while True:
            b = s.recv(65536)
            if not b:
                break
            chunks.append(b)
        return b"".join(chunks).decode("utf-8", "replace")
    except OSError:
        return ""
    finally:
        s.close()


def hypr_json(what: str):
    try:
        return json.loads(hypr("j/" + what) or "null")
    except ValueError:
        return None


def hypr_dispatch(lua: str, legacy: str) -> bool:
    """Run a dispatcher, as the Lua expression LUA or the legacy command LEGACY."""
    global _lua_dispatch
    if _lua_dispatch is not False:
        out = hypr("dispatch " + lua).strip()
        if out == "ok":
            _lua_dispatch = True
            return True
        if _lua_dispatch is None and "invalid dispatcher" in out.lower():
            _lua_dispatch = False          # a pre-Lua Hyprland: use the legacy form from now on
        else:
            return False
    return hypr("dispatch " + legacy).strip() == "ok"


def focus_window(address: str) -> bool:
    """Focus a window wherever it is: switches to its workspace (or shows its special workspace)."""
    if not re.fullmatch(r"0x[0-9a-fA-F]+", address or ""):
        return False
    return hypr_dispatch("hl.dsp.focus({ window = 'address:%s' })" % address, "focuswindow address:%s" % address)


def close_window(address: str) -> bool:
    if not re.fullmatch(r"0x[0-9a-fA-F]+", address or ""):
        return False
    return hypr_dispatch("hl.dsp.window.close({ window = 'address:%s' })" % address, "closewindow address:%s" % address)


def class_keys(app_id: str, wmclass: str = "") -> set[str]:
    """Window classes (lower case) that belong to the app with desktop ID APP_ID."""
    keys = {app_id.lower(), app_id.split(".")[-1].lower()}
    if wmclass:
        keys.add(wmclass.lower())
    return keys


def app_windows(app_id: str) -> list[dict]:
    """Mapped windows of APP_ID on every workspace, most recently focused first."""
    df = desktop_file(app_id)
    keys = class_keys(app_id, read_entry(df).get("StartupWMClass", "") if df else "")
    out = []
    for c in hypr_json("clients") or []:
        cls = (c.get("class") or c.get("initialClass") or "").lower()
        if cls and c.get("mapped", True) and (cls in keys or cls.split(".")[-1] in keys):
            out.append(c)
    return sorted(out, key=lambda c: c.get("focusHistoryID", 99))


def activate(app_id: str) -> int:
    """Dock click: bring the app's window forward (again: cycle its windows) or launch it."""
    wins = app_windows(app_id)
    if not wins:
        subprocess.Popen(["gtk-launch", app_id], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        return 0
    target = wins[0]
    if target.get("focusHistoryID") == 0 and len(wins) > 1:
        # Already in front: the next click visits its other windows in a stable order.
        ordered = sorted(wins, key=lambda c: c["address"])
        i = [c["address"] for c in ordered].index(target["address"])
        target = ordered[(i + 1) % len(ordered)]
    return 0 if focus_window(target["address"]) else 1


def icon_theme_names() -> list[str]:
    names = []
    for f in (config_home() / "gtk-3.0" / "settings.ini", config_home() / "gtk-4.0" / "settings.ini"):
        try:
            m = re.search(r"^gtk-icon-theme-name\s*=\s*(.+)$", f.read_text(encoding="utf-8"), re.M)
            if m:
                names.append(m.group(1).strip())
        except OSError:
            pass
    return names + ["Papirus-Dark", "Papirus", "Adwaita", "breeze", "hicolor"]


def find_icon(name: str) -> str | None:
    """Absolute path of the best icon for NAME (scalable first, then the largest bitmap)."""
    if not name:
        return None
    if name.startswith("/"):
        return name if os.path.isfile(name) else None
    best: tuple[int, str] | None = None
    for theme in icon_theme_names():
        for d in data_dirs() + [Path.home() / ".icons"]:
            root = d / "icons" / theme if d != Path.home() / ".icons" else d / theme
            if not root.is_dir():
                continue
            for sub in root.iterdir():
                if not sub.is_dir():
                    continue
                size = 10_000 if sub.name in ("scalable", "symbolic") else int(re.match(r"(\d+)", sub.name).group(1)) \
                    if re.match(r"\d+", sub.name) else 0
                for cat in ("apps", "applications"):
                    for ext in ICON_EXTS:
                        p = sub / cat / (name + ext)
                        if p.is_file() and (best is None or size > best[0]):
                            best = (size, str(p))
        if best:
            return best[1]
    for d in data_dirs():
        for ext in ICON_EXTS:
            p = d / "pixmaps" / (name + ext)
            if p.is_file():
                return str(p)
    return None


def load_state() -> dict:
    try:
        st = json.loads(state_path().read_text(encoding="utf-8"))
        if isinstance(st.get("pins"), list):
            st["pins"] = [p for p in st["pins"] if isinstance(p, str) and ID_RE.match(p)]
            st["size"] = int(st.get("size", 40))
            return st
    except (OSError, ValueError, TypeError):
        pass
    # First run: one installed app per slot, in dock order.
    pins = []
    for slot in DEFAULT_SLOTS:
        app = next((a for a in slot if desktop_file(a)), None)
        if app:
            pins.append(app)
    return {"pins": pins, "size": 40}


def save_state(st: dict) -> None:
    p = state_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(st, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, p)


def module_name(app_id: str) -> str:
    return "image#dock-" + re.sub(r"[^a-z0-9-]", "-", app_id.lower())


def generate(st: dict) -> Path:
    mods: dict[str, dict] = {}
    names = []
    for app in st["pins"]:
        df = desktop_file(app)
        if not df:
            continue
        entry = read_entry(df)
        icon = find_icon(entry.get("Icon", ""))
        if icon:
            name = module_name(app)
            mods[name] = {"path": icon, "size": st["size"], "on-click": "aether-dock activate %s" % app, "tooltip": False}
        else:
            # No icon file in the theme: a glyph keeps the app clickable.
            name = "custom/dock-" + module_name(app).split("#", 1)[1][5:]
            mods[name] = {"format": "󰣆", "tooltip-format": entry.get("Name", app),
                             "on-click": "aether-dock activate %s" % app}
        names.append(name)
    mods["custom/launchpad"] = {"format": "󰀻", "tooltip-format": "All apps (Launchpad)",
                                "on-click": "aether-menu launchpad", "on-click-right": "aether-dock menu"}
    if not names:
        mods["custom/dock-hint"] = {"format": "  Pin apps", "tooltip-format": "Right-click the grid button, or: aether-dock add ID",
                                    "on-click": "aether-dock menu"}
        names = ["custom/dock-hint"]
    mods["group/dock-pins"] = {"orientation": "horizontal", "modules": names}
    # Open windows of apps that are not pinned, with their own icons (Hyprland
    # implements wlr-foreign-toplevel). Pinned apps are left out, so nothing
    # appears twice; their window class is usually the last part of the ID.
    ignore = sorted({a for a in st["pins"]} | {a.split(".")[-1] for a in st["pins"]} | {a.split(".")[-1].lower() for a in st["pins"]})
    mods["wlr/taskbar#dock"] = {"format": "{icon}", "icon-size": st["size"] - 4, "tooltip-format": "{title}",
                                "on-click": "activate", "on-click-middle": "close", "on-click-right": "minimize-raise",
                                "ignore-list": ignore + ["aether-dropterm", "aether-settings"]}
    out = modules_path()
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(".tmp")
    tmp.write_text("// Generated by aether-dock from %s — edit with aether-dock, not by hand.\n%s\n"
                   % (state_path(), json.dumps(mods, indent=2, ensure_ascii=False)), encoding="utf-8")
    os.replace(tmp, out)
    return out


def installed_apps() -> list[tuple[str, str]]:
    seen, out = set(), []
    for d in data_dirs():
        for f in sorted((d / "applications").glob("*.desktop")) if (d / "applications").is_dir() else []:
            if f.stem in seen:
                continue
            seen.add(f.stem)
            e = read_entry(f)
            if e and e.get("NoDisplay", "false").lower() != "true" and e.get("Type") == "Application":
                out.append((f.stem, e["Name"]))
    return sorted(out, key=lambda x: x[1].lower())


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    cmd = args[0] if args else "list"
    st = load_state()
    if cmd in ("-h", "--help", "help"):
        print(__doc__.split("\n\n", 2)[1].strip() + "\n\n" + __doc__.split("\n\n", 2)[2].split("\n\n")[0])
        return 0
    if cmd == "list":
        for app in st["pins"]:
            print("%-32s %s" % (app, "installed" if desktop_file(app) else "not installed (hidden)"))
        print("icon size: %d" % st["size"])
        print("autohide: %s · magnify: %s" % (st.get("autohide", "auto"), st.get("magnify", 1.5)))
        return 0
    if cmd == "apps":
        for app_id, name in installed_apps():
            print("%-40s %s" % (app_id, name))
        return 0
    if cmd == "activate":
        if len(args) < 2 or not ID_RE.match(args[1]):
            print("usage: aether-dock activate ID", file=sys.stderr)
            return 2
        return activate(args[1])
    if cmd in ("add", "remove", "move") and (len(args) < 2 or not ID_RE.match(args[1])):
        print("usage: aether-dock %s ID" % cmd, file=sys.stderr)
        return 2
    if cmd == "add":
        if not desktop_file(args[1]):
            print("no app with ID %r (see: aether-dock apps)" % args[1], file=sys.stderr)
            return 1
        if args[1] not in st["pins"]:
            pos = int(args[2]) if len(args) > 2 and args[2].isdigit() else len(st["pins"])
            st["pins"].insert(min(pos, len(st["pins"])), args[1])
    elif cmd == "remove":
        if args[1] not in st["pins"]:
            print("%s is not pinned" % args[1], file=sys.stderr)
            return 1
        st["pins"].remove(args[1])
    elif cmd == "move":
        if args[1] not in st["pins"] or len(args) < 3 or args[2] not in ("left", "right"):
            print("usage: aether-dock move ID left|right (ID must be pinned)", file=sys.stderr)
            return 2
        i = st["pins"].index(args[1])
        j = max(0, i - 1) if args[2] == "left" else min(len(st["pins"]) - 1, i + 1)
        st["pins"][i], st["pins"][j] = st["pins"][j], st["pins"][i]
    elif cmd == "size":
        if len(args) < 2 or not args[1].isdigit() or not 24 <= int(args[1]) <= 96:
            print("usage: aether-dock size 24..96", file=sys.stderr)
            return 2
        st["size"] = int(args[1])
    elif cmd == "autohide":
        if len(args) < 2 or args[1] not in ("auto", "smart", "off"):
            print("usage: aether-dock autohide auto|smart|off", file=sys.stderr)
            return 2
        st["autohide"] = args[1]
    elif cmd == "magnify":
        try:
            factor = float(args[1]) if len(args) > 1 else 0.0
        except ValueError:
            factor = 0.0
        if not 1.0 <= factor <= 2.0:
            print("usage: aether-dock magnify 1.0..2.0 (1.0 turns it off)", file=sys.stderr)
            return 2
        st["magnify"] = round(factor, 2)
    elif cmd != "generate":
        print("unknown command %r (see: aether-dock --help)" % cmd, file=sys.stderr)
        return 2
    save_state(st)
    print("dock: %s" % generate(st))
    return 0


if __name__ == "__main__":
    sys.exit(main())
