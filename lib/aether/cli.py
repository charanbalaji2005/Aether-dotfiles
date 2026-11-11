"""`aether` hardware/graphics/performance commands.

The bash entry point (scripts/bin/aether) keeps the session commands it has
always had (reload, lock, launcher, ...) and hands everything below to this
module. Every command:

* reads the real system through util.Context (no hard-coded output),
* supports --json for scripts and the shell,
* never needs root itself — privileged steps run via `sudo <cmd>` only after
  the exact command was shown and confirmed,
* logs what it changed to ~/.local/state/aether/aether.log.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from typing import Dict, List, Optional

from . import __version__, cli_desktop, cli_v1, performance, telemetry, theme
from .graphics import hyprconf, nvidia, report, stack
from .hw import cpu as cpu_mod
from .hw import gpu as gpu_mod
from .hw import system
from .util import Context, Output, confirm, default_context, get_logger, is_root, state_dir
from .util import parse_version as util_parse_version
from .util import version_at_least as util_version_at_least

REPO_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


# -- formatting helpers -------------------------------------------------------

def _bytes(n: Optional[float]) -> Optional[str]:
    if n is None:
        return None
    n = float(n)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if abs(n) < 1024 or unit == "TiB":
            return ("%.0f %s" if unit == "B" else "%.1f %s") % (n, unit)
        n /= 1024
    return None


def _pct(v: Optional[float]) -> Optional[str]:
    return None if v is None else "%d%%" % round(v * 100)


def _dur(seconds: Optional[float]) -> Optional[str]:
    if seconds is None:
        return None
    s = int(seconds)
    d, s = divmod(s, 86400)
    h, s = divmod(s, 3600)
    m, _ = divmod(s, 60)
    return ("%dd " % d if d else "") + "%dh %dm" % (h, m)


def _emit_json(data) -> int:
    json.dump(data, sys.stdout, indent=2, default=str)
    sys.stdout.write("\n")
    return 0


def _print_checks(out: Output, checks: List[Dict[str, str]]) -> None:
    for c in checks:
        out.status(c["level"], c["text"])
        if c.get("hint") and c["level"] != "pass":
            out.note(c["hint"])


# -- system / hardware --------------------------------------------------------

def cmd_system(ctx: Context, args) -> int:
    data = system.summary(ctx)
    if args.json:
        return _emit_json(data)
    out = Output()
    out.heading("System")
    out.kv("OS", data["os"])
    out.kv("Kernel", data["kernel"])
    out.kv("Architecture", data["architecture"])
    out.kv("Uptime", _dur(data["uptimeSeconds"]))  # type: ignore[arg-type]
    total, avail = data["memoryTotal"], data["memoryAvailable"]
    out.kv("Memory", "%s used of %s" % (_bytes(total - avail), _bytes(total)) if total and avail is not None else None)  # type: ignore[operator]
    st, sf = data["swapTotal"], data["swapFree"]
    out.kv("Swap", ("%s used of %s" % (_bytes(st - sf), _bytes(st))) if st else "none")  # type: ignore[operator]
    sb = data["secureBoot"]
    out.kv("Secure Boot", "%s (%s)" % (sb["state"], sb["detail"]))  # type: ignore[index]
    virt = data["virtualization"]
    out.kv("Virtualization", "bare metal" if virt == "none" else virt)
    out.heading("Session")
    sess = data["session"]
    out.kv("Session type", sess["sessionType"])  # type: ignore[index]
    out.kv("Desktop", sess["desktop"])  # type: ignore[index]
    out.kv("Hyprland", (data["hyprlandVersion"] or "not installed") + (" (running)" if sess["hyprlandRunning"] == "yes" else ""))  # type: ignore[index,operator]
    return 0


def _storage(ctx: Context) -> List[Dict[str, object]]:
    disks = []
    for name in ctx.listdir("/sys/block"):
        if name.startswith(("loop", "ram", "zram", "dm-", "sr", "md")):
            continue
        base = "/sys/block/" + name
        sectors = ctx.read_int(base + "/size")
        if not sectors:
            continue
        rot = ctx.read_line(base + "/queue/rotational")
        disks.append(
            {
                "name": name,
                "model": (ctx.read_line(base + "/device/model") or "").strip() or None,
                "size": sectors * 512,
                "type": "NVMe SSD" if name.startswith("nvme") else ("HDD" if rot == "1" else ("SSD" if rot == "0" else None)),
                "removable": ctx.read_line(base + "/removable") == "1",
            }
        )
    return disks


def cmd_hardware(ctx: Context, args) -> int:
    cpu = cpu_mod.summary(ctx)
    gpus = gpu_mod.detect(ctx)
    topo = gpu_mod.topology(gpus)
    mem = system.meminfo(ctx)
    disks = _storage(ctx)
    rel = system.os_release(ctx)
    data = {
        "system": {"os": rel.get("PRETTY_NAME"), "kernel": system.kernel_release(ctx), "architecture": system.architecture(ctx)},
        "cpu": cpu,
        "gpus": gpus,
        "gpuTopology": topo,
        "memory": {"total": mem.get("MemTotal"), "swapTotal": mem.get("SwapTotal")},
        "storage": disks,
        "battery": _battery(ctx),
    }
    if args.json:
        return _emit_json(data)
    out = Output()
    out.heading("Machine")
    out.kv("OS", data["system"]["os"])
    out.kv("Kernel", data["system"]["kernel"])
    out.kv("Architecture", data["system"]["architecture"])
    _print_cpu(out, cpu)
    out.heading("Graphics (%s)" % topo["layout"])
    if not gpus:
        out.write("  No display-class PCI devices found.")
    for g in gpus:
        out.kv(g["slot"], "%s %s" % (g["vendorLabel"], g["name"]))
        out.note("driver: %s | %s%s | runtime PM: %s" % (g["driver"] or "none", g["kind"], ", boot display" if g["bootVga"] else "", g["runtimeStatus"] or "n/a"))
    out.heading("Memory & storage")
    out.kv("RAM", _bytes(mem.get("MemTotal")))
    out.kv("Swap", _bytes(mem.get("SwapTotal")) or "none")
    for d in disks:
        out.kv(d["name"], "%s %s%s" % (_bytes(d["size"]), d["type"] or "", (" — " + d["model"]) if d["model"] else ""))  # type: ignore[arg-type]
    bat = data["battery"]
    if bat:
        out.heading("Battery")
        for b in bat:  # type: ignore[union-attr]
            out.kv(b["name"], "%s%% (%s)%s" % (b["capacity"], b["status"], (", health %s%%" % b["health"]) if b.get("health") else ""))
    return 0


def _battery(ctx: Context) -> List[Dict[str, object]]:
    out = []
    for name in ctx.listdir("/sys/class/power_supply"):
        base = "/sys/class/power_supply/" + name
        if ctx.read_line(base + "/type") != "Battery" or ctx.read_line(base + "/scope") == "Device":
            continue
        full = ctx.read_int(base + "/energy_full") or ctx.read_int(base + "/charge_full")
        design = ctx.read_int(base + "/energy_full_design") or ctx.read_int(base + "/charge_full_design")
        out.append(
            {
                "name": name,
                "capacity": ctx.read_int(base + "/capacity"),
                "status": ctx.read_line(base + "/status"),
                "health": round(full * 100.0 / design) if full and design else None,
            }
        )
    return out


def _print_cpu(out: Output, cpu: Dict[str, object]) -> None:
    topo = cpu["topology"]
    freq = cpu["frequency"]
    sc = cpu["scaling"]
    out.heading("CPU")
    out.kv("Model", cpu["model"])
    out.kv("Vendor", cpu["vendor"])
    if topo["threads"]:  # type: ignore[index]
        out.kv("Cores / threads", "%s cores, %s threads%s" % (topo["cores"], topo["threads"], ", %s sockets" % topo["sockets"] if (topo["sockets"] or 1) > 1 else ""))  # type: ignore[index,operator]
    else:
        out.kv("Cores / threads", None)
    if freq["currentMhz"]:  # type: ignore[index]
        out.kv("Frequency", "%d MHz now (max %s MHz)" % (freq["currentMhz"], freq["maxMhz"] or "?"))  # type: ignore[index]
    else:
        out.kv("Frequency", None)
    out.kv("Scaling driver", sc["driver"])  # type: ignore[index]
    out.kv("Governor", sc["governor"])  # type: ignore[index]
    if sc["energyPerformancePreference"]:  # type: ignore[index]
        out.kv("Energy preference", sc["energyPerformancePreference"])  # type: ignore[index]
    out.kv("Boost", sc["boost"])  # type: ignore[index]
    out.kv("Temperature", ("%.1f °C" % cpu["temperatureC"]) if cpu["temperatureC"] is not None else None)
    out.kv("Virtualization", ("%s (KVM %s)" % (cpu["virtualization"], "ready" if cpu["kvmAvailable"] == "yes" else "module not loaded")) if cpu["virtualization"] else "not exposed")


def cmd_cpu(ctx: Context, args) -> int:
    def once():
        info = cpu_mod.summary(ctx)
        live = telemetry.snapshot(ctx)
        info["live"] = live.get("cpu")
        info["load"] = live.get("load")
        return info

    if args.json:
        return _emit_json(once())
    out = Output()
    try:
        while True:
            info = once()
            if args.watch:
                sys.stdout.write("\033[2J\033[H")
            _print_cpu(out, info)
            live = info["live"] or {}
            out.heading("Live")
            out.kv("Usage", _pct(live.get("usage")))  # type: ignore[union-attr]
            cores = live.get("cores") or []  # type: ignore[union-attr]
            if cores:
                row = " ".join("%3d" % round(c * 100) for c in cores)
                out.kv("Per thread (%)", row)
            load = info.get("load")
            out.kv("Load average", " ".join("%.2f" % x for x in load) if load else None)  # type: ignore[union-attr]
            if not args.watch:
                return 0
            time.sleep(max(1.0, args.interval - 0.5))
    except KeyboardInterrupt:
        return 0


# -- GPU -----------------------------------------------------------------------

def cmd_gpu(ctx: Context, args) -> int:
    if args.gpu_cmd == "run":
        return cmd_gpu_run(ctx, args)
    if args.json:
        snap = telemetry.snapshot(ctx)
        return _emit_json({"gpus": gpu_mod.detect(ctx), "live": snap.get("gpus")})
    out = Output()
    try:
        while True:
            gpus = gpu_mod.detect(ctx)
            live = {g["slot"]: g for g in telemetry.snapshot(ctx).get("gpus", [])}  # type: ignore[union-attr]
            if args.watch:
                sys.stdout.write("\033[2J\033[H")
            if not gpus:
                out.write("No GPU detected.")
                return 1
            for g in gpus:
                out.heading("%s %s  [%s]" % (g["vendorLabel"], g["name"], g["slot"]))
                out.kv("Driver", g["driver"] or "none bound")
                out.kv("Type", "%s%s" % (g["kind"], ", boot display" if g["bootVga"] else ""))
                if g["vendor"] == "nvidia":
                    out.kv("Architecture", nvidia.architecture(g.get("codename")))
                lv = live.get(g["slot"])
                if lv is None:
                    out.kv("Telemetry", "not collected for virtual adapters")
                    continue
                if lv["state"] == "suspended":
                    out.kv("State", "asleep (runtime-suspended) — not queried to save power")
                    continue
                out.kv("Usage", _pct(lv["usage"]))
                out.kv("Temperature", ("%.0f °C" % lv["tempC"]) if lv["tempC"] is not None else None)
                if lv["vramTotal"]:
                    out.kv("VRAM", "%s / %s" % (_bytes(lv["vramUsed"]), _bytes(lv["vramTotal"])))
                else:
                    out.kv("VRAM", None)
                out.kv("Power", ("%.1f W" % lv["powerW"]) if lv["powerW"] is not None else None)
                out.kv("Clock", ("%d MHz" % lv["clockMhz"]) if lv["clockMhz"] else None)
                if lv.get("note"):
                    out.note(lv["note"])
            if not args.watch:
                return 0
            time.sleep(max(1.0, args.interval - 0.5))
    except KeyboardInterrupt:
        return 0


def cmd_gpu_run(ctx: Context, args) -> int:
    command = list(args.command or [])
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        sys.stderr.write("usage: aether gpu run [--gpu SLOT] <command> [args...]\n")
        return 2
    gpus = gpu_mod.detect(ctx)
    if args.gpu:
        target = next((g for g in gpus if g["slot"] == args.gpu or g["slot"].endswith(args.gpu)), None)
        if target is None:
            sys.stderr.write("No GPU at %s. Detected: %s\n" % (args.gpu, ", ".join(g["slot"] for g in gpus)))
            return 2
    else:
        candidates = [g for g in gpus if not g["bootVga"] and g["kind"] in ("discrete", "unknown")]
        target = candidates[0] if candidates else None
        if target is None:
            sys.stderr.write("No secondary GPU to offload to — this machine renders everything on %s already.\n" % (gpus[0]["name"] if gpus else "its only GPU"))
            return 1
    if not target["driver"]:
        sys.stderr.write("%s has no kernel driver bound; cannot offload to it.\n" % target["name"])
        return 1
    env = dict(os.environ)
    env.update(hyprconf.offload_env(target))
    get_logger().info("gpu run on %s: %s", target["slot"], command)
    try:
        os.execvpe(command[0], command, env)
    except OSError as exc:
        sys.stderr.write("Could not run %s: %s\n" % (command[0], exc))
        return 127
    return 0


# -- graphics ------------------------------------------------------------------

def cmd_graphics(ctx: Context, args) -> int:
    sub = args.graphics_cmd or "detect"
    if sub == "detect":
        data = report.detect(ctx)
        if args.json:
            return _emit_json(data)
        return _print_detect(data)
    if sub == "drivers":
        recs = report.drivers(ctx, check_repo=not args.offline)
        if args.json:
            return _emit_json(recs)
        out = Output()
        if not recs:
            out.write("No GPU detected.")
            return 1
        for r in recs:
            out.heading("%s [%s]" % (r["name"], r["slot"]))
            out.kv("Current driver", r.get("currentDriver") or "none")
            if r.get("architecture"):
                out.kv("Architecture", "%s (%s)" % (r["architecture"], r.get("codename")))
            if r["vendor"] == "nvidia":
                if r.get("package"):
                    out.kv("Recommended", "%s + %s" % (r["package"], ", ".join(r.get("extras") or [])))  # type: ignore[arg-type]
                    out.kv("Install with", r.get("command"))
                else:
                    out.kv("Recommended", "no proprietary driver")
                    out.note(str(r.get("reason", "")))
            for n in r.get("notes") or []:  # type: ignore[union-attr]
                out.bullet(n)
            for c in r.get("codecs") or []:  # type: ignore[union-attr]
                out.bullet("Video codecs: " + c)
        return 0
    if sub == "verify":
        checks = report.verify(ctx, hyprconf.hardware_conf_path())
        if args.json:
            return _emit_json(checks)
        out = Output()
        out.heading("Graphics verification")
        _print_checks(out, checks)
        fails = sum(1 for c in checks if c["level"] == "fail")
        warns = sum(1 for c in checks if c["level"] == "warn")
        out.write()
        out.write("  %d failed, %d warnings" % (fails, warns))
        return 1 if fails else 0
    if sub == "install-nvidia":
        return cmd_install_nvidia(ctx, args)
    if sub == "configure":
        return cmd_graphics_configure(ctx, args)
    sys.stderr.write("unknown graphics command %r\n" % sub)
    return 2


def _print_detect(data: Dict[str, object]) -> int:
    out = Output()
    topo = data["topology"]
    out.heading("Graphics hardware (%s)" % topo["layout"])  # type: ignore[index]
    gpus = data["gpus"]
    if not gpus:
        out.write("  No display-class PCI device found.")
    for g in gpus:  # type: ignore[union-attr]
        out.write()
        out.write("  %s %s" % (g["vendorLabel"], g["name"]))
        out.kv("  PCI slot / ID", "%s  [%s:%s]" % (g["slot"], g["vendorId"], g["deviceId"]))
        out.kv("  Kernel driver", g["driver"] or "none bound")
        out.kv("  Role", "%s%s" % (g["kind"], ", boot display" if g["bootVga"] else ""))
        out.kv("  DRM nodes", " ".join(x for x in (g["drm"].get("card"), g["drm"].get("render")) if x) or None)
        if g.get("codename"):
            out.kv("  Chip", "%s (%s)" % (g["codename"], nvidia.architecture(g["codename"]) or "unknown generation"))
        va = g.get("vaapi")
        if va:
            if va["status"] == "ok":
                out.kv("  VA-API", "%s — decode: %s" % (va.get("driver") or "?", ", ".join(va["decode"]) or "none"))
            elif va["status"] == "not-checked":
                out.kv("  VA-API", "not checked (%s)" % va.get("hint"))
            else:
                out.kv("  VA-API", "unavailable (%s)" % (va.get("error") or va["status"]))
    out.heading("Graphics stack")
    out.kv("Kernel", data["kernel"])
    out.kv("Mesa", data["mesa"])
    gl = data["opengl"]
    out.kv("OpenGL renderer", gl["renderer"] if gl["status"] == "ok" else "not checked (%s)" % gl.get("hint", gl["status"]))  # type: ignore[index]
    if gl.get("version"):  # type: ignore[union-attr]
        out.kv("OpenGL version", gl["version"])  # type: ignore[index]
    vk = data["vulkan"]
    if vk["status"] == "ok":  # type: ignore[index]
        for d in vk["devices"]:  # type: ignore[index]
            out.kv("Vulkan device", "%s (%s)" % (d.get("deviceName"), d.get("driverName") or d.get("driverID", "?")))
    else:
        icds = ", ".join(i["driver"] for i in vk["icds"]) or "none"  # type: ignore[index]
        out.kv("Vulkan drivers", "%s%s" % (icds, " — " + vk["hint"] if vk.get("hint") else ""))  # type: ignore[union-attr,index]
    sb = data["secureBoot"]
    out.kv("Secure Boot", sb["state"])  # type: ignore[index]
    out.kv("Hyprland", data["hyprlandVersion"])
    nv = data.get("nvidia")
    if nv:
        out.heading("NVIDIA driver")
        out.kv("Module loaded", "yes (%s)" % nv["driverVersion"] if nv["moduleLoaded"] else "no")  # type: ignore[index]
        out.kv("Module for kernel", nv["moduleBuiltForRunningKernel"] or "none built for the running kernel")  # type: ignore[index]
        installed = [k + " " + v for k, v in nv["packages"].items() if v]  # type: ignore[index,union-attr]
        out.kv("Packages", ", ".join(installed) if installed else ("none" if nv["packages"] else "rpm unavailable"))  # type: ignore[index]
        out.kv("nouveau loaded", "yes" if nv["nouveauLoaded"] else "no")  # type: ignore[index]
        out.kv("DRM modeset / fbdev", "%s / %s" % (nv["drmModeset"] or "-", nv["drmFbdev"] or "-"))  # type: ignore[index]
        out.kv("GBM backend", "present" if nv["gbmBackend"] else "missing")  # type: ignore[index]
        out.kv("Explicit sync", "supported (555+)" if nv["explicitSyncCapable"] else "not supported / unknown")  # type: ignore[index]
        key = nv["akmodsKey"]  # type: ignore[index]
        out.kv("akmods signing key", ("present, enrolled: %s" % (key["enrolled"] or "unknown")) if key["key"] else "not generated")
        out.kv("Persistence daemon", "%s / %s" % (nv["persistenced"].get("enabled") or "-", nv["persistenced"].get("active") or "-"))  # type: ignore[index,union-attr]
        out.kv("nvidia-smi", "available" if nv["nvidiaSmi"] else "not installed")  # type: ignore[index]
        out.kv("CUDA", "driver library present" if nv["cudaDriverLibrary"] else "libcuda not found")  # type: ignore[index]
        out.kv("Vulkan ICD", "present" if nv["vulkanIcd"] else "missing")  # type: ignore[index]
    out.write()
    out.write("  Next: `aether graphics verify` for PASS/WARN/FAIL checks, `aether graphics drivers` for recommendations.")
    return 0


def cmd_install_nvidia(ctx: Context, args) -> int:
    out = Output()
    log = get_logger()
    if is_root():
        sys.stderr.write("Run this as your normal user. It uses sudo for the individual steps that need root.\n")
        return 2
    plan = nvidia.install_plan(ctx, package_override=args.package, with_cuda=not args.no_cuda, with_vaapi=args.vaapi)
    if args.json:
        return _emit_json(plan)
    out.heading("NVIDIA driver installation plan")
    rec = plan.get("recommendation") or {}
    if rec.get("name"):  # type: ignore[union-attr]
        out.kv("GPU", "%s (%s, %s)" % (rec["name"], rec.get("codename") or "?", rec.get("architecture") or "unknown generation"))  # type: ignore[index,union-attr]
    for line in plan["info"]:  # type: ignore[union-attr]
        out.status("info", line)
    for n in rec.get("notes") or []:  # type: ignore[union-attr]
        out.status("info", n)
    for w in plan["warnings"]:  # type: ignore[union-attr]
        out.status("warn", w)
    if plan["blockers"]:
        for b in plan["blockers"]:  # type: ignore[union-attr]
            out.status("fail", b)
        out.write()
        out.write("  Nothing was changed.")
        return 0 if any("already installed" in b for b in plan["blockers"]) else 1  # type: ignore[union-attr]

    out.heading("Steps")
    for i, step in enumerate(plan["steps"], 1):  # type: ignore[arg-type]
        out.write("  %d. %s%s" % (i, step["title"], " (optional)" if step.get("optional") else ""))
        out.write("     $ %s" % " ".join(step["argv"]))
        out.note(step["why"])
    out.heading("After installing")
    for line in plan["postInstall"]:  # type: ignore[union-attr]
        out.bullet(line)
    out.heading("Rollback")
    for line in plan["rollback"]:  # type: ignore[union-attr]
        out.bullet(line)

    if args.dry_run:
        out.write()
        out.write("  --dry-run: nothing was executed.")
        return 0
    out.write()
    if not confirm("Execute the steps above?", assume_yes=args.yes, typed="install"):
        out.write("  Aborted — nothing was changed.")
        return 1

    before = ctx.run(["rpm", "-qa", "*nvidia*"]).out.split()
    record = {"started": time.strftime("%Y-%m-%d %H:%M:%S"), "plan": plan, "packagesBefore": sorted(before), "results": []}
    for step in plan["steps"]:  # type: ignore[union-attr]
        if step.get("optional") and not confirm("Run optional step: %s?" % step["title"], assume_yes=args.yes):
            record["results"].append({"step": step["title"], "skipped": True})  # type: ignore[union-attr]
            continue
        argv = list(step["argv"])
        if args.yes and argv[:3] == ["sudo", "dnf", "install"]:
            argv.insert(3, "-y")
        out.write()
        out.write("  >>> %s" % " ".join(argv))
        log.info("install-nvidia executing: %s", argv)
        rc = subprocess.call(argv)
        record["results"].append({"step": step["title"], "argv": argv, "rc": rc})  # type: ignore[union-attr]
        if rc != 0:
            out.status("fail", "Step failed with exit code %d: %s" % (rc, step["title"]))
            out.note("Stopped here. Nothing after this step ran. Re-run `aether graphics install-nvidia` after fixing the cause.")
            record["packagesAfter"] = sorted(ctx.run(["rpm", "-qa", "*nvidia*"]).out.split())
            path = nvidia.write_install_record(record, state_dir())
            if path:
                out.note("Install record: %s" % path)
            return 1

    built = nvidia.module_built_version(ctx)
    record["packagesAfter"] = sorted(ctx.run(["rpm", "-qa", "*nvidia*"]).out.split())
    record["moduleBuilt"] = built
    path = nvidia.write_install_record(record, state_dir())
    out.write()
    if built:
        out.status("pass", "NVIDIA kernel module %s is built for the running kernel." % built)
        out.write("  Reboot to load it, then run: aether graphics verify && aether graphics configure")
    else:
        out.status("warn", "The kernel module is not built yet.")
        out.note("akmods may still be building in the background. Wait, then check `modinfo -F version nvidia` before rebooting.")
    if path:
        out.note("Install record (packages before/after, every command run): %s" % path)
    return 0


def cmd_graphics_configure(ctx: Context, args) -> int:
    out = Output()
    path = hyprconf.hardware_conf_path()
    try:
        text, notes, links = hyprconf.generate_hardware_conf(ctx, primary_slot=args.primary)
    except ValueError as exc:
        sys.stderr.write(str(exc) + "\n")
        return 2
    current = ""
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            current = fh.read()
    if args.json:
        return _emit_json({"path": path, "content": text, "notes": notes, "changed": current != text})
    out.heading("Hyprland GPU settings → %s" % path)
    for n in notes:
        out.status("info", n)
    if current == text:
        out.write("  Already up to date — nothing to change.")
        return 0
    out.write()
    out.write(hyprconf.diff(current, text, path) if current else text)
    if args.dry_run:
        out.write("  --dry-run: nothing written.")
        return 0
    if current and not current.startswith(hyprconf.HEADER_MARK) and "Placeholder created by AetherOS" not in current:
        out.status("warn", "The existing file was edited by hand; it will be backed up before replacing.")
    if not confirm("Write this file?", assume_yes=args.yes):
        out.write("  Aborted — nothing written.")
        return 1
    backup = hyprconf.write_fragment(path, text, links)
    get_logger().info("graphics configure wrote %s (backup: %s)", path, backup)
    out.status("pass", "Wrote %s" % path)
    if backup:
        out.note("Previous version saved as %s" % backup)
    out.note("Hyprland reloads sourced files automatically. Environment (env =) changes apply at your next login.")
    return 0


# -- performance ---------------------------------------------------------------

def cmd_performance(ctx: Context, args) -> int:
    sub = args.perf_cmd or "status"
    out = Output()
    if sub == "status":
        pp = performance.power_profile_state(ctx)
        hp = performance.current_hypr_profile(hyprconf.profile_conf_path())
        sc = cpu_mod.scaling(ctx)
        data = {"powerProfile": pp, "hyprlandProfile": hp or "balanced (default)", "cpuScaling": sc}
        if args.json:
            return _emit_json(data)
        out.heading("Performance")
        out.kv("Power profile", "%s (available: %s)" % (pp["active"], ", ".join(pp["profiles"])) if pp.get("available") else "unavailable — %s" % pp.get("reason"))  # type: ignore[arg-type]
        out.kv("Hyprland profile", data["hyprlandProfile"])
        out.kv("CPU governor", sc["governor"])
        out.kv("CPU energy pref.", sc["energyPerformancePreference"])
        out.write()
        out.write("  Change with: aether performance set <power-saver|balanced|performance>")
        out.write("               aether performance hyprland <%s>" % "|".join(performance.HYPR_PROFILES))
        return 0
    if sub == "list":
        if args.json:
            return _emit_json({"power": list(performance.POWER_PROFILES), "hyprland": {k: v["summary"] for k, v in performance.HYPR_PROFILES.items()}})
        out.heading("Power profiles (powerprofilesctl)")
        for p in performance.POWER_PROFILES:
            out.bullet(p)
        out.heading("Hyprland profiles")
        for k, v in performance.HYPR_PROFILES.items():
            out.bullet("%-12s %s" % (k, v["summary"]))
        return 0
    if sub == "set":
        res = performance.set_power_profile(ctx, args.profile)
        if args.json:
            return _emit_json(res)
        if res["ok"]:
            get_logger().info("power profile set to %s", args.profile)
            out.status("pass", "Power profile: %s" % res["active"])
            return 0
        out.status("fail", str(res["error"]))
        return 1
    if sub == "hyprland":
        name = args.profile
        if name not in performance.HYPR_PROFILES:
            sys.stderr.write("unknown Hyprland profile %r (choose: %s)\n" % (name, ", ".join(performance.HYPR_PROFILES)))
            return 2
        path = hyprconf.profile_conf_path()
        hver = util_parse_version(system.hyprland_version(ctx))
        text = performance.render_hypr_profile(name, bool(hver and util_version_at_least(hver, (0, 53))))
        if args.dry_run:
            out.write(text)
            return 0
        backup = hyprconf.write_fragment(path, text)
        get_logger().info("hyprland profile %s written to %s", name, path)
        if args.json:
            return _emit_json({"ok": True, "profile": name, "path": path, "backup": backup})
        out.status("pass", "Hyprland profile '%s' written to %s" % (name, path))
        out.note("Hyprland picks this up automatically; if not, run `hyprctl reload`.")
        return 0
    return 2


# -- theme ---------------------------------------------------------------------

def cmd_theme(ctx: Context, args) -> int:
    handled = cli_desktop.cmd_theme_extra(ctx, args)
    if handled is not None:
        return handled
    out = Output()
    if args.theme_cmd == "accent":
        colour, err = theme.extract_accent(ctx, args.image, args.mode)
        if args.json:
            return _emit_json({"accent": colour, "error": err})
        if err:
            sys.stderr.write(err + "\n")
            return 1
        if args.apply:
            ok, msg = theme.update_shell_config("appearance", "accent", colour)
            if not ok:
                sys.stderr.write(msg + "\n")
                return 1
        sys.stdout.write(str(colour) + "\n")
        return 0
    if args.theme_cmd == "mode":
        ok, msg = theme.update_shell_config("appearance", "theme", args.mode)
        if not ok:
            out.status("fail", msg)
            return 1
        out.status("pass", "Shell theme set to %s (%s)" % (args.mode, msg))
        if args.mode in ("dark", "light"):
            ok2, msg2 = theme.set_color_scheme(ctx, args.mode)
            out.status("pass" if ok2 else "warn", "GTK color-scheme: %s" % msg2)
        return 0
    return 2


# -- telemetry -----------------------------------------------------------------

def cmd_telemetry(ctx: Context, args) -> int:
    if args.stream:
        return telemetry.stream(ctx, max(0.5, args.interval), args.processes, args.count)
    return _emit_json(telemetry.snapshot(ctx, processes=args.processes))


# -- diagnostics / repair ------------------------------------------------------

def hyprland_config_check(ctx: Context) -> List[Dict[str, str]]:
    checks = []
    conf = os.path.join(os.environ.get("HOME", ""), ".config", "hypr", "hyprland.conf")
    for frag in (hyprconf.hardware_conf_path(), hyprconf.profile_conf_path(), hyprconf.compat_conf_path()):
        if os.path.isfile(frag):
            checks.append({"level": "pass", "text": "%s exists" % frag, "hint": ""})
        else:
            checks.append({"level": "fail", "text": "%s missing — hyprland.conf sources it" % frag, "hint": "Run `aether repair` to recreate it."})
    if ctx.which("Hyprland") and os.path.isfile(conf):
        res = ctx.run(["Hyprland", "--verify-config", "-c", conf], timeout=30)
        text = (res.out + res.err).strip()
        if res.ok and "error" not in text.lower():
            checks.append({"level": "pass", "text": "Hyprland --verify-config: no errors", "hint": ""})
        elif res.rc == 127:
            pass
        elif "unrecognized" in text.lower() or "unknown option" in text.lower():
            checks.append({"level": "info", "text": "This Hyprland build has no --verify-config", "hint": ""})
        else:
            tail = "\n".join(text.splitlines()[-8:])
            checks.append({"level": "fail", "text": "Hyprland reports config errors", "hint": tail})
    if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE") and ctx.which("hyprctl"):
        res = ctx.run(["hyprctl", "configerrors"], timeout=5)
        errs = [l for l in res.out.splitlines() if l.strip() and "no errors" not in l.lower()]
        if res.ok and not errs:
            checks.append({"level": "pass", "text": "Running Hyprland reports no config errors", "hint": ""})
        elif res.ok:
            checks.append({"level": "fail", "text": "Running Hyprland reports %d config error(s)" % len(errs), "hint": "\n".join(errs[:8])})
    return checks


def shell_config_check() -> List[Dict[str, str]]:
    path = theme.config_file()
    if not os.path.exists(path):
        return [{"level": "info", "text": "%s not created yet (the shell writes it on first start)" % path, "hint": ""}]
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        if not isinstance(data, dict):
            raise ValueError("not an object")
    except (ValueError, OSError) as exc:
        return [{"level": "fail", "text": "%s is not valid JSON (%s)" % (path, exc), "hint": "`aether repair` backs it up and lets the shell recreate defaults."}]
    return [{"level": "pass", "text": "%s is valid JSON" % path, "hint": ""}]


def cmd_diagnostics(ctx: Context, args) -> int:
    out = Output()
    sections = []
    doctor = os.path.join(REPO_DIR, "scripts", "doctor.sh")
    doctor_rc = None
    if os.path.isfile(doctor) and not args.json:
        out.heading("Dependencies & session (scripts/doctor.sh)")
        sys.stdout.flush()
        doctor_rc = subprocess.call(["bash", doctor])
    sections.append(("Hyprland configuration", hyprland_config_check(ctx)))
    sections.append(("Shell configuration", shell_config_check()))
    sections.append(("Graphics", report.verify(ctx, hyprconf.hardware_conf_path())))
    pp = performance.power_profile_state(ctx)
    sections.append(("Power management", [
        {"level": "pass", "text": "Power profile: %s" % pp["active"], "hint": ""} if pp.get("available")
        else {"level": "warn", "text": "Power profiles unavailable", "hint": str(pp.get("reason"))}
    ]))
    cpu = cpu_mod.summary(ctx)
    sections.append(("CPU", [
        {"level": "pass" if cpu["temperatureC"] is not None else "warn",
         "text": ("CPU temperature sensor: %.1f °C" % cpu["temperatureC"]) if cpu["temperatureC"] is not None else "No CPU temperature sensor found",
         "hint": "" if cpu["temperatureC"] is not None else "The panel will show CPU temperature as unavailable. Load coretemp (Intel) or k10temp (AMD)."},
    ]))
    if args.json:
        return _emit_json({name: checks for name, checks in sections})
    fails = 0
    lines = []
    for name, checks in sections:
        out.heading(name)
        _print_checks(out, checks)
        for c in checks:
            lines.append("[%s] %s: %s%s" % (c["level"].upper(), name, c["text"], (" — " + c["hint"]) if c.get("hint") else ""))
            fails += c["level"] == "fail"
    try:
        os.makedirs(state_dir(), exist_ok=True)
        path = os.path.join(state_dir(), "diagnostics-%s.txt" % time.strftime("%Y%m%d-%H%M%S"))
        with open(path, "w", encoding="utf-8") as fh:
            fh.write("AetherOS diagnostics %s (aether %s)\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), __version__))
            fh.write("\n".join(lines) + "\n")
        out.write()
        out.write("  Report saved to %s" % path)
    except OSError:
        pass
    return 1 if fails or (doctor_rc not in (None, 0)) else 0


def cmd_repair(ctx: Context, args) -> int:
    out = Output()
    log = get_logger()
    actions = []

    for frag in (hyprconf.hardware_conf_path(), hyprconf.profile_conf_path(), hyprconf.compat_conf_path()):
        if not os.path.isfile(frag):
            actions.append(("Recreate missing Hyprland fragment %s" % frag, lambda: hyprconf.ensure_defaults(), False))
    compat = hyprconf.compat_conf_path()
    if system.hyprland_version(ctx) and (not os.path.isfile(compat) or "Placeholder created by AetherOS" in open(compat, encoding="utf-8", errors="replace").read()):
        actions.append(("Write version-specific Hyprland settings to %s" % compat,
                        lambda: hyprconf.write_fragment(compat, hyprconf.generate_compat_conf(ctx)), False))

    cfg = theme.config_file()
    if os.path.exists(cfg) and shell_config_check()[0]["level"] == "fail":
        def _reset_cfg(cfg=cfg):
            dest = "%s.broken-%s" % (cfg, time.strftime("%Y%m%d-%H%M%S"))
            os.replace(cfg, dest)
            return dest
        actions.append(("Move invalid %s aside (the shell recreates defaults)" % cfg, _reset_cfg, True))

    bindir = os.path.join(REPO_DIR, "scripts", "bin")
    for f in sorted(os.listdir(bindir)) if os.path.isdir(bindir) else []:
        p = os.path.join(bindir, f)
        if os.path.isfile(p) and hasattr(os, "access") and not os.access(p, os.X_OK):
            actions.append(("Restore executable bit on %s" % p, lambda p=p: os.chmod(p, 0o755), False))

    home = os.environ.get("HOME", "")
    managed = [
        os.path.join(home, ".config", "hypr"),
        os.path.join(home, ".config", "quickshell", "aether-shell"),
        os.path.join(home, ".local", "bin", "aether"),
    ]
    broken = [m for m in managed if not os.path.exists(m)]
    setup = os.path.join(REPO_DIR, "scripts", "setup-symlinks.sh")
    if broken and os.path.isfile(setup):
        actions.append(("Re-run setup-symlinks.sh (missing/broken: %s; existing files are backed up, never deleted)" % ", ".join(broken),
                        lambda: subprocess.call(["bash", setup]), True))

    if ctx.which("systemctl") and os.environ.get("XDG_RUNTIME_DIR"):
        for unit in ("aether-shell.service", "aether-clipboard.service"):
            res = ctx.run(["systemctl", "--user", "is-enabled", unit], timeout=5)
            state = res.out.strip()
            if state not in ("enabled", "enabled-runtime", "static", "linked"):
                actions.append(("Enable systemd user unit %s (currently: %s)" % (unit, state or "unknown"),
                                lambda unit=unit: subprocess.call(["systemctl", "--user", "enable", unit]), True))

    if not actions:
        out.status("pass", "Nothing to repair.")
        hc = hyprland_config_check(ctx)
        if any(c["level"] == "fail" for c in hc):
            _print_checks(out, hc)
            out.note("Hyprland config errors need a manual fix. Recovery: log in from a TTY and run\n  Hyprland -c %s" % os.path.join(REPO_DIR, "config", "hypr", "recovery.conf"))
        return 0

    out.heading("Repairs")
    for i, (title, _, _) in enumerate(actions, 1):
        out.write("  %d. %s" % (i, title))
    if args.dry_run:
        out.write()
        out.write("  --dry-run: nothing changed.")
        return 0
    failed = 0
    for title, fn, needs_confirm in actions:
        if needs_confirm and not confirm(title + "?", assume_yes=args.yes):
            out.status("info", "skipped: " + title)
            continue
        try:
            result = fn()
            if isinstance(result, int) and result != 0:
                raise RuntimeError("exit code %d" % result)
            out.status("pass", title)
            log.info("repair: %s -> %s", title, result)
        except Exception as exc:  # noqa: BLE001 — report and continue with the next repair
            failed += 1
            out.status("fail", "%s (%s)" % (title, exc))
            log.error("repair failed: %s (%s)", title, exc)
    return 1 if failed else 0


def cmd_hyprland(ctx: Context, args) -> int:
    if getattr(args, "hypr_cmd", None) == "compat":
        path = hyprconf.compat_conf_path()
        if getattr(args, "if_stale", False) and not hyprconf.compat_is_stale(ctx, path):
            return 0
        text = hyprconf.generate_compat_conf(ctx)
        if args.dry_run:
            sys.stdout.write(text)
            return 0
        backup = hyprconf.write_fragment(path, text)
        get_logger().info("hyprland compat written to %s", path)
        if args.json:
            return _emit_json({"path": path, "backup": backup})
        Output().status("pass", "Wrote %s" % path)
        return 0
    checks = hyprland_config_check(ctx)
    if args.json:
        return _emit_json(checks)
    out = Output()
    out.heading("Hyprland configuration")
    _print_checks(out, checks)
    return 1 if any(c["level"] == "fail" for c in checks) else 0


# -- parser --------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="aether", description="AetherOS hardware, graphics and performance tools.")
    p.add_argument("--version", action="version", version="aether " + __version__)
    sub = p.add_subparsers(dest="command", metavar="<command>")

    def add(name, help_text):
        sp = sub.add_parser(name, help=help_text, description=help_text)
        sp.add_argument("--json", action="store_true", help="machine-readable output")
        return sp

    add("system", "OS, kernel, session, Secure Boot and Hyprland version")
    add("hardware", "CPU, GPUs, memory, storage and battery overview")

    sp = add("cpu", "CPU model, topology, frequency, governor, temperature and live usage")
    sp.add_argument("--watch", action="store_true", help="refresh continuously (Ctrl+C to stop)")
    sp.add_argument("--interval", type=float, default=2.0)

    sp = add("gpu", "GPU list with live usage, temperature, VRAM and power; `gpu run` offloads a program")
    sp.add_argument("--watch", action="store_true", help="refresh continuously (Ctrl+C to stop)")
    sp.add_argument("--interval", type=float, default=2.0)
    gsub = sp.add_subparsers(dest="gpu_cmd", metavar="[run]")
    run = gsub.add_parser("run", help="run a program on the discrete GPU (PRIME offload)")
    run.add_argument("--gpu", help="PCI slot of the GPU to use (default: first non-boot GPU)")
    run.add_argument("command", nargs=argparse.REMAINDER)

    sp = add("graphics", "graphics drivers: detect | drivers | verify | install-nvidia | configure")
    gs = sp.add_subparsers(dest="graphics_cmd", metavar="<subcommand>")
    for name, h in (("detect", "detect GPUs and the full graphics stack"),
                    ("drivers", "recommend drivers and codec packages per GPU (installs nothing)"),
                    ("verify", "PASS/WARN/FAIL checks of the running graphics stack")):
        x = gs.add_parser(name, help=h, description=h)
        x.add_argument("--json", action="store_true")
        if name == "drivers":
            x.add_argument("--offline", action="store_true", help="skip querying dnf repositories")
    x = gs.add_parser("install-nvidia", help="install the matching RPM Fusion NVIDIA driver (Fedora)",
                      description="Shows the full plan and asks before running anything. Never disables Secure Boot.")
    x.add_argument("--json", action="store_true", help="print the plan as JSON and exit")
    x.add_argument("--dry-run", action="store_true", help="show the plan only")
    x.add_argument("--yes", action="store_true", help="don't prompt (still never touches Secure Boot)")
    x.add_argument("--no-cuda", action="store_true", help="skip xorg-x11-drv-nvidia-cuda (nvidia-smi, libcuda)")
    x.add_argument("--vaapi", action="store_true", help="also install libva-nvidia-driver for VA-API decode")
    x.add_argument("--package", help="override the automatically selected akmod package")
    x = gs.add_parser("configure", help="write Hyprland GPU settings for this machine",
                      description="Generates ~/.config/aether-shell/hypr/hardware.conf from detected hardware.")
    x.add_argument("--json", action="store_true")
    x.add_argument("--primary", metavar="SLOT", help="explicitly choose the GPU Hyprland renders on (PCI slot)")
    x.add_argument("--dry-run", action="store_true")
    x.add_argument("--yes", action="store_true")

    sp = add("performance", "power profiles and Hyprland visual profiles")
    ps = sp.add_subparsers(dest="perf_cmd", metavar="[status|list|set|hyprland]")
    ps.add_parser("status", help="show current profiles").add_argument("--json", action="store_true")
    ps.add_parser("list", help="list available profiles").add_argument("--json", action="store_true")
    x = ps.add_parser("set", help="set the system power profile")
    x.add_argument("profile", choices=performance.POWER_PROFILES)
    x.add_argument("--json", action="store_true")
    x = ps.add_parser("hyprland", help="set the Hyprland visual profile")
    x.add_argument("profile", choices=list(performance.HYPR_PROFILES))
    x.add_argument("--dry-run", action="store_true")
    x.add_argument("--json", action="store_true")

    sp = add("theme", "accent colour from a wallpaper; dark/light mode")
    ts = sp.add_subparsers(dest="theme_cmd", metavar="<accent|mode>")
    x = ts.add_parser("accent", help="derive an accent colour from an image")
    x.add_argument("image")
    x.add_argument("--mode", choices=("dark", "light"), default="dark")
    x.add_argument("--apply", action="store_true", help="write it to the shell config")
    x = ts.add_parser("mode", help="set the shell theme")
    x.add_argument("mode", choices=("dark", "light", "auto"))
    cli_desktop.register(sub, add, ts)
    cli_v1.register(sub, add)

    sp = add("telemetry", "live metrics as JSON (used by the shell)")
    sp.add_argument("--stream", action="store_true", help="one JSON line per interval until stdout closes")
    sp.add_argument("--interval", type=float, default=2.0)
    sp.add_argument("--processes", action="store_true", help="emit the top-processes table instead of system metrics")
    sp.add_argument("--count", type=int, help="stop after N lines (testing)")

    add("diagnostics", "full health report (dependencies, Hyprland config, graphics, power)")
    sp = add("repair", "fix common problems (missing fragments, broken symlinks, invalid config, units)")
    sp.add_argument("--dry-run", action="store_true")
    sp.add_argument("--yes", action="store_true")
    sp = add("hyprland", "validate the Hyprland configuration; `hyprland compat` writes version-specific syntax")
    hs = sp.add_subparsers(dest="hypr_cmd", metavar="[verify|compat]")
    hs.add_parser("verify", help="check the config with Hyprland itself").add_argument("--json", action="store_true")
    x = hs.add_parser("compat", help="write settings whose syntax depends on the Hyprland version")
    x.add_argument("--dry-run", action="store_true")
    x.add_argument("--if-stale", action="store_true", help="only if Hyprland's version changed or the file is a placeholder (used at login)")
    x.add_argument("--json", action="store_true")
    return p


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not getattr(args, "command", None):
        parser.print_help()
        return 0
    if not hasattr(args, "json"):
        args.json = False
    ctx = default_context()
    handlers = {
        "system": cmd_system,
        "hardware": cmd_hardware,
        "cpu": cmd_cpu,
        "gpu": cmd_gpu,
        "graphics": cmd_graphics,
        "performance": cmd_performance,
        "theme": cmd_theme,
        "telemetry": cmd_telemetry,
        "diagnostics": cmd_diagnostics,
        "repair": cmd_repair,
        "hyprland": cmd_hyprland,
    }
    handlers.update(cli_desktop.HANDLERS)
    handlers.update(cli_v1.HANDLERS)
    for key, value in list(cli_desktop.DEFAULTS.items()) + list(cli_v1.DEFAULTS.items()):
        if not hasattr(args, key):
            setattr(args, key, value)
    if args.command == "gpu" and not hasattr(args, "gpu_cmd"):
        args.gpu_cmd = None
    if args.command == "graphics" and getattr(args, "graphics_cmd", None) is None:
        args.graphics_cmd = "detect"
    if args.command == "theme" and not getattr(args, "theme_cmd", None):
        parser.parse_args(["theme", "--help"])
    if args.command == "performance" and not getattr(args, "dry_run", None):
        args.dry_run = False
    try:
        return handlers[args.command](ctx, args)
    except KeyboardInterrupt:
        return 130
    except BrokenPipeError:
        return 0
