"""Userspace graphics-stack probes shared by every vendor: Mesa, OpenGL/EGL,
Vulkan and VA-API.

Each probe distinguishes three outcomes, because they mean different things
to the user:

* the probe tool is missing      -> "not checked" + which package provides it
* the tool ran and found nothing -> a real negative result
* the tool ran and found support -> details

Nothing here guesses: if no tool can answer, the answer is ``None``.
"""

from __future__ import annotations

import json
import re
from typing import Dict, List, Optional

from ..util import Context

# Fedora package that provides each probe tool.
PROBE_PACKAGES = {
    "vulkaninfo": "vulkan-tools",
    "vainfo": "libva-utils",
    "glxinfo": "glx-utils",
    "eglinfo": "egl-utils",
    "nvidia-smi": "xorg-x11-drv-nvidia-cuda (RPM Fusion)",
}

_LIBDIRS = ("/usr/lib64", "/usr/lib", "/usr/lib/x86_64-linux-gnu", "/usr/lib/aarch64-linux-gnu")


def mesa_version(ctx: Context) -> Optional[str]:
    res = ctx.run(["rpm", "-q", "--qf", "%{VERSION}", "mesa-dri-drivers"], timeout=10)
    if res.ok and res.out.strip() and "not installed" not in res.out:
        return res.out.strip()
    return None


def opengl(ctx: Context) -> Dict[str, Optional[str]]:
    """OpenGL renderer/version via eglinfo (Wayland-native) or glxinfo."""
    for tool, argv in (("eglinfo", ["eglinfo", "-B"]), ("glxinfo", ["glxinfo", "-B"])):
        if not ctx.which(tool):
            continue
        res = ctx.run(argv, timeout=10)
        if not res.ok:
            continue
        renderer = version = vendor = None
        for line in res.out.splitlines():
            line = line.strip()
            if line.startswith("OpenGL renderer string:") and renderer is None:
                renderer = line.split(":", 1)[1].strip()
            elif line.startswith("OpenGL core profile version string:") and version is None:
                version = line.split(":", 1)[1].strip()
            elif line.startswith("OpenGL version string:") and version is None:
                version = line.split(":", 1)[1].strip()
            elif line.startswith("OpenGL vendor string:") and vendor is None:
                vendor = line.split(":", 1)[1].strip()
        if renderer:
            return {"status": "ok", "tool": tool, "renderer": renderer, "version": version, "vendor": vendor}
        return {"status": "no-renderer", "tool": tool, "renderer": None, "version": None, "vendor": None}
    return {
        "status": "not-checked",
        "tool": None,
        "renderer": None,
        "version": None,
        "vendor": None,
        "hint": "install egl-utils or glx-utils to check the OpenGL renderer",
    }


def vulkan_icds(ctx: Context) -> List[Dict[str, str]]:
    """Installed Vulkan ICD manifests (driver registrations)."""
    icds = []
    for d in ("/usr/share/vulkan/icd.d", "/etc/vulkan/icd.d"):
        for f in ctx.listdir(d):
            if not f.endswith(".json"):
                continue
            text = ctx.read(d + "/" + f) or "{}"
            try:
                lib = json.loads(text).get("ICD", {}).get("library_path", "")
            except ValueError:
                lib = ""
            icds.append({"file": f, "library": lib, "driver": _icd_driver(f)})
    return icds


def _icd_driver(filename: str) -> str:
    f = filename.lower()
    if f.startswith("nvidia"):
        return "nvidia"
    if f.startswith("radeon"):
        return "radv"
    if f.startswith("intel_hasvk"):
        return "hasvk"
    if f.startswith("intel"):
        return "anv"
    if f.startswith("nouveau"):
        return "nvk"
    if f.startswith("lvp"):
        return "lavapipe (software)"
    if f.startswith("amd"):
        return "amdvlk"
    return f.rsplit(".", 2)[0]


def vulkan(ctx: Context) -> Dict[str, object]:
    icds = vulkan_icds(ctx)
    result: Dict[str, object] = {"icds": icds, "devices": [], "status": "not-checked"}
    if not ctx.which("vulkaninfo"):
        result["hint"] = "install vulkan-tools to enumerate Vulkan devices"
        result["status"] = "icds-only" if icds else "none"
        return result
    res = ctx.run(["vulkaninfo", "--summary"], timeout=20)
    if not res.ok:
        result["status"] = "error"
        result["error"] = (res.err or res.out).strip().splitlines()[-1:] or ["vulkaninfo failed"]
        return result
    devices = []
    current: Dict[str, str] = {}
    for line in res.out.splitlines():
        m = re.match(r"\s*(deviceName|deviceType|driverName|driverInfo|apiVersion|driverID)\s*=\s*(.+)", line)
        if m:
            key, val = m.group(1), m.group(2).strip()
            if key == "apiVersion" and current.get("deviceName"):
                devices.append(current)
                current = {}
            current[key] = val
    if current.get("deviceName"):
        devices.append(current)
    result["devices"] = devices
    result["status"] = "ok" if devices else "no-devices"
    return result


def vaapi(ctx: Context, render_node: Optional[str] = None) -> Dict[str, object]:
    """VA-API driver and decode/encode profiles for a render node."""
    drivers = []
    for libdir in _LIBDIRS:
        for f in ctx.listdir(libdir + "/dri"):
            if f.endswith("_drv_video.so"):
                drivers.append(f.replace("_drv_video.so", ""))
    out: Dict[str, object] = {"installedDrivers": sorted(set(drivers)), "status": "not-checked"}
    if not ctx.which("vainfo"):
        out["hint"] = "install libva-utils to check hardware video acceleration"
        return out
    argv = ["vainfo"]
    if render_node:
        argv += ["--display", "drm", "--device", "/dev/dri/" + render_node]
    res = ctx.run(argv, timeout=10)
    text = res.out + "\n" + res.err
    m = re.search(r"Driver version:\s*(.+)", text)
    decode, encode = set(), set()
    for line in text.splitlines():
        pm = re.match(r"\s*VAProfile(\w+)\s*:\s*VAEntrypoint(\w+)", line)
        if not pm:
            continue
        profile, entry = pm.group(1), pm.group(2)
        codec = _codec_family(profile)
        if codec is None:
            continue
        if entry == "VLD":
            decode.add(codec)
        elif entry.startswith("Enc"):
            encode.add(codec)
    out.update(
        {
            "status": "ok" if (res.ok and (decode or encode)) else ("no-profiles" if res.ok else "error"),
            "driver": m.group(1).strip() if m else None,
            "decode": sorted(decode),
            "encode": sorted(encode),
        }
    )
    if not res.ok:
        tail = [l for l in text.strip().splitlines() if l.strip()][-1:]
        out["error"] = tail[0] if tail else "vainfo failed"
    return out


def _codec_family(profile: str) -> Optional[str]:
    p = profile.lower()
    for prefix, name in (
        ("h264", "H.264"),
        ("hevc", "HEVC"),
        ("av1", "AV1"),
        ("vp9", "VP9"),
        ("vp8", "VP8"),
        ("mpeg2", "MPEG-2"),
        ("vc1", "VC-1"),
        ("jpeg", "JPEG"),
    ):
        if p.startswith(prefix):
            return name
    return None


def library_present(ctx: Context, soname: str) -> bool:
    res = ctx.run(["ldconfig", "-p"], timeout=10)
    if res.ok:
        return soname in res.out
    return any(ctx.exists(d + "/" + soname) for d in _LIBDIRS)


def rpm_installed(ctx: Context, *packages: str) -> Dict[str, Optional[str]]:
    """Map package -> installed version-release, None if absent.

    Returns an empty dict when rpm itself is unavailable (non-RPM distro),
    so callers can tell "not installed" from "can't tell".
    """
    if not ctx.which("rpm"):
        return {}
    out: Dict[str, Optional[str]] = {}
    for pkg in packages:
        res = ctx.run(["rpm", "-q", "--qf", "%{VERSION}-%{RELEASE}", pkg], timeout=10)
        out[pkg] = res.out.strip() if res.ok and "not installed" not in res.out else None
    return out


def kernel_module_loaded(ctx: Context, name: str) -> bool:
    return ctx.isdir("/sys/module/" + name)
