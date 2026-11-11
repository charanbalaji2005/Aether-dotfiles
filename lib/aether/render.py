"""Rendering diagnostics: which graphics APIs and drivers the desktop can use.

Default mode reads *files only* — environment, GLVND EGL vendor files, Vulkan
ICD manifests, VA-API drivers, the GPU the compositor was pinned to — so it is
safe on a hybrid laptop (nothing touches a sleeping dGPU). `probe=True` also
runs eglinfo / vulkaninfo, which load drivers and may wake a discrete GPU; the
CLI says so before doing it.

Nothing here changes configuration. Qt Quick's backend is never forced: the
report only explains what Qt will pick and why something is unavailable.
"""

from __future__ import annotations

import glob
import json
import os
import re
from typing import Any, Dict, List

from .util import Context

EGL_VENDOR_DIRS = ("/usr/share/glvnd/egl_vendor.d", "/etc/glvnd/egl_vendor.d")
VULKAN_ICD_DIRS = ("/usr/share/vulkan/icd.d", "/etc/vulkan/icd.d")
VAAPI_DIRS = ("/usr/lib64/dri", "/usr/lib/x86_64-linux-gnu/dri", "/usr/lib/dri", "/usr/lib64/dri-nonfree", "/usr/lib64/dri-freeworld")


def _json_files(ctx: Context, dirs) -> List[Dict[str, Any]]:
    out = []
    for d in dirs:
        for path in sorted(ctx.glob(d + "/*.json")):
            try:
                data = json.loads(ctx.read(path) or "{}")
            except ValueError:
                data = {}
            out.append({"file": os.path.basename(path), "data": data})
    return out


def _vendor_of(name: str) -> str:
    n = name.lower()
    for key, vendor in (("nvidia", "nvidia"), ("radeon", "amd"), ("amd", "amd"), ("intel", "intel"),
                        ("lvp", "software"), ("lavapipe", "software"), ("mesa", "mesa"), ("nouveau", "nouveau"),
                        ("virtio", "virtual"), ("dzn", "other")):
        if key in n:
            return vendor
    return "other"


def report(ctx: Context, probe: bool = False) -> Dict[str, Any]:
    env = ctx.env
    notes: List[str] = []
    egl = _json_files(ctx, EGL_VENDOR_DIRS)
    egl_vendors = sorted({_vendor_of(e["data"].get("ICD", {}).get("library_path", e["file"])) for e in egl})
    vk = _json_files(ctx, VULKAN_ICD_DIRS)
    vk_icds = [{"file": e["file"], "library": e["data"].get("ICD", {}).get("library_path", ""),
                "vendor": _vendor_of(e["file"] + " " + e["data"].get("ICD", {}).get("library_path", ""))} for e in vk]
    vaapi = sorted({os.path.basename(p)[:-len("_drv_video.so")] for d in VAAPI_DIRS for p in ctx.glob(d + "/*_drv_video.so")})

    forced_backend = env.get("QSG_RHI_BACKEND") or ""
    software = env.get("QT_QUICK_BACKEND") == "software" or env.get("LIBGL_ALWAYS_SOFTWARE") in ("1", "true")
    qt_backends = {
        "opengl": {"available": bool(egl), "why": "" if egl else "no EGL vendor library (install mesa-libEGL, or the NVIDIA driver)"},
        "vulkan": {"available": any(i["vendor"] not in ("software",) for i in vk_icds),
                   "why": "" if vk_icds else "no Vulkan ICD installed (mesa-vulkan-drivers, or the NVIDIA driver)"},
        "software": {"available": True, "why": "always available (slow; shaders and particles disabled)"},
    }
    if qt_backends["vulkan"]["available"] is False and vk_icds:
        qt_backends["vulkan"]["why"] = "only a software Vulkan driver (lavapipe) is installed"
    effective = "software" if software else (forced_backend or "opengl")
    if forced_backend:
        notes.append("QSG_RHI_BACKEND=%s is set in the environment; Qt Quick uses it." % forced_backend)
    else:
        notes.append("Qt Quick uses OpenGL (its Linux default). AetherOS does not force a backend.")
    if software:
        notes.append("Software rendering is forced (QT_QUICK_BACKEND/LIBGL_ALWAYS_SOFTWARE): shader effects are off.")
    if effective == "vulkan" and not qt_backends["vulkan"]["available"]:
        notes.append("QSG_RHI_BACKEND=vulkan but no hardware Vulkan driver: Qt will fail or fall back.")

    # The GPU the compositor renders on (pinned by `aether graphics configure`).
    drm = env.get("AQ_DRM_DEVICES") or env.get("WLR_DRM_DEVICES") or ""
    prime = {k: env[k] for k in ("DRI_PRIME", "__NV_PRIME_RENDER_OFFLOAD", "__GLX_VENDOR_LIBRARY_NAME", "__EGL_VENDOR_LIBRARY_FILENAMES", "GBM_BACKEND") if env.get(k)}
    if prime.get("__NV_PRIME_RENDER_OFFLOAD") == "1" or prime.get("DRI_PRIME") == "1":
        notes.append("PRIME render offload is set for the whole session: every app (and the shell) renders on the dGPU, which keeps it awake. Prefer per-app offload (`aether gpu run <app>`).")

    out: Dict[str, Any] = {
        "qtBackends": qt_backends, "effectiveBackend": effective, "forcedBackend": forced_backend or None,
        "eglVendors": egl_vendors, "vulkanIcds": vk_icds, "vaapiDrivers": vaapi,
        "compositorDrmDevices": drm.split(":") if drm else [], "primeEnv": prime,
        "wayland": bool(env.get("WAYLAND_DISPLAY")), "notes": notes, "probed": False,
    }
    if probe:
        out["probed"] = True
        out["egl"] = _probe_egl(ctx)
        out["vulkan"] = _probe_vulkan(ctx)
    return out


def _probe_egl(ctx: Context) -> Dict[str, Any]:
    if not ctx.which("eglinfo"):
        return {"available": False, "why": "eglinfo not installed (sudo dnf install egl-utils)"}
    res = ctx.run(["eglinfo", "-B"], timeout=15)
    if not res.ok:
        return {"available": False, "why": (res.err or "eglinfo failed").strip().splitlines()[-1]}
    platforms = []
    current = None
    for line in res.out.splitlines():
        m = re.match(r"^(\w[\w ]*) platform:", line)
        if m:
            current = {"platform": m.group(1).strip(), "renderer": None, "version": None}
            platforms.append(current)
        elif current is not None:
            r = re.match(r"^\s*OpenGL (core profile )?renderer:\s*(.+)$", line)
            v = re.match(r"^\s*OpenGL (core profile )?version:\s*(.+)$", line)
            if r and current["renderer"] is None:
                current["renderer"] = r.group(2).strip()
            if v and current["version"] is None:
                current["version"] = v.group(2).strip()
    return {"available": True, "platforms": platforms}


def _probe_vulkan(ctx: Context) -> Dict[str, Any]:
    if not ctx.which("vulkaninfo"):
        return {"available": False, "why": "vulkaninfo not installed (sudo dnf install vulkan-tools)"}
    res = ctx.run(["vulkaninfo", "--summary"], timeout=20)
    if not res.ok:
        return {"available": False, "why": (res.err or "vulkaninfo failed").strip().splitlines()[-1] if (res.err or "").strip() else "vulkaninfo failed"}
    devices, cur = [], None
    for line in res.out.splitlines():
        if re.match(r"^GPU\d+:", line.strip()):
            cur = {}
            devices.append(cur)
        elif cur is not None:
            m = re.match(r"^\s*(apiVersion|driverName|driverInfo|deviceName|deviceType)\s*=\s*(.+)$", line)
            if m:
                cur[m.group(1)] = m.group(2).strip()
    api = re.search(r"Vulkan Instance Version:\s*(\S+)", res.out)
    return {"available": True, "instanceVersion": api.group(1) if api else None, "devices": devices}
