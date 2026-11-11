"""Read-only system status for the System Centre: updates, security posture
and systemd user services.

Everything here observes. The only mutating function is
``service_action`` (start/stop/restart of a *user* unit, no privileges).
Updates are listed, never installed from here: the shell opens a terminal
running `sudo dnf upgrade` so the user sees and approves the transaction.
"""

from __future__ import annotations

import json
import re
from typing import Any, Dict, List

from .hw import system
from .util import Context

UNIT_RE = re.compile(r"^[A-Za-z0-9@_.:\\-]{1,200}\.(service|timer|socket)$")
_PKG_LINE = re.compile(r"^(\S+)\.(x86_64|aarch64|noarch|i686|ppc64le|s390x|riscv64)\s+(\S+)\s+(\S+)\s*$")


def parse_check_update(text: str) -> List[Dict[str, str]]:
    """Parse `dnf check-update` output (dnf4 and dnf5 print the same three
    columns). Everything after an 'Obsoleting' header is ignored."""
    out: List[Dict[str, str]] = []
    for line in text.splitlines():
        if line.strip().lower().startswith("obsoleting"):
            break
        m = _PKG_LINE.match(line.strip())
        if m:
            out.append({"name": m.group(1), "arch": m.group(2), "version": m.group(3), "repo": m.group(4)})
    return out


def updates(ctx: Context) -> Dict[str, Any]:
    if not ctx.which("dnf"):
        return {"available": False, "reason": "dnf not found (not a Fedora system?)"}
    # --refresh is not passed: this must be cheap. Metadata age is dnf's call.
    res = ctx.run(["dnf", "-q", "check-update"], timeout=180)
    if res.rc not in (0, 100):
        return {"available": False, "reason": (res.err or res.out).strip().splitlines()[-1] if (res.err or res.out).strip() else "dnf check-update failed (rc %d)" % res.rc}
    pkgs = parse_check_update(res.out) if res.rc == 100 else []
    reboot = None
    nr = ctx.run(["dnf", "needs-restarting", "-r"], timeout=60)
    if nr.rc in (0, 1) and (nr.out or nr.err):
        reboot = nr.rc == 1
    security = [p for p in pkgs if p["name"].startswith(("kernel", "glibc", "openssl", "systemd"))]
    return {"available": True, "count": len(pkgs), "packages": pkgs, "rebootRequired": reboot,
            "corePackages": [p["name"] for p in security],
            "command": ["sudo", "dnf", "upgrade", "--refresh"]}


def _first_line(res) -> str:
    return (res.out or "").strip().splitlines()[0] if (res.out or "").strip() else ""


def security(ctx: Context) -> Dict[str, Any]:
    items: List[Dict[str, str]] = []

    def add(key: str, label: str, level: str, value: str, detail: str = "") -> None:
        items.append({"id": key, "label": label, "level": level, "value": value, "detail": detail})

    enforce = ctx.read_line("/sys/fs/selinux/enforce")
    if enforce is None:
        ge = ctx.run(["getenforce"], timeout=5)
        mode = _first_line(ge) if ge.ok else ""
        if mode:
            add("selinux", "SELinux", "pass" if mode == "Enforcing" else "warn", mode)
        else:
            add("selinux", "SELinux", "warn", "Not available", "No SELinux filesystem; Fedora ships it enabled.")
    else:
        add("selinux", "SELinux", "pass" if enforce.strip() == "1" else "warn",
            "Enforcing" if enforce.strip() == "1" else "Permissive",
            "" if enforce.strip() == "1" else "AetherOS never changes this. Re-enable with: sudo setenforce 1")

    fw = ctx.run(["systemctl", "is-active", "firewalld.service"], timeout=5)
    state = _first_line(fw) or "unknown"
    add("firewall", "Firewall (firewalld)", "pass" if state == "active" else "warn", state,
        "" if state == "active" else "Start it with: sudo systemctl enable --now firewalld")

    sb = system.secure_boot(ctx)
    sb_state = str(sb.get("state", "unknown"))
    add("secureboot", "Secure Boot", "pass" if sb_state == "enabled" else "info", sb_state, str(sb.get("source", "")))

    lsblk = ctx.run(["lsblk", "-rno", "TYPE"], timeout=5)
    if lsblk.ok:
        crypt = "crypt" in lsblk.out.split()
        add("encryption", "Disk encryption", "pass" if crypt else "info", "LUKS volume active" if crypt else "No encrypted volume open",
            "" if crypt else "Full-disk encryption is chosen at install time; this is informational.")
    else:
        add("encryption", "Disk encryption", "info", "Unknown", "lsblk unavailable")

    return {"items": items}


def services(ctx: Context) -> Dict[str, Any]:
    if not ctx.which("systemctl"):
        return {"available": False, "reason": "systemctl not found"}
    res = ctx.run(["systemctl", "--user", "list-units", "--type=service", "--all", "--no-legend", "--plain", "--no-pager"], timeout=10)
    if not res.ok:
        return {"available": False, "reason": (res.err or "no systemd user session").strip()}
    units = []
    for line in res.out.splitlines():
        parts = line.split(None, 4)
        if len(parts) < 4 or not parts[0].endswith(".service"):
            continue
        units.append({"unit": parts[0], "load": parts[1], "active": parts[2], "sub": parts[3],
                      "description": parts[4] if len(parts) > 4 else "", "aether": parts[0].startswith("aether-")})
    units.sort(key=lambda u: (not u["aether"], u["active"] != "failed", u["unit"]))
    return {"available": True, "units": units, "failed": [u["unit"] for u in units if u["active"] == "failed"]}


def service_action(ctx: Context, action: str, unit: str) -> Dict[str, Any]:
    if action not in ("start", "stop", "restart"):
        return {"ok": False, "error": "action must be start, stop or restart"}
    if not UNIT_RE.match(unit):
        return {"ok": False, "error": "not a valid unit name"}
    res = ctx.run(["systemctl", "--user", action, unit], timeout=30)
    return {"ok": res.ok, "error": (res.err or res.out).strip() if not res.ok else None}


def service_log(ctx: Context, unit: str, lines: int = 40) -> Dict[str, Any]:
    if not UNIT_RE.match(unit):
        return {"ok": False, "error": "not a valid unit name"}
    res = ctx.run(["journalctl", "--user", "-u", unit, "-n", str(max(1, min(500, lines))), "--no-pager", "-o", "short-iso"], timeout=15)
    return {"ok": res.ok, "log": res.out if res.ok else "", "error": res.err.strip() if not res.ok else None}


def dumps(data: Any) -> str:
    return json.dumps(data, indent=2, sort_keys=False)
