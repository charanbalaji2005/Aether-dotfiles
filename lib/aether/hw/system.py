"""Operating-system, session and firmware detection."""

from __future__ import annotations

import json
import platform
import re
from typing import Dict, Optional

from ..util import Context, parse_version

# EFI global-variable GUID that holds the SecureBoot flag.
_SB_VAR = "/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"


def os_release(ctx: Context) -> Dict[str, str]:
    data: Dict[str, str] = {}
    text = ctx.read("/etc/os-release") or ctx.read("/usr/lib/os-release") or ""
    for line in text.splitlines():
        if "=" not in line or line.lstrip().startswith("#"):
            continue
        key, _, value = line.partition("=")
        data[key.strip()] = value.strip().strip('"').strip("'")
    return data


def is_fedora(ctx: Context) -> bool:
    rel = os_release(ctx)
    return rel.get("ID") == "fedora" or "fedora" in rel.get("ID_LIKE", "").split()


def kernel_release(ctx: Context) -> Optional[str]:
    rel = ctx.read_line("/proc/sys/kernel/osrelease")
    if rel:
        return rel
    if ctx.is_live:
        return platform.release() or None
    return None


def architecture(ctx: Context) -> Optional[str]:
    # /proc/sys/kernel/arch exists on newer kernels; fall back to uname.
    arch = ctx.read_line("/proc/sys/kernel/arch")
    if arch:
        return arch
    if ctx.is_live:
        return platform.machine() or None
    res = ctx.run(["uname", "-m"])
    return res.out.strip() if res.ok and res.out.strip() else None


def uptime_seconds(ctx: Context) -> Optional[float]:
    text = ctx.read_line("/proc/uptime")
    if not text:
        return None
    try:
        return float(text.split()[0])
    except (ValueError, IndexError):
        return None


def meminfo(ctx: Context) -> Dict[str, int]:
    """Return /proc/meminfo values in bytes (only the keys present)."""
    out: Dict[str, int] = {}
    for line in (ctx.read("/proc/meminfo") or "").splitlines():
        m = re.match(r"^(\w+(?:\(\w+\))?):\s+(\d+)(?:\s+kB)?", line)
        if m:
            out[m.group(1)] = int(m.group(2)) * 1024
    return out


def secure_boot(ctx: Context) -> Dict[str, str]:
    """Report Secure Boot state without ever modifying it.

    Prefers ``mokutil --sb-state`` (Fedora ships mokutil by default), falling
    back to reading the EFI variable directly: 4 attribute bytes followed by
    a single data byte, 1 = enabled.
    """
    if not ctx.isdir("/sys/firmware/efi"):
        return {"state": "unsupported", "detail": "Legacy BIOS boot (no UEFI) — Secure Boot does not apply"}

    res = ctx.run(["mokutil", "--sb-state"], timeout=5)
    text = (res.out + res.err).lower()
    if res.rc != 127 and "secureboot enabled" in text:
        return {"state": "enabled", "detail": "reported by mokutil"}
    if res.rc != 127 and "secureboot disabled" in text:
        return {"state": "disabled", "detail": "reported by mokutil"}

    raw = ctx.read_bytes(_SB_VAR)
    if raw is not None and len(raw) >= 5:
        return {
            "state": "enabled" if raw[4] == 1 else "disabled",
            "detail": "read from EFI variable",
        }
    return {"state": "unknown", "detail": "UEFI system, but SecureBoot variable unreadable and mokutil unavailable"}


def virtualization(ctx: Context) -> Optional[str]:
    res = ctx.run(["systemd-detect-virt"], timeout=5)
    value = res.out.strip()
    if res.rc == 127 or not value:
        return None
    return value  # "none" on bare metal


def hyprland_version(ctx: Context) -> Optional[str]:
    """Installed Hyprland version, from the running instance if possible."""
    res = ctx.run(["hyprctl", "version", "-j"], timeout=5)
    if res.ok:
        try:
            data = json.loads(res.out)
            tag = data.get("tag") or data.get("version") or ""
            v = parse_version(tag)
            if v:
                return ".".join(str(x) for x in v)
        except (ValueError, AttributeError):
            pass
    for argv in (["Hyprland", "--version"], ["hyprland", "--version"]):
        res = ctx.run(argv, timeout=5)
        if res.ok:
            m = re.search(r"Hyprland\s+v?(\d+\.\d+(?:\.\d+)?)", res.out) or re.search(
                r"[Tt]ag:\s*v?(\d+\.\d+(?:\.\d+)?)", res.out
            )
            if m:
                return m.group(1)
            v = parse_version(res.out)
            if v:
                return ".".join(str(x) for x in v)
    return None


def session_info(ctx: Context) -> Dict[str, Optional[str]]:
    env = ctx.env
    return {
        "sessionType": env.get("XDG_SESSION_TYPE"),
        "desktop": env.get("XDG_CURRENT_DESKTOP"),
        "hyprlandRunning": "yes" if env.get("HYPRLAND_INSTANCE_SIGNATURE") else "no",
        "waylandDisplay": env.get("WAYLAND_DISPLAY"),
    }


def summary(ctx: Context) -> Dict[str, object]:
    rel = os_release(ctx)
    mem = meminfo(ctx)
    return {
        "os": rel.get("PRETTY_NAME") or rel.get("NAME"),
        "osId": rel.get("ID"),
        "osVersion": rel.get("VERSION_ID"),
        "kernel": kernel_release(ctx),
        "architecture": architecture(ctx),
        "uptimeSeconds": uptime_seconds(ctx),
        "memoryTotal": mem.get("MemTotal"),
        "memoryAvailable": mem.get("MemAvailable"),
        "swapTotal": mem.get("SwapTotal"),
        "swapFree": mem.get("SwapFree"),
        "secureBoot": secure_boot(ctx),
        "virtualization": virtualization(ctx),
        "hyprlandVersion": hyprland_version(ctx),
        "session": session_info(ctx),
    }
