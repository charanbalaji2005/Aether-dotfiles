"""CPU detection: vendor, model, topology, frequency, governor, thermals.

Reads /proc/cpuinfo and sysfs only — no external tools required. Works on
Intel and AMD x86 machines and degrades to partial information on other
architectures (ARM cpuinfo has no "model name"/"vendor_id" fields).
"""

from __future__ import annotations

import re
from typing import Dict, List, Optional

from ..util import Context

_VENDORS = {
    "GenuineIntel": "Intel",
    "AuthenticAMD": "AMD",
    "HygonGenuine": "Hygon",
    "CentaurHauls": "Centaur",
}

# hwmon driver names that report CPU package/die temperature, best first.
_CPU_HWMON = ("coretemp", "k10temp", "zenpower", "cpu_thermal", "soc_thermal")
# Preferred sensor labels per driver.
_PREFERRED_LABELS = ("package id 0", "tctl", "tdie", "cpu")


def _parse_cpuinfo(text: str) -> List[Dict[str, str]]:
    blocks: List[Dict[str, str]] = []
    current: Dict[str, str] = {}
    for line in text.splitlines():
        if not line.strip():
            if current:
                blocks.append(current)
                current = {}
            continue
        key, sep, value = line.partition(":")
        if sep:
            current[key.strip()] = value.strip()
    if current:
        blocks.append(current)
    return blocks


def topology(ctx: Context) -> Dict[str, Optional[int]]:
    blocks = [b for b in _parse_cpuinfo(ctx.read("/proc/cpuinfo") or "") if "processor" in b]
    threads = len(blocks) or None
    cores = set()
    sockets = set()
    for b in blocks:
        if "physical id" in b and "core id" in b:
            cores.add((b["physical id"], b["core id"]))
            sockets.add(b["physical id"])
    if not cores:
        # Fall back to sysfs topology (ARM and some VMs omit the fields).
        for cpu in ctx.glob("/sys/devices/system/cpu/cpu[0-9]*"):
            core = ctx.read_line(cpu + "/topology/core_id")
            pkg = ctx.read_line(cpu + "/topology/physical_package_id")
            if core is not None:
                cores.add((pkg, core))
                sockets.add(pkg)
    return {
        "threads": threads,
        "cores": len(cores) or threads,
        "sockets": len(sockets) or (1 if threads else None),
    }


def identity(ctx: Context) -> Dict[str, Optional[str]]:
    blocks = _parse_cpuinfo(ctx.read("/proc/cpuinfo") or "")
    first = blocks[0] if blocks else {}
    vendor_raw = first.get("vendor_id")
    model = first.get("model name") or first.get("Model") or first.get("Hardware")
    if model:
        model = re.sub(r"\s+", " ", model)
    flags = set((first.get("flags") or first.get("Features") or "").split())
    if "vmx" in flags:
        virt = "Intel VT-x"
    elif "svm" in flags:
        virt = "AMD-V"
    else:
        virt = None
    return {
        "vendor": _VENDORS.get(vendor_raw or "", vendor_raw),
        "model": model,
        "family": first.get("cpu family"),
        "microcode": first.get("microcode"),
        "virtualization": virt,
        "kvmAvailable": "yes" if ctx.exists("/dev/kvm") else "no",
        "flags": sorted(flags & {"avx", "avx2", "avx512f", "sse4_2", "aes", "sha_ni", "hypervisor"}),
    }


def frequency(ctx: Context) -> Dict[str, Optional[float]]:
    cur: List[int] = []
    max_khz: Optional[int] = None
    min_khz: Optional[int] = None
    for cpu in ctx.glob("/sys/devices/system/cpu/cpu[0-9]*"):
        v = ctx.read_int(cpu + "/cpufreq/scaling_cur_freq")
        if v:
            cur.append(v)
        mx = ctx.read_int(cpu + "/cpufreq/cpuinfo_max_freq")
        if mx and (max_khz is None or mx > max_khz):
            max_khz = mx
        mn = ctx.read_int(cpu + "/cpufreq/cpuinfo_min_freq")
        if mn and (min_khz is None or mn < min_khz):
            min_khz = mn
    if not cur:
        # /proc/cpuinfo "cpu MHz" is still populated on x86 without cpufreq.
        for b in _parse_cpuinfo(ctx.read("/proc/cpuinfo") or ""):
            try:
                cur.append(int(float(b["cpu MHz"]) * 1000))
            except (KeyError, ValueError):
                pass
    return {
        "currentMhz": round(sum(cur) / len(cur) / 1000.0, 0) if cur else None,
        "peakCurrentMhz": round(max(cur) / 1000.0, 0) if cur else None,
        "maxMhz": round(max_khz / 1000.0, 0) if max_khz else None,
        "minMhz": round(min_khz / 1000.0, 0) if min_khz else None,
    }


def scaling(ctx: Context) -> Dict[str, Optional[str]]:
    base = "/sys/devices/system/cpu/cpu0/cpufreq"
    return {
        "driver": ctx.read_line(base + "/scaling_driver"),
        "governor": ctx.read_line(base + "/scaling_governor"),
        "availableGovernors": ctx.read_line(base + "/scaling_available_governors"),
        "energyPerformancePreference": ctx.read_line(base + "/energy_performance_preference"),
        "boost": _boost_state(ctx),
    }


def _boost_state(ctx: Context) -> Optional[str]:
    v = ctx.read_line("/sys/devices/system/cpu/cpufreq/boost")
    if v is not None:
        return "enabled" if v == "1" else "disabled"
    v = ctx.read_line("/sys/devices/system/cpu/intel_pstate/no_turbo")
    if v is not None:
        return "disabled" if v == "1" else "enabled"
    return None


def find_temperature_sensor(ctx: Context) -> Optional[str]:
    """Return the sysfs path of the best CPU temperature input, or None.

    Callers that poll (telemetry) cache this path once instead of rescanning
    hwmon every tick.
    """
    candidates = []
    for hw in ctx.glob("/sys/class/hwmon/hwmon*"):
        name = (ctx.read_line(hw + "/name") or "").lower()
        if name not in _CPU_HWMON:
            continue
        rank = _CPU_HWMON.index(name)
        inputs = sorted(p for p in ctx.listdir(hw) if re.match(r"temp\d+_input$", p))
        best = None
        for inp in inputs:
            label = (ctx.read_line(hw + "/" + inp.replace("_input", "_label")) or "").lower()
            if label in _PREFERRED_LABELS:
                best = inp
                break
        if best is None and inputs:
            best = inputs[0]
        if best:
            candidates.append((rank, hw + "/" + best))
    if candidates:
        candidates.sort()
        return candidates[0][1]
    # Thermal-zone fallback (x86_pkg_temp on Intel, generic zones on ARM).
    for zone in ctx.glob("/sys/class/thermal/thermal_zone*"):
        ztype = (ctx.read_line(zone + "/type") or "").lower()
        if ztype in ("x86_pkg_temp", "cpu-thermal", "cpu_thermal", "soc_thermal"):
            return zone + "/temp"
    return None


def read_temperature(ctx: Context, sensor: Optional[str]) -> Optional[float]:
    if not sensor:
        return None
    millideg = ctx.read_int(sensor)
    if millideg is None:
        return None
    return round(millideg / 1000.0, 1)


def summary(ctx: Context) -> Dict[str, object]:
    sensor = find_temperature_sensor(ctx)
    data: Dict[str, object] = {}
    data.update(identity(ctx))
    data["topology"] = topology(ctx)
    data["frequency"] = frequency(ctx)
    data["scaling"] = scaling(ctx)
    data["temperatureC"] = read_temperature(ctx, sensor)
    data["temperatureSensor"] = sensor
    return data
