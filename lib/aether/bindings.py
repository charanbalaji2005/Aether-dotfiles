"""aether-bindings — list, search and check the Hyprland keybindings.

The single source of truth is the Hyprland files themselves: the shared
config/hypr/keybinds.conf plus the active interface's
config/hypr/interfaces/<interface>.conf (and, if present, the user's own
~/.config/aether-shell/hypr/user-binds.conf). Descriptions come from a
trailing "#: text"; categories from the "# ── Name ──" section headers.

  aether-bindings list [CATEGORY]   every binding, grouped by category
  aether-bindings search TEXT       bindings whose keys, action or description match
  aether-bindings check             conflicts, unknown dispatchers, missing programs (exit 1 on errors)
"""

from __future__ import annotations

import os
import re
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path

# Dispatchers this configuration may use (Hyprland 0.45+). Unknown ones are errors.
DISPATCHERS = {
    "exec", "execr", "pass", "sendshortcut", "killactive", "forcekillactive", "closewindow", "killwindow",
    "signal", "workspace", "movetoworkspace", "movetoworkspacesilent", "togglefloating", "setfloating",
    "settiled", "fullscreen", "fullscreenstate", "dpms", "pin", "movefocus", "movewindow", "swapwindow",
    "centerwindow", "resizeactive", "moveactive", "resizewindowpixel", "movewindowpixel", "cyclenext",
    "swapnext", "tagwindow", "focuswindow", "focusmonitor", "splitratio", "movecursortocorner",
    "movecursor", "renameworkspace", "exit", "forcerendererreload", "movecurrentworkspacetomonitor",
    "focusworkspaceoncurrentmonitor", "moveworkspacetomonitor", "swapactiveworkspaces", "bringactivetotop",
    "alterzorder", "togglespecialworkspace", "focusurgentorlast", "togglegroup", "changegroupactive",
    "focuscurrentorlast", "lockgroups", "lockactivegroup", "moveintogroup", "moveoutofgroup",
    "movewindoworgroup", "movegroupwindow", "denywindowfromgroup", "setignoregrouplock", "global",
    "submap", "event", "setprop", "pseudo", "togglesplit", "swapsplit", "layoutmsg",
    "resizewindow",  # bindm (mouse) only
}
MOD_ORDER = {"SUPER": 0, "CTRL": 1, "CONTROL": 1, "ALT": 2, "SHIFT": 3}
CHAINED = {("ALT", "Tab")}  # two dispatchers on one key, on purpose
SHELL_BUILTINS = {"sh", "bash", "sleep"}


@dataclass
class Bind:
    mods: str
    key: str
    dispatcher: str
    arg: str
    desc: str
    category: str
    source: str
    line: int

    @property
    def combo(self) -> str:
        mods = sorted(self.mods.split(), key=lambda m: (MOD_ORDER.get(m.upper(), 9), m))
        return " + ".join(mods + [self.key]) if mods else self.key


def repo_dir() -> Path:
    return Path(__file__).resolve().parents[2]


def config_home() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")


def active_interface() -> str:
    try:
        v = (config_home() / "aether-shell" / "interface").read_text(encoding="utf-8").strip()
    except OSError:
        v = ""
    return v if v in ("classic", "aether") else "classic"


def sources(interface: str | None = None) -> list[Path]:
    hypr = repo_dir() / "config" / "hypr"
    out = [hypr / "keybinds.conf", hypr / "interfaces" / ("%s.conf" % (interface or active_interface()))]
    user = config_home() / "aether-shell" / "hypr" / "user-binds.conf"
    if user.is_file():
        out.append(user)
    return out


def parse(paths: list[Path]) -> tuple[list[Bind], dict[str, str]]:
    binds: list[Bind] = []
    variables: dict[str, str] = {}
    for path in paths:
        category = "General"
        for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            head = re.match(r"^#\s*──\s*(.+?)\s*─", raw)
            if head:
                category = head.group(1).split("(")[0].strip()
                continue
            code, _, comment = raw.partition("#")
            code = code.strip()
            desc = comment[1:].strip() if comment.startswith(":") else ""
            m = re.match(r"^\$(\w+)\s*=\s*(.+)$", code)
            if m:
                variables[m.group(1)] = m.group(2).strip()
                continue
            m = re.match(r"^bind[a-z]*\s*=\s*([^,]*),\s*([^,]+),\s*([^,]+?)\s*(?:,\s*(.*))?$", code)
            if not m:
                continue
            mods = " ".join(sorted(expand(m.group(1), variables).split()))
            binds.append(Bind(mods, m.group(2).strip(), m.group(3).strip(), expand(m.group(4) or "", variables).strip(),
                              desc, category, path.name, n))
    return binds, variables


def expand(text: str, variables: dict[str, str]) -> str:
    return re.sub(r"\$(\w+)", lambda m: variables.get(m.group(1), m.group(0)), text)


def check(binds: list[Bind]) -> tuple[list[str], list[str]]:
    errors, warnings = [], []
    seen: dict[tuple[str, str], Bind] = {}
    bindir = repo_dir() / "scripts" / "bin"
    for b in binds:
        k = (b.mods, b.key)
        if k in seen and (seen[k].dispatcher, seen[k].arg) != (b.dispatcher, b.arg) and k not in CHAINED:
            errors.append("conflict: %s is bound twice — %s:%d and %s:%d" % (b.combo, seen[k].source, seen[k].line, b.source, b.line))
        seen.setdefault(k, b)
        if b.dispatcher not in DISPATCHERS:
            errors.append("%s:%d: unknown dispatcher '%s' (%s)" % (b.source, b.line, b.dispatcher, b.combo))
        if b.dispatcher == "exec" and b.arg:
            prog = b.arg.split()[0]
            if prog.startswith("$"):
                errors.append("%s:%d: undefined variable %s (%s)" % (b.source, b.line, prog, b.combo))
            elif prog not in SHELL_BUILTINS and not (bindir / prog).is_file() and not shutil.which(prog):
                warnings.append("%s: '%s' is not installed — the key does nothing until it is" % (b.combo, prog))
    return errors, warnings


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    cmd = args[0] if args else "list"
    iface = None
    if "--interface" in args:
        i = args.index("--interface")
        iface = args[i + 1] if i + 1 < len(args) else None
        del args[i:i + 2]
    binds, _ = parse(sources(iface))
    if cmd in ("-h", "--help", "help"):
        print(__doc__.split("\n\n", 2)[2].rstrip())
        return 0
    if cmd == "list":
        want = " ".join(args[1:]).lower()
        last = None
        for b in binds:
            if want and want not in b.category.lower():
                continue
            if b.category != last:
                print("\n%s" % b.category)
                last = b.category
            print("  %-26s %s" % (b.combo, b.desc or ("%s %s" % (b.dispatcher, b.arg)).strip()))
        return 0
    if cmd == "search":
        q = " ".join(args[1:]).lower()
        if not q:
            print("usage: aether-bindings search TEXT", file=sys.stderr)
            return 2
        for b in binds:
            hay = " ".join((b.combo, b.dispatcher, b.arg, b.desc, b.category)).lower()
            if q in hay:
                print("%-26s %-22s %s" % (b.combo, b.category, b.desc or ("%s %s" % (b.dispatcher, b.arg)).strip()))
        return 0
    if cmd == "check":
        errors, warnings = check(binds)
        for w in warnings:
            print("warn  " + w)
        for e in errors:
            print("FAIL  " + e)
        print("%d bindings checked (%s interface): %d error(s), %d warning(s)"
              % (len(binds), iface or active_interface(), len(errors), len(warnings)))
        return 1 if errors else 0
    print("usage: aether-bindings list [CATEGORY] | search TEXT | check  [--interface classic|aether]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
