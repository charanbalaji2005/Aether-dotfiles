"""NVIDIA driver state, driver-branch selection and the Fedora install plan.

Design rules (see docs/NVIDIA_GUIDE.md for the user-facing version):

* The driver branch is chosen from the GPU's *chip code name* (GA104,
  TU116, GP106, ...) which lspci/pci.ids report, never assumed.
* Unknown or unsupported GPUs are never auto-installed.
* Secure Boot is detected and explained; it is never disabled.
* Installation is a plan of explicit commands, each shown before it runs,
  executed only after the user types a confirmation word.
"""

from __future__ import annotations

import os
import re
from typing import Dict, List, Optional

from ..hw import gpu as gpu_mod
from ..hw import system
from ..util import Context, parse_version
from . import stack

# Architecture by chip code-name prefix.
_ARCH_BY_PREFIX = [
    ("GB", "Blackwell"),
    ("GH", "Hopper"),
    ("AD", "Ada Lovelace"),
    ("GA", "Ampere"),
    ("TU", "Turing"),
    ("GV", "Volta"),
    ("GP", "Pascal"),
    ("GM", "Maxwell"),
    ("GK", "Kepler"),
    ("GF", "Fermi"),
]

# How each architecture maps onto RPM Fusion packages.
#   current  -> akmod-nvidia (newest branch)
#   legacy580 -> 580 is the last branch that supports these chips; prefer the
#                580xx legacy package when the repo provides it
#   legacy470 -> 470xx legacy: no GBM support, so it cannot drive Hyprland
#   none     -> no maintained proprietary driver
SUPPORT = {
    "Blackwell": "current",
    "Hopper": "current",
    "Ada Lovelace": "current",
    "Ampere": "current",
    "Turing": "current",
    "Volta": "legacy580",
    "Pascal": "legacy580",
    "Maxwell": "legacy580",
    "Kepler": "legacy470",
    "Fermi": "none",
}

AKMODS_KEY = "/etc/pki/akmods/certs/public_key.der"
RPMFUSION_FREE = "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-{ver}.noarch.rpm"
RPMFUSION_NONFREE = "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-{ver}.noarch.rpm"


def architecture(codename: Optional[str]) -> Optional[str]:
    if not codename:
        return None
    for prefix, arch in _ARCH_BY_PREFIX:
        if codename.upper().startswith(prefix):
            return arch
    return None


def driver_version(ctx: Context) -> Optional[str]:
    v = ctx.read_line("/sys/module/nvidia/version")
    if v:
        return v
    text = ctx.read("/proc/driver/nvidia/version") or ""
    m = re.search(r"Kernel Module(?: for [\w_]+)?\s+(\d+\.\d+(?:\.\d+)?)", text)
    return m.group(1) if m else None


def module_built_version(ctx: Context) -> Optional[str]:
    """Version of the nvidia module built for the *running* kernel, if any."""
    res = ctx.run(["modinfo", "-F", "version", "nvidia"], timeout=10)
    if res.ok and res.out.strip():
        return res.out.strip().splitlines()[0]
    return None


def module_signer(ctx: Context) -> Optional[str]:
    res = ctx.run(["modinfo", "-F", "signer", "nvidia"], timeout=10)
    if not res.ok:
        return None
    return res.out.strip() or None


def akmods_failure_logs(ctx: Context, kernel: Optional[str]) -> List[str]:
    logs = []
    for f in ctx.listdir("/var/cache/akmods/nvidia"):
        if f.endswith(".failed.log") and (kernel is None or kernel in f):
            logs.append("/var/cache/akmods/nvidia/" + f)
    return logs


def akmods_key_status(ctx: Context) -> Dict[str, Optional[str]]:
    if not ctx.exists(AKMODS_KEY):
        return {"key": None, "enrolled": None}
    res = ctx.run(["mokutil", "--test-key", AKMODS_KEY], timeout=10)
    text = (res.out + res.err).lower()
    if "already enrolled" in text:
        enrolled = "yes"
    elif "not enrolled" in text:
        enrolled = "no"
    else:
        enrolled = None
    return {"key": AKMODS_KEY, "enrolled": enrolled}


def module_param(ctx: Context, module: str, param: str) -> Optional[str]:
    return ctx.read_line("/sys/module/%s/parameters/%s" % (module, param))


def driver_param(ctx: Context, name: str) -> Optional[str]:
    """Read a value from /proc/driver/nvidia/params (e.g. PreserveVideoMemoryAllocations)."""
    for line in (ctx.read("/proc/driver/nvidia/params") or "").splitlines():
        key, sep, value = line.partition(":")
        if sep and key.strip() == name:
            return value.strip()
    return None


def systemd_unit_state(ctx: Context, unit: str) -> Dict[str, Optional[str]]:
    enabled = ctx.run(["systemctl", "is-enabled", unit], timeout=5)
    active = ctx.run(["systemctl", "is-active", unit], timeout=5)
    if enabled.rc == 127:
        return {"enabled": None, "active": None}
    return {
        "enabled": (enabled.out.strip() or None),
        "active": (active.out.strip() or None),
    }


def gbm_backend_present(ctx: Context) -> bool:
    return any(ctx.exists(d + "/gbm/nvidia-drm_gbm.so") for d in ("/usr/lib64", "/usr/lib", "/usr/lib/x86_64-linux-gnu"))


def state(ctx: Context, gpus: Optional[List[gpu_mod.GPU]] = None) -> Dict[str, object]:
    """Everything known about the NVIDIA driver stack on this machine."""
    gpus = gpus if gpus is not None else gpu_mod.detect(ctx)
    nv = [g for g in gpus if g["vendor"] == "nvidia"]
    kernel = system.kernel_release(ctx)
    pkgs = stack.rpm_installed(
        ctx,
        "akmod-nvidia",
        "akmod-nvidia-580xx",
        "akmod-nvidia-470xx",
        "xorg-x11-drv-nvidia",
        "xorg-x11-drv-nvidia-cuda",
        "xorg-x11-drv-nvidia-power",
        "libva-nvidia-driver",
        "nvidia-vaapi-driver",
    )
    loaded = stack.kernel_module_loaded(ctx, "nvidia")
    version = driver_version(ctx) if loaded else None
    built = module_built_version(ctx)
    ver_tuple = parse_version(version or built)
    info: Dict[str, object] = {
        "gpus": [
            {
                "slot": g["slot"],
                "name": g["name"],
                "codename": g.get("codename"),
                "architecture": architecture(g.get("codename")),
                "driver": g["driver"],
                "runtimeStatus": g["runtimeStatus"],
            }
            for g in nv
        ],
        "kernel": kernel,
        "packages": pkgs,
        "moduleLoaded": loaded,
        "nouveauLoaded": stack.kernel_module_loaded(ctx, "nouveau"),
        "driverVersion": version,
        "moduleBuiltForRunningKernel": built,
        "moduleSigner": module_signer(ctx) if built else None,
        "akmodsFailedLogs": akmods_failure_logs(ctx, kernel),
        "akmodsKey": akmods_key_status(ctx),
        "drmModeset": module_param(ctx, "nvidia_drm", "modeset"),
        "drmFbdev": module_param(ctx, "nvidia_drm", "fbdev"),
        "gbmBackend": gbm_backend_present(ctx),
        "preserveVideoMemory": driver_param(ctx, "PreserveVideoMemoryAllocations"),
        "persistenced": systemd_unit_state(ctx, "nvidia-persistenced.service"),
        "suspendService": systemd_unit_state(ctx, "nvidia-suspend.service"),
        "nvidiaSmi": bool(ctx.which("nvidia-smi")),
        "cudaDriverLibrary": stack.library_present(ctx, "libcuda.so.1"),
        "nvcc": bool(ctx.which("nvcc")),
        "vulkanIcd": any(i["driver"] == "nvidia" for i in stack.vulkan_icds(ctx)),
        "explicitSyncCapable": bool(ver_tuple and ver_tuple[0] >= 555),
    }
    return info


def recommend(ctx: Context, g: gpu_mod.GPU, check_repo: bool = True) -> Dict[str, object]:
    """Pick the RPM Fusion package for one NVIDIA GPU.

    Returns ``{"package": None, ...}`` with a reason whenever the GPU must
    not be auto-installed.
    """
    codename = g.get("codename")
    arch = architecture(codename)
    rec: Dict[str, object] = {
        "slot": g["slot"],
        "name": g["name"],
        "codename": codename,
        "architecture": arch,
        "package": None,
        "extras": [],
        "hyprlandSupported": None,
        "notes": [],
    }
    if arch is None:
        rec["reason"] = (
            "Could not determine this GPU's chip generation from its PCI name (%r). "
            "Refusing to pick a driver branch automatically — check the GPU on "
            "nvidia.com/drivers and pass --package explicitly." % g["name"]
        )
        return rec

    support = SUPPORT[arch]
    if support == "current":
        rec["package"] = "akmod-nvidia"
        rec["hyprlandSupported"] = True
        if arch in ("Turing", "Ampere", "Ada Lovelace", "Hopper", "Blackwell"):
            rec["notes"].append(
                "%s GPUs are supported by NVIDIA's open kernel modules, which current "
                "driver branches use by default for this generation." % arch
            )
    elif support == "legacy580":
        rec["hyprlandSupported"] = True
        legacy_available = _repo_has(ctx, "akmod-nvidia-580xx") if check_repo else None
        if legacy_available:
            rec["package"] = "akmod-nvidia-580xx"
            rec["notes"].append(
                "%s GPUs are only supported up to the 580 driver series; using the "
                "580xx legacy package so future driver updates don't drop support." % arch
            )
        else:
            rec["package"] = "akmod-nvidia"
            rec["notes"].append(
                "%s GPUs are supported only up to the NVIDIA 580 series. akmod-nvidia-580xx "
                "was not found in your enabled repositories%s, so akmod-nvidia is proposed — "
                "check `dnf info akmod-nvidia` shows a 580.x version before installing; newer "
                "branches no longer support this GPU."
                % (arch, "" if check_repo else " (repository check skipped)")
            )
    elif support == "legacy470":
        rec["hyprlandSupported"] = False
        rec["reason"] = (
            "Kepler GPUs need the 470xx legacy driver, which has no GBM support and "
            "therefore cannot run Hyprland. Use the in-kernel nouveau driver instead "
            "(already the Fedora default); no installation is needed."
        )
    else:
        rec["hyprlandSupported"] = False
        rec["reason"] = (
            "%s GPUs have no maintained proprietary driver for current kernels. "
            "Use the in-kernel nouveau driver (the Fedora default)." % arch
        )
    if rec["package"]:
        rec["extras"] = ["xorg-x11-drv-nvidia-cuda"]
        rec["notes"].append(
            "xorg-x11-drv-nvidia-cuda provides nvidia-smi (used by the AetherOS panel for "
            "GPU usage/temperature) and the CUDA driver library. It does not install the "
            "CUDA toolkit."
        )
    return rec


def _repo_has(ctx: Context, package: str) -> Optional[bool]:
    res = ctx.run(["dnf", "-q", "list", "--available", package], timeout=120)
    if res.rc == 127:
        return None
    if res.ok and package in res.out:
        return True
    # dnf exits 1 with "No matching packages" when absent.
    return False


def enabled_repos(ctx: Context) -> Optional[List[str]]:
    res = ctx.run(["dnf", "repolist", "--enabled"], timeout=120)
    if not res.ok:
        return None
    repos = []
    for line in res.out.splitlines()[1:]:
        parts = line.split()
        if parts:
            repos.append(parts[0])
    return repos


def rpmfusion_status(ctx: Context) -> Dict[str, Optional[bool]]:
    repos = enabled_repos(ctx)
    if repos is None:
        return {"free": None, "nonfree": None, "nvidiaOnly": None}
    nonfree = any(r == "rpmfusion-nonfree" or r.startswith("rpmfusion-nonfree-updates") for r in repos)
    nvidia_only = any(r.startswith("rpmfusion-nonfree-nvidia-driver") for r in repos)
    return {
        "free": any(r == "rpmfusion-free" or r.startswith("rpmfusion-free-updates") for r in repos),
        "nonfree": nonfree,
        "nvidiaOnly": nvidia_only,
    }


def newest_installed_kernel(ctx: Context) -> Optional[str]:
    res = ctx.run(["rpm", "-q", "kernel-core", "--qf", "%{VERSION}-%{RELEASE}.%{ARCH}\\n"], timeout=10)
    if not res.ok:
        return None
    kernels = [k.strip() for k in res.out.splitlines() if k.strip()]
    if not kernels:
        return None

    def key(k: str):
        return [int(x) if x.isdigit() else x for x in re.split(r"[.\-_]", k)]

    try:
        return sorted(kernels, key=key)[-1]
    except TypeError:
        return kernels[-1]


class Step(dict):
    """One planned action. ``argv`` is run without a shell."""


def install_plan(
    ctx: Context,
    package_override: Optional[str] = None,
    with_cuda: bool = True,
    with_vaapi: bool = False,
) -> Dict[str, object]:
    """Build — but do not execute — the NVIDIA installation plan."""
    gpus = gpu_mod.detect(ctx)
    nv = [g for g in gpus if g["vendor"] == "nvidia"]
    plan: Dict[str, object] = {"ok": False, "blockers": [], "warnings": [], "steps": [], "info": []}
    blockers: List[str] = plan["blockers"]  # type: ignore[assignment]
    warnings: List[str] = plan["warnings"]  # type: ignore[assignment]
    steps: List[Step] = plan["steps"]  # type: ignore[assignment]
    info: List[str] = plan["info"]  # type: ignore[assignment]

    if not system.is_fedora(ctx):
        blockers.append("This installer targets Fedora (RPM Fusion). Detected: %s" % (system.os_release(ctx).get("PRETTY_NAME") or "unknown OS"))
    if not nv:
        blockers.append("No NVIDIA GPU detected on the PCI bus — nothing to install.")
        return plan

    st = state(ctx, gpus)
    plan["state"] = st
    if st["moduleLoaded"] and st["driverVersion"]:
        info.append("The NVIDIA driver %s is already loaded and working." % st["driverVersion"])
        blockers.append("Driver already installed. Use `aether graphics verify` to check it; reinstalling is not needed.")
        return plan

    if package_override:
        package = package_override
        if not re.match(r"^akmod-nvidia(-\d+xx)?$", package):
            blockers.append("--package must be akmod-nvidia or akmod-nvidia-<branch>xx, got %r" % package)
            return plan
        warnings.append("Driver package chosen manually (--package %s); automatic branch selection skipped." % package)
        rec = {"package": package, "extras": ["xorg-x11-drv-nvidia-cuda"], "notes": []}
    else:
        rec = recommend(ctx, nv[0])
        if len(nv) > 1:
            archs = {architecture(g.get("codename")) for g in nv}
            if len(archs) > 1:
                blockers.append("Multiple NVIDIA GPUs of different generations (%s) — choose a branch manually with --package." % ", ".join(sorted(a or "unknown" for a in archs)))
                return plan
        if not rec["package"]:
            blockers.append(str(rec.get("reason")))
            plan["recommendation"] = rec
            return plan
    plan["recommendation"] = rec

    # Kernel: akmods builds for the newest installed kernel, so a system that
    # hasn't rebooted into its newest kernel ends up with no module for the
    # running one until the next boot. RPM Fusion's own instructions say to
    # fully update and reboot first.
    running = st["kernel"]
    newest = newest_installed_kernel(ctx)
    if running and newest and running != newest:
        warnings.append(
            "Running kernel %s is not the newest installed kernel (%s). Update and reboot "
            "into the newest kernel first: `sudo dnf upgrade --refresh` then reboot." % (running, newest)
        )

    fed_ver = system.os_release(ctx).get("VERSION_ID", "")
    rf = rpmfusion_status(ctx)
    plan["rpmfusion"] = rf
    if rf["nonfree"] is None:
        warnings.append("Could not query enabled repositories (dnf unavailable or offline).")
    elif not (rf["nonfree"] or rf["nvidiaOnly"]):
        if not fed_ver.isdigit():
            blockers.append("RPM Fusion is not enabled and the Fedora version could not be determined.")
            return plan
        steps.append(
            Step(
                title="Enable RPM Fusion (free + nonfree) using the official release packages",
                argv=["sudo", "dnf", "install", RPMFUSION_FREE.format(ver=fed_ver), RPMFUSION_NONFREE.format(ver=fed_ver)],
                why="akmod-nvidia is distributed by RPM Fusion, not Fedora. These are RPM Fusion's own signed repository definition packages; dnf will ask you to confirm and to import the repository GPG key.",
            )
        )

    sb = system.secure_boot(ctx)
    plan["secureBoot"] = sb
    if sb["state"] == "enabled":
        key = st["akmodsKey"]
        if key.get("enrolled") == "yes":
            info.append("Secure Boot is enabled and the akmods signing key is already enrolled — the module will be signed and load normally.")
        else:
            info.append(
                "Secure Boot is enabled. Kernel modules must be signed with a key the firmware trusts, "
                "otherwise the NVIDIA module is built but refused at load time. AetherOS will NOT disable "
                "Secure Boot. Instead it generates an akmods signing key and queues it for enrollment."
            )
            steps.append(
                Step(
                    title="Install the akmods signing tooling",
                    argv=["sudo", "dnf", "install", "kmodtool", "akmods", "mokutil", "openssl"],
                    why="Provides kmodgenca (key generation) and mokutil (key enrollment).",
                )
            )
            if not key.get("key"):
                steps.append(
                    Step(
                        title="Generate the akmods module-signing key",
                        argv=["sudo", "kmodgenca", "-a"],
                        why="Creates %s; akmods signs every module it builds with it." % AKMODS_KEY,
                    )
                )
            steps.append(
                Step(
                    title="Queue the signing key for enrollment (you will choose a one-time password)",
                    argv=["sudo", "mokutil", "--import", AKMODS_KEY],
                    why="On the next boot the blue 'MOK management' screen appears: choose 'Enroll MOK', 'Continue', 'Yes', then type the same one-time password.",
                )
            )
    elif sb["state"] == "unknown":
        warnings.append("Secure Boot state could not be determined. If the module fails to load after reboot, run `aether graphics verify`.")

    pkgs = [str(rec["package"])]
    if with_cuda:
        pkgs += list(rec.get("extras") or [])
    if with_vaapi:
        pkgs.append("libva-nvidia-driver")
    steps.append(
        Step(
            title="Install the NVIDIA driver (%s)" % ", ".join(pkgs),
            argv=["sudo", "dnf", "install"] + pkgs,
            why="akmod-nvidia builds the kernel module locally for your kernel and rebuilds it automatically after kernel updates.",
        )
    )
    if running:
        steps.append(
            Step(
                title="Build the kernel module now and wait for it",
                argv=["sudo", "akmods", "--force", "--kernels", running],
                why="Normally this happens in the background after installation; running it explicitly lets the installer confirm the module exists before you reboot.",
                optional=True,
            )
        )
    plan["ok"] = not blockers
    plan["postInstall"] = [
        "Confirm the module was built: modinfo -F version nvidia  (prints a version, not an error)",
        "Reboot." + (" Complete MOK enrollment on the blue screen that appears first." if sb["state"] == "enabled" and st["akmodsKey"].get("enrolled") != "yes" else ""),
        "After rebooting: aether graphics verify, then aether graphics configure to write the Hyprland GPU settings.",
    ]
    plan["rollback"] = [
        "sudo dnf history list   # find the transaction id of the driver install",
        "sudo dnf history undo <id>",
        "or: sudo dnf remove '*nvidia*' --exclude=nvidia-gpu-firmware",
    ]
    return plan


def write_install_record(record: Dict[str, object], directory: str) -> Optional[str]:
    import json
    import time

    try:
        os.makedirs(directory, exist_ok=True)
        path = os.path.join(directory, "nvidia-install-%s.json" % time.strftime("%Y%m%d-%H%M%S"))
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(record, fh, indent=2, default=str)
        return path
    except OSError:
        return None
