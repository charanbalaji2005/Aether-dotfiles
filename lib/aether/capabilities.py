"""Graphics capability summary for the shell's effects engine.

Answers one question: *how much visual work is this machine comfortable
with?* — from facts already in sysfs/procfs. It never runs a GPU tool
(nvidia-smi, vulkaninfo, glxinfo): on a hybrid laptop those wake the
discrete GPU, and waking a GPU to decide how pretty an animation should be
is exactly the thing this module exists to prevent.

The result is a *recommendation*. The shell combines it with the user's
setting, the power state and measured frame times (PerformanceService).
"""

from __future__ import annotations

import json
from typing import Any, Dict, List

from .hw import gpu as gpu_mod
from .hw import system
from .util import Context

TIERS = ("eco", "balanced", "ultra")
_SOFTWARE_DRIVERS = {"", "vgem", "bochs-drm", "simpledrm", "simple-framebuffer", "cirrus"}
_VIRTUAL_VENDORS = {"virtio", "vmware", "qemu", "qxl", "virtualbox", "microsoft"}


def _refresh_rates(ctx: Context) -> List[float]:
    if not ctx.env.get("HYPRLAND_INSTANCE_SIGNATURE") or not ctx.which("hyprctl"):
        return []
    res = ctx.run(["hyprctl", "-j", "monitors"], timeout=5)
    if not res.ok:
        return []
    try:
        return [round(float(m.get("refreshRate", 0)), 2) for m in json.loads(res.out) if m.get("refreshRate")]
    except (ValueError, TypeError, AttributeError):
        return []


def summary(ctx: Context) -> Dict[str, Any]:
    gpus = gpu_mod.detect(ctx)
    topo = gpu_mod.topology(gpus)
    mem_bytes = system.meminfo(ctx).get("MemTotal", 0)  # meminfo() returns bytes
    mem_gb = mem_bytes / float(1 << 30) if mem_bytes else 0.0
    reasons: List[str] = []
    tier = "balanced"
    shaders = True

    real = [g for g in gpus if g["vendor"] not in _VIRTUAL_VENDORS]
    # The GPU that draws the desktop: the boot display, except on hybrid
    # laptops where AetherOS deliberately keeps the desktop on the iGPU.
    desktop = None
    if topo.get("hybrid"):
        desktop = next((g for g in gpus if g["kind"] == "integrated"), None)
    if desktop is None:
        desktop = next((g for g in gpus if g["bootVga"]), gpus[0] if gpus else None)

    forced_sw = ctx.env.get("LIBGL_ALWAYS_SOFTWARE") in ("1", "true") or ctx.env.get("QT_QUICK_BACKEND") == "software"
    if forced_sw:
        tier, shaders = "eco", False
        reasons.append("Software rendering is forced by the environment.")
    elif not gpus:
        tier, shaders = "eco", False
        reasons.append("No GPU was detected; assuming software rendering.")
    elif not real:
        tier = "eco"
        reasons.append("Virtual machine GPU (%s): effects kept light." % gpus[0]["vendorLabel"])
    elif desktop is not None and (desktop["driver"] or "") in _SOFTWARE_DRIVERS:
        tier, shaders = "eco", False
        reasons.append("%s has no accelerated driver bound." % desktop["name"])
    elif desktop is not None and desktop["driver"] == "nouveau":
        tier = "eco"
        reasons.append("NVIDIA GPU on nouveau: limited acceleration (see `aether graphics drivers`).")
    elif topo.get("hybrid"):
        tier = "balanced"
        reasons.append("Hybrid graphics: the desktop renders on the integrated GPU and the discrete GPU is left asleep.")
    elif desktop is not None and desktop["kind"] == "discrete":
        tier = "ultra"
        reasons.append("%s drives the desktop." % desktop["name"])
    else:
        tier = "balanced"
        reasons.append("Integrated graphics (%s)." % (desktop["name"] if desktop else "unknown"))

    if mem_gb and mem_gb < 3.5:
        tier = "eco"
        reasons.append("%.1f GiB of memory: effects kept light." % mem_gb)
    elif mem_gb and mem_gb < 7.5 and tier == "ultra":
        tier = "balanced"
        reasons.append("%.1f GiB of memory: 'ultra' not recommended." % mem_gb)

    rates = _refresh_rates(ctx)
    return {
        "tier": tier,
        "shaders": shaders,
        "reasons": reasons,
        "hybrid": bool(topo.get("hybrid")),
        "layout": topo.get("layout"),
        "desktopGpu": {"name": desktop["name"], "vendor": desktop["vendor"], "driver": desktop["driver"],
                       "kind": desktop["kind"]} if desktop else None,
        "gpus": [{"name": g["name"], "vendor": g["vendor"], "driver": g["driver"], "kind": g["kind"],
                  "runtimeStatus": g["runtimeStatus"]} for g in gpus],
        "memoryGiB": round(mem_gb, 1) if mem_gb else None,
        "refreshRates": rates,
        "maxRefresh": max(rates) if rates else None,
        "safeMode": False,
    }
