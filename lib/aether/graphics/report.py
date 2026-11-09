"""High-level graphics reports: detect, driver recommendations, verify."""

from __future__ import annotations

import os
from typing import Dict, List, Optional

from ..hw import gpu as gpu_mod
from ..hw import system
from ..util import Context, parse_version, version_at_least
from . import nvidia, stack

Check = Dict[str, str]  # {"level": pass|warn|fail|info, "text": ..., "hint": ...}


def detect(ctx: Context) -> Dict[str, object]:
    gpus = gpu_mod.detect(ctx)
    topo = gpu_mod.topology(gpus)
    per_gpu = []
    for g in gpus:
        entry = dict(g)
        if g["runtimeStatus"] == "suspended":
            # Probing a runtime-suspended dGPU would wake it up.
            entry["vaapi"] = {"status": "skipped", "error": "GPU is asleep (runtime-suspended); not probed to avoid waking it"}
        elif g["drm"].get("render"):
            entry["vaapi"] = stack.vaapi(ctx, g["drm"]["render"])
        per_gpu.append(entry)
    out: Dict[str, object] = {
        "gpus": per_gpu,
        "topology": topo,
        "kernel": system.kernel_release(ctx),
        "mesa": stack.mesa_version(ctx),
        "opengl": stack.opengl(ctx),
        "vulkan": stack.vulkan(ctx),
        "secureBoot": system.secure_boot(ctx),
        "hyprlandVersion": system.hyprland_version(ctx),
        "session": system.session_info(ctx),
    }
    if topo["hasNvidia"]:
        out["nvidia"] = nvidia.state(ctx, gpus)
    return out


def drivers(ctx: Context, check_repo: bool = True) -> List[Dict[str, object]]:
    """Per-GPU driver recommendation. Read-only: installs nothing."""
    recs = []
    fedora = system.is_fedora(ctx)
    for g in gpu_mod.detect(ctx):
        vendor = g["vendor"]
        if vendor == "nvidia":
            r = nvidia.recommend(ctx, g, check_repo=check_repo)
            r["vendor"] = "nvidia"
            r["currentDriver"] = g["driver"]
            if r.get("package"):
                r["command"] = "aether graphics install-nvidia"
            r.setdefault("codecs", [])
            if fedora and r.get("package"):
                r["codecs"] = ["libva-nvidia-driver (RPM Fusion) — VA-API video decode through NVDEC"]
            recs.append(r)
        elif vendor == "amd":
            notes = ["AMD GPUs use the in-kernel amdgpu driver and Mesa (RADV for Vulkan, radeonsi for OpenGL/VA-API). No separate driver install is needed."]
            if g["driver"] == "radeon":
                notes.append("This GPU is bound to the legacy 'radeon' driver. Southern/Sea Islands (GCN 1.0/1.1) cards can use amdgpu with the kernel parameters radeon.si_support=0 amdgpu.si_support=1 (or .cik_support) for Vulkan — change only if you need it.")
            recs.append(
                {
                    "vendor": "amd",
                    "slot": g["slot"],
                    "name": g["name"],
                    "currentDriver": g["driver"],
                    "package": None,
                    "notes": notes,
                    "codecs": (
                        ["Fedora's mesa-va-drivers omits H.264/HEVC for patent reasons. For full hardware decode: sudo dnf swap mesa-va-drivers mesa-va-drivers-freeworld (RPM Fusion free)."]
                        if fedora
                        else []
                    ),
                }
            )
        elif vendor == "intel":
            notes = ["Intel GPUs use the in-kernel i915 or xe driver and Mesa (ANV for Vulkan, iris for OpenGL). No separate driver install is needed."]
            if g["driver"] not in ("i915", "xe"):
                notes.append("Unexpected kernel driver %r bound to this GPU." % g["driver"])
            recs.append(
                {
                    "vendor": "intel",
                    "slot": g["slot"],
                    "name": g["name"],
                    "currentDriver": g["driver"],
                    "package": None,
                    "notes": notes,
                    "codecs": (
                        ["Broadwell (5th gen) and newer: sudo dnf install intel-media-driver (RPM Fusion nonfree) for the iHD VA-API driver with full codec support. Older GPUs use libva-intel-driver (i965)."]
                        if fedora
                        else []
                    ),
                }
            )
        else:
            recs.append(
                {
                    "vendor": vendor,
                    "slot": g["slot"],
                    "name": g["name"],
                    "currentDriver": g["driver"],
                    "package": None,
                    "notes": ["Virtual or uncommon display adapter — uses its in-kernel driver; nothing to install."],
                    "codecs": [],
                }
            )
    return recs


def _c(level: str, text: str, hint: str = "") -> Check:
    return {"level": level, "text": text, "hint": hint}


def verify(ctx: Context, hardware_conf: Optional[str] = None) -> List[Check]:
    checks: List[Check] = []
    gpus = gpu_mod.detect(ctx)
    topo = gpu_mod.topology(gpus)
    if not gpus:
        checks.append(_c("fail", "No display-class PCI device found", "Is this a container or a headless VM? /sys/bus/pci may not be visible."))
        return checks

    for g in gpus:
        label = "%s %s [%s]" % (g["vendorLabel"], g["name"], g["slot"])
        if g["driver"]:
            checks.append(_c("pass", "%s bound to kernel driver '%s'" % (label, g["driver"])))
        else:
            checks.append(_c("fail", "%s has no kernel driver bound" % label, "Check `journalctl -k -b | grep -iE 'drm|nvidia|amdgpu|i915|xe'`."))
        if g["drm"].get("render"):
            checks.append(_c("pass", "%s exposes render node /dev/dri/%s" % (label, g["drm"]["render"])))
        elif g["driver"]:
            checks.append(_c("warn", "%s has no DRM render node" % label, "The driver did not register with DRM; Wayland compositors cannot use this GPU."))

    session = system.session_info(ctx)
    if session.get("sessionType") == "wayland":
        checks.append(_c("pass", "Wayland session (%s)" % (session.get("desktop") or "unknown desktop")))
    elif session.get("sessionType"):
        checks.append(_c("info", "Current session type is %s, not wayland — some checks reflect that session" % session["sessionType"]))

    gl = stack.opengl(ctx)
    if gl["status"] == "ok":
        renderer = gl["renderer"] or ""
        if "llvmpipe" in renderer.lower() or "softpipe" in renderer.lower():
            checks.append(_c("fail", "OpenGL is using software rendering (%s)" % renderer, "Hardware acceleration is not active. Run `aether graphics drivers`."))
        else:
            checks.append(_c("pass", "OpenGL renderer: %s (%s)" % (renderer, gl.get("version") or "version unknown")))
    else:
        checks.append(_c("info", "OpenGL renderer not checked", gl.get("hint", "")))

    vk = stack.vulkan(ctx)
    icd_drivers = {i["driver"] for i in vk.get("icds", [])}  # type: ignore[union-attr]
    expected_icd = {"nvidia": {"nvidia", "nvk"}, "amd": {"radv", "amdvlk"}, "intel": {"anv", "hasvk"}}
    for g in gpus:
        want = expected_icd.get(g["vendor"])
        if not want:
            continue
        if g["vendor"] == "nvidia" and g["driver"] == "nouveau":
            want = {"nvk"}
        if icd_drivers & want:
            checks.append(_c("pass", "Vulkan driver installed for %s (%s)" % (g["vendorLabel"], ", ".join(sorted(icd_drivers & want)))))
        else:
            pkg = {"amd": "mesa-vulkan-drivers", "intel": "mesa-vulkan-drivers", "nvidia": "xorg-x11-drv-nvidia (via akmod-nvidia)"}[g["vendor"]]
            checks.append(_c("warn", "No Vulkan ICD for %s" % g["vendorLabel"], "Install %s." % pkg))
    if vk.get("status") == "ok":
        names = ", ".join(d.get("deviceName", "?") for d in vk.get("devices", []))  # type: ignore[union-attr]
        if "llvmpipe" in names.lower() and not any("llvmpipe" not in d.get("deviceName", "").lower() for d in vk["devices"]):  # type: ignore[index]
            checks.append(_c("fail", "Vulkan only exposes the software rasterizer (llvmpipe)"))
        else:
            checks.append(_c("pass", "Vulkan devices: %s" % names))
    elif vk.get("status") == "icds-only":
        checks.append(_c("info", "Vulkan devices not enumerated", str(vk.get("hint", ""))))

    for g in gpus:
        render = g["drm"].get("render")
        if not render or g["runtimeStatus"] == "suspended" or g["vendor"] not in ("nvidia", "amd", "intel"):
            continue
        va = stack.vaapi(ctx, render)
        if va["status"] == "ok":
            checks.append(_c("pass", "VA-API on %s: decode %s" % (g["vendorLabel"], ", ".join(va["decode"]) or "none")))  # type: ignore[arg-type]
            if g["vendor"] in ("amd", "intel") and "H.264" not in va["decode"] and system.is_fedora(ctx):  # type: ignore[operator]
                checks.append(_c("warn", "No H.264 hardware decode on %s" % g["vendorLabel"], "See `aether graphics drivers` for the RPM Fusion codec package."))
        elif va["status"] == "not-checked":
            checks.append(_c("info", "VA-API not checked for %s" % g["vendorLabel"], str(va.get("hint", ""))))
        else:
            checks.append(_c("warn", "VA-API unavailable on %s (%s)" % (g["vendorLabel"], va.get("error") or va["status"]), "See `aether graphics drivers` for codec packages."))

    if topo["hasNvidia"]:
        checks.extend(_verify_nvidia(ctx, gpus, topo))

    if topo["hybrid"]:
        checks.append(_c("info", "Hybrid graphics: %s (boot) + %s" % (
            ", ".join(topo["integratedSlots"]) or "?", ", ".join(topo["discreteSlots"]) or "?"),
            "Desktop renders on the integrated GPU; run apps on the discrete GPU with `aether gpu run <command>`."))
        if hardware_conf and os.path.isfile(hardware_conf):
            with open(hardware_conf, "r", encoding="utf-8", errors="replace") as fh:
                text = fh.read()
            active = [l for l in text.splitlines() if l.strip() and not l.strip().startswith("#")]
            if any("__GLX_VENDOR_LIBRARY_NAME,nvidia" in l.replace(" ", "") for l in active):
                checks.append(_c("warn", "hardware.conf forces NVIDIA GLX globally on a hybrid system", "This keeps the dGPU awake and can break apps on the iGPU. Regenerate with `aether graphics configure`."))
    return checks


def _verify_nvidia(ctx: Context, gpus, topo) -> List[Check]:
    checks: List[Check] = []
    st = nvidia.state(ctx, gpus)
    sb = system.secure_boot(ctx)
    hypr = parse_version(system.hyprland_version(ctx))

    if st["nouveauLoaded"] and any(st["packages"].get(p) for p in ("akmod-nvidia", "akmod-nvidia-580xx")):  # type: ignore[union-attr]
        checks.append(_c("fail", "nouveau is loaded although the NVIDIA driver package is installed", "The proprietary module was not used at boot. Usually means the module was not built or was rejected (see below)."))

    if st["moduleLoaded"]:
        checks.append(_c("pass", "NVIDIA kernel module loaded (driver %s)" % (st["driverVersion"] or "version unknown")))
    elif st["nouveauLoaded"]:
        checks.append(_c("info", "NVIDIA GPU is driven by nouveau (open-source)", "For the proprietary driver: `aether graphics drivers`."))
    else:
        if st["moduleBuiltForRunningKernel"]:
            if sb["state"] == "enabled":
                checks.append(_c("fail", "NVIDIA module is built (%s) but not loaded, and Secure Boot is enabled" % st["moduleBuiltForRunningKernel"],
                                 "The module is most likely unsigned or signed with a key the firmware doesn't trust. "
                                 "Enroll the akmods key: sudo mokutil --import %s, reboot, choose 'Enroll MOK'. "
                                 "See docs/NVIDIA_GUIDE.md#secure-boot." % nvidia.AKMODS_KEY))
            else:
                checks.append(_c("fail", "NVIDIA module is built (%s) but not loaded" % st["moduleBuiltForRunningKernel"], "Reboot, then check `journalctl -k -b | grep -i nvidia`."))
        elif any(st["packages"].values()):  # type: ignore[union-attr]
            checks.append(_c("fail", "NVIDIA packages installed but no module exists for kernel %s" % st["kernel"],
                             "Build it: sudo akmods --force --kernels %s  (logs: /var/cache/akmods/nvidia/)" % st["kernel"]))
        else:
            checks.append(_c("info", "Proprietary NVIDIA driver not installed", "Run `aether graphics drivers` for the recommended package."))

    for log in st["akmodsFailedLogs"]:  # type: ignore[union-attr]
        checks.append(_c("fail", "akmods build failure log: %s" % log, "Read the end of the log; usually missing kernel-devel for the running kernel."))

    if sb["state"] == "enabled" and st["moduleBuiltForRunningKernel"]:
        key = st["akmodsKey"]
        if key.get("enrolled") == "yes":  # type: ignore[union-attr]
            checks.append(_c("pass", "Secure Boot enabled and akmods signing key enrolled"))
        elif key.get("enrolled") == "no":  # type: ignore[union-attr]
            checks.append(_c("fail", "Secure Boot enabled but the akmods signing key is NOT enrolled",
                             "sudo mokutil --import %s, reboot, complete 'Enroll MOK'." % nvidia.AKMODS_KEY))
        if not st["moduleSigner"]:
            checks.append(_c("warn", "The built nvidia module carries no signature", "Rebuild after creating the key: sudo kmodgenca -a && sudo akmods --force"))

    if st["moduleLoaded"]:
        if st["drmModeset"] == "Y":
            checks.append(_c("pass", "nvidia_drm modeset enabled (required for Wayland)"))
        elif st["drmModeset"] is not None:
            checks.append(_c("fail", "nvidia_drm modeset is disabled", "Hyprland requires it. Add nvidia-drm.modeset=1 to the kernel command line: sudo grubby --update-kernel=ALL --args='nvidia-drm.modeset=1'"))
        if st["drmFbdev"] == "Y":
            checks.append(_c("pass", "nvidia_drm fbdev enabled"))
        elif st["drmFbdev"] == "N":
            checks.append(_c("info", "nvidia_drm fbdev disabled", "Recommended on driver 545+ for a working VT console: nvidia-drm.fbdev=1"))
        if st["gbmBackend"]:
            checks.append(_c("pass", "NVIDIA GBM backend present"))
        else:
            checks.append(_c("warn", "NVIDIA GBM backend (nvidia-drm_gbm.so) not found", "Wayland compositors need GBM; reinstall xorg-x11-drv-nvidia."))
        if st["explicitSyncCapable"]:
            if hypr is None:
                checks.append(_c("pass", "Driver supports explicit sync (555+); Hyprland version unknown"))
            elif version_at_least(hypr, (0, 42)):
                checks.append(_c("pass", "Explicit sync available (driver 555+, Hyprland %s)" % ".".join(map(str, hypr))))
            else:
                checks.append(_c("warn", "Driver supports explicit sync but Hyprland %s predates it (0.42+)" % ".".join(map(str, hypr)), "Update Hyprland to avoid flicker."))
        else:
            checks.append(_c("warn", "Driver %s predates explicit sync (555+)" % st["driverVersion"], "Expect flicker in some XWayland apps; update the driver."))
        if st["preserveVideoMemory"] == "1":
            checks.append(_c("pass", "PreserveVideoMemoryAllocations enabled (suspend/resume safe)"))
        elif st["preserveVideoMemory"] is not None:
            checks.append(_c("warn", "PreserveVideoMemoryAllocations disabled", "Wayland sessions can come back corrupted after suspend. RPM Fusion's xorg-x11-drv-nvidia-power package enables it together with nvidia-suspend/resume services."))
        if st["suspendService"].get("enabled") == "enabled":  # type: ignore[union-attr]
            checks.append(_c("pass", "nvidia-suspend.service enabled"))
        elif st["suspendService"].get("enabled") is not None:  # type: ignore[union-attr]
            checks.append(_c("warn", "nvidia-suspend.service not enabled (%s)" % st["suspendService"]["enabled"], "sudo systemctl enable nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service"))  # type: ignore[index]
        p = st["persistenced"]
        if p.get("active"):  # type: ignore[union-attr]
            checks.append(_c("info", "nvidia-persistenced: %s/%s" % (p.get("enabled"), p.get("active")), "Only useful for compute/headless workloads; not required on a desktop."))  # type: ignore[union-attr]

    if st["nvidiaSmi"]:
        checks.append(_c("pass", "nvidia-smi available (panel GPU telemetry enabled)"))
    elif st["moduleLoaded"]:
        checks.append(_c("warn", "nvidia-smi not installed — GPU usage/temperature will show as unavailable", "sudo dnf install xorg-x11-drv-nvidia-cuda"))
    if st["cudaDriverLibrary"]:
        checks.append(_c("pass", "CUDA driver library (libcuda.so.1) present" + (" + nvcc toolkit" if st["nvcc"] else "")))
    elif st["moduleLoaded"]:
        checks.append(_c("info", "CUDA driver library not found", "sudo dnf install xorg-x11-drv-nvidia-cuda"))

    if topo["hybrid"]:
        for g in st["gpus"]:  # type: ignore[union-attr]
            if g["runtimeStatus"] == "suspended":
                checks.append(_c("pass", "Discrete NVIDIA GPU is runtime-suspended (power saving works)"))
            elif g["runtimeStatus"] == "active":
                checks.append(_c("info", "Discrete NVIDIA GPU is currently awake", "Normal while an app uses it; if it never sleeps, check `aether gpu` for processes on the dGPU."))
    return checks
