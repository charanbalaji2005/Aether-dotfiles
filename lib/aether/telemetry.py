"""Live system telemetry, streamed as one JSON object per line.

The shell runs ONE long-lived ``aether telemetry --stream`` process instead
of forking cat/df/nvidia-smi every couple of seconds. Per tick it reads a
handful of /proc and sysfs files (microseconds each) and prints a line.

Rules that keep idle cost low and values honest:

* Sensor paths are discovered once at start-up, not rescanned per tick.
* A discrete GPU whose PCI runtime status is "suspended" is NOT queried —
  reading its counters (or running nvidia-smi) would wake it up and drain
  a laptop battery. It is reported as ``state: "suspended"``.
* NVIDIA desktop GPUs are read from a single ``nvidia-smi -lms`` child that
  streams its own samples; hybrid NVIDIA dGPUs use one-shot queries only
  while awake.
* Every metric that cannot be read is ``null`` with a ``note`` saying why.
  Nothing is estimated or invented.
* The per-process table is only computed when ``--processes`` is passed
  (the dashboard starts a second stream with it only while it is visible).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
import time
from typing import Any, Dict, List, Optional

from .hw import cpu as cpu_mod
from .hw import gpu as gpu_mod
from .util import Context

_NV_FIELDS = "pci.bus_id,utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw,clocks.gr"
_VIRTUAL_IFACES = ("lo", "docker", "veth", "br-", "virbr", "vnet", "tun", "tap", "wg", "tailscale", "zt", "podman", "cni", "flannel")


def _num(text: Optional[str]) -> Optional[float]:
    if text is None:
        return None
    text = text.strip()
    if not text or text.startswith("[") or text.lower() in ("n/a", "[n/a]", "not supported"):
        return None
    try:
        return float(text)
    except ValueError:
        return None


class _NvidiaSmiStream:
    """Background reader for `nvidia-smi --query-gpu ... -lms N`."""

    def __init__(self, interval_ms: int):
        self.latest: Dict[str, Dict[str, Optional[float]]] = {}
        self.error: Optional[str] = None
        self._proc: Optional[subprocess.Popen] = None
        try:
            self._proc = subprocess.Popen(
                ["nvidia-smi", "--query-gpu=" + _NV_FIELDS, "--format=csv,noheader,nounits", "-lms", str(interval_ms)],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                bufsize=1,
            )
        except OSError as exc:
            self.error = str(exc)
            return
        threading.Thread(target=self._pump, daemon=True).start()

    def _pump(self) -> None:
        assert self._proc is not None and self._proc.stdout is not None
        for line in self._proc.stdout:
            row = parse_nvidia_smi_line(line)
            if row:
                self.latest[row["bus"]] = row  # type: ignore[index]
        self.error = "nvidia-smi exited"

    def stop(self) -> None:
        if self._proc and self._proc.poll() is None:
            self._proc.terminate()


def parse_nvidia_smi_line(line: str) -> Optional[Dict[str, object]]:
    parts = [p.strip() for p in line.split(",")]
    if len(parts) < 7:
        return None
    bus = parts[0].lower()
    # nvidia-smi reports 00000000:01:00.0; sysfs uses 0000:01:00.0.
    if bus.count(":") == 2 and len(bus.split(":")[0]) == 8:
        bus = bus[4:]
    used, total = _num(parts[3]), _num(parts[4])
    return {
        "bus": bus,
        "usage": None if _num(parts[1]) is None else _num(parts[1]) / 100.0,  # type: ignore[operator]
        "tempC": _num(parts[2]),
        "vramUsed": None if used is None else int(used * 1048576),
        "vramTotal": None if total is None else int(total * 1048576),
        "powerW": _num(parts[5]),
        "clockMhz": _num(parts[6]),
    }


class Sampler:
    def __init__(self, ctx: Context, interval: float = 2.0, processes: bool = False, process_limit: int = 8, stream_nvidia: bool = False):
        self.ctx = ctx
        self.interval = interval
        self.processes = processes
        self.process_limit = process_limit
        self._last_cpu: Optional[List[int]] = None
        self._last_cores: Optional[List[List[int]]] = None
        self._last_net: Optional[Dict[str, int]] = None
        self._last_net_t: Optional[float] = None
        self._last_proc: Dict[int, int] = {}
        self._last_proc_total: Optional[int] = None
        self._page = os.sysconf("SC_PAGE_SIZE") if hasattr(os, "sysconf") else 4096
        self._ncpu = os.cpu_count() or 1
        self.cpu_sensor = cpu_mod.find_temperature_sensor(ctx)
        self.freq_files = [p + "/cpufreq/scaling_cur_freq" for p in ctx.glob("/sys/devices/system/cpu/cpu[0-9]*") if ctx.exists(p + "/cpufreq/scaling_cur_freq")]
        self.gpus = self._discover_gpus()
        self._nv_stream: Optional[_NvidiaSmiStream] = None
        # NVML (in-process, no subprocess) is preferred. It is opened lazily,
        # only once an NVIDIA GPU is known to be awake (nvmlInit wakes GPUs).
        self._nvml: Any = None
        self._nvml_failed = False
        self.nvml_factory = None  # tests inject a fake here
        nv_desktop = [g for g in self.gpus if g["vendor"] == "nvidia" and g["driver"] == "nvidia" and not g["_runtimePm"]]
        if stream_nvidia and not processes and nv_desktop and ctx.is_live and ctx.which("nvidia-smi") and not self._nvml_usable():
            self._nv_stream = _NvidiaSmiStream(int(interval * 1000))

    def _nvml_usable(self) -> bool:
        if self._nvml is not None:
            return True
        if self._nvml_failed or not (self.ctx.is_live or self.nvml_factory):
            return False
        try:
            if self.nvml_factory is not None:
                self._nvml = self.nvml_factory()
            else:
                from . import nvml as nvml_mod
                self._nvml = nvml_mod.Nvml()
        except Exception:  # noqa: BLE001 — NvmlUnavailable or a broken library
            self._nvml_failed = True
            self._nvml = None
        return self._nvml is not None

    def _name_processes(self, procs: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        for p in procs:
            p["name"] = (self.ctx.read_line("/proc/%d/comm" % p["pid"]) or "").strip() or None
        return procs

    def _nvml_transient(self, slot: str) -> Optional[Dict[str, Any]]:
        """Open NVML, sample one GPU (+ processes), close it again."""
        try:
            if self.nvml_factory is not None:
                lib = self.nvml_factory()
            elif self.ctx.is_live:
                from . import nvml as nvml_mod
                lib = nvml_mod.Nvml()
            else:
                return None
        except Exception:  # noqa: BLE001
            return None
        try:
            row = lib.sample(slot)
            if row.get("error"):
                return None
            row["_processes"] = lib.processes(slot)
            return row
        finally:
            lib.close()

    # -- discovery ---------------------------------------------------------
    def _discover_gpus(self) -> List[Dict[str, object]]:
        out = []
        topo_gpus = gpu_mod.detect(self.ctx)
        hybrid = gpu_mod.topology(topo_gpus)["hybrid"]
        for g in topo_gpus:
            if g["kind"] == "virtual":
                continue
            dev = g["sysfsPath"]
            hwmon = None
            for h in self.ctx.glob(dev + "/hwmon/hwmon*"):
                hwmon = h
                break
            entry = {
                "slot": g["slot"],
                "vendor": g["vendor"],
                "name": g["name"],
                "driver": g["driver"],
                "kind": g["kind"],
                "_dev": dev,
                "_hwmon": hwmon,
                # Runtime PM only matters for secondary GPUs on hybrid systems.
                "_runtimePm": bool(hybrid and not g["bootVga"] and g["runtimeStatus"] is not None),
                "_card": g["drm"].get("card"),
            }
            out.append(entry)
        return out

    # -- readers -----------------------------------------------------------
    def _cpu(self) -> Dict[str, object]:
        text = self.ctx.read("/proc/stat") or ""
        usage = None
        cores: List[float] = []
        totals: List[List[int]] = []
        for line in text.splitlines():
            if not line.startswith("cpu"):
                break
            fields = [int(x) for x in line.split()[1:]]
            if len(fields) < 4:
                continue
            idle = fields[3] + (fields[4] if len(fields) > 4 else 0)
            # guest/guest_nice are already included in user/nice.
            total = sum(fields[:8]) if len(fields) >= 8 else sum(fields)
            if line.startswith("cpu "):
                if self._last_cpu:
                    dt, di = total - self._last_cpu[0], idle - self._last_cpu[1]
                    usage = max(0.0, min(1.0, 1 - di / dt)) if dt > 0 else None
                self._last_cpu = [total, idle]
            else:
                totals.append([total, idle])
        if self._last_cores and len(self._last_cores) == len(totals):
            for (t, i), (lt, li) in zip(totals, self._last_cores):
                dt = t - lt
                cores.append(round(max(0.0, min(1.0, 1 - (i - li) / dt)), 3) if dt > 0 else 0.0)
        self._last_cores = totals
        freqs = [self.ctx.read_int(f) for f in self.freq_files]
        freqs = [f for f in freqs if f]
        return {
            "usage": None if usage is None else round(usage, 4),
            "cores": cores,
            "freqMhz": round(sum(freqs) / len(freqs) / 1000.0) if freqs else None,
            "tempC": cpu_mod.read_temperature(self.ctx, self.cpu_sensor),
            "tempNote": None if self.cpu_sensor else "no CPU temperature sensor exposed (coretemp/k10temp not loaded?)",
        }

    def _mem(self) -> Dict[str, Optional[int]]:
        vals: Dict[str, int] = {}
        for line in (self.ctx.read("/proc/meminfo") or "").splitlines():
            key, _, rest = line.partition(":")
            if key in ("MemTotal", "MemAvailable", "SwapTotal", "SwapFree"):
                try:
                    vals[key] = int(rest.split()[0]) * 1024
                except (ValueError, IndexError):
                    pass
        total, avail = vals.get("MemTotal"), vals.get("MemAvailable")
        st, sf = vals.get("SwapTotal"), vals.get("SwapFree")
        return {
            "total": total,
            "used": (total - avail) if total is not None and avail is not None else None,
            "swapTotal": st,
            "swapUsed": (st - sf) if st is not None and sf is not None else None,
        }

    def _disk(self, mount: str = "/") -> Dict[str, Optional[int]]:
        try:
            st = os.statvfs(self.ctx.path(mount))
        except (OSError, AttributeError):
            return {"mount": mount, "total": None, "used": None}  # type: ignore[dict-item]
        total = st.f_blocks * st.f_frsize
        free = st.f_bavail * st.f_frsize
        return {"mount": mount, "total": total, "used": total - free}  # type: ignore[dict-item]

    def _default_iface(self) -> Optional[str]:
        for line in (self.ctx.read("/proc/net/route") or "").splitlines()[1:]:
            parts = line.split()
            if len(parts) > 2 and parts[1] == "00000000":
                return parts[0]
        return None

    def _net(self, now: float) -> Dict[str, object]:
        rx_tot = tx_tot = 0
        default = self._default_iface()
        for line in (self.ctx.read("/proc/net/dev") or "").splitlines()[2:]:
            name, _, rest = line.partition(":")
            name = name.strip()
            if not name:
                continue
            # With a default route, count exactly that interface (even a VPN
            # tunnel); otherwise sum the physical-looking interfaces.
            if default:
                if name != default:
                    continue
            elif name.startswith(_VIRTUAL_IFACES):
                continue
            f = rest.split()
            if len(f) < 9:
                continue
            rx_tot += int(f[0])
            tx_tot += int(f[8])
        counters = {"rx": rx_tot, "tx": tx_tot}
        rx_bps = tx_bps = None
        if self._last_net is not None and self._last_net_t is not None:
            dt = now - self._last_net_t
            if dt > 0:
                rx_bps = max(0, int((counters["rx"] - self._last_net["rx"]) / dt))
                tx_bps = max(0, int((counters["tx"] - self._last_net["tx"]) / dt))
        self._last_net, self._last_net_t = counters, now
        return {"iface": default, "rxBps": rx_bps, "txBps": tx_bps, "connected": default is not None}

    def _gpu(self, g: Dict[str, object]) -> Dict[str, object]:
        dev = str(g["_dev"])
        out: Dict[str, object] = {
            "slot": g["slot"], "vendor": g["vendor"], "name": g["name"], "kind": g["kind"],
            "state": "active", "usage": None, "tempC": None, "vramUsed": None, "vramTotal": None,
            "powerW": None, "clockMhz": None, "note": None,
        }
        if g["_runtimePm"]:
            rs = self.ctx.read_line(dev + "/power/runtime_status")
            if rs == "suspended":
                out["state"] = "suspended"
                out["note"] = "discrete GPU asleep (not queried, to save power)"
                return out
        vendor = g["vendor"]
        if vendor == "nvidia":
            if g["driver"] != "nvidia":
                out["note"] = "telemetry needs the proprietary NVIDIA driver (current: %s)" % (g["driver"] or "none")
                return out
            row = None
            if g["_runtimePm"]:
                # Hybrid laptop dGPU, currently awake. Any open handle (NVML or
                # nvidia-smi) resets its autosuspend timer, so periodic sampling
                # would keep it awake forever. Counters are read only while a
                # detail view asks for them (processes=True), and then with a
                # transient NVML session that is closed straight away.
                if not self.processes:
                    out["note"] = "awake; open the dashboard for live counters (reading them keeps the GPU awake)"
                    return out
                row = self._nvml_transient(str(g["slot"]))
                if row is not None:
                    out["source"] = "nvml"
                    out["powerLimitW"] = row.get("powerLimitW")
                    out["processes"] = self._name_processes(row.pop("_processes", []))
                    for k in ("usage", "tempC", "vramUsed", "vramTotal", "powerW", "clockMhz"):
                        out[k] = row.get(k)
                    return out
            if row is None and self._nvml_usable() and not g["_runtimePm"]:
                row = self._nvml.sample(str(g["slot"]))
                out["source"] = "nvml"
                if row.get("error"):
                    out["note"] = row["error"]
                    row = None
                else:
                    out["powerLimitW"] = row.get("powerLimitW")
                    if self.processes:
                        out["processes"] = self._name_processes(self._nvml.processes(str(g["slot"])))
            elif self._nv_stream is not None:
                row = self._nv_stream.latest.get(str(g["slot"]).lower())
                if row is None and self._nv_stream.error:
                    out["note"] = "nvidia-smi stream unavailable"
            elif self.ctx.which("nvidia-smi"):
                res = self.ctx.run(["nvidia-smi", "--query-gpu=" + _NV_FIELDS, "--format=csv,noheader,nounits", "-i", str(g["slot"])], timeout=5)
                row = parse_nvidia_smi_line(res.out.splitlines()[0]) if res.ok and res.out.strip() else None
            else:
                out["note"] = "nvidia-smi not installed (xorg-x11-drv-nvidia-cuda)"
            if row:
                for k in ("usage", "tempC", "vramUsed", "vramTotal", "powerW", "clockMhz"):
                    out[k] = row.get(k)
            return out
        if vendor == "amd":
            busy = self.ctx.read_int(dev + "/gpu_busy_percent")
            out["usage"] = None if busy is None else busy / 100.0
            out["vramUsed"] = self.ctx.read_int(dev + "/mem_info_vram_used")
            out["vramTotal"] = self.ctx.read_int(dev + "/mem_info_vram_total")
        elif vendor == "intel":
            card = g["_card"]
            freq = None
            if card:
                freq = self.ctx.read_int("/sys/class/drm/%s/gt_cur_freq_mhz" % card) or self.ctx.read_int(
                    "/sys/class/drm/%s/device/tile0/gt0/freq0/cur_freq" % card
                )
            out["clockMhz"] = freq
            out["note"] = "Intel GPU utilisation needs perf counters (intel_gpu_top as root); showing clock only"
        if g["_hwmon"]:
            hw = str(g["_hwmon"])
            t = self.ctx.read_int(hw + "/temp1_input")
            out["tempC"] = None if t is None else round(t / 1000.0, 1)
            p = self.ctx.read_int(hw + "/power1_average") or self.ctx.read_int(hw + "/power1_input")
            out["powerW"] = None if p is None else round(p / 1e6, 1)
        return out

    def _processes(self) -> List[Dict[str, object]]:
        total_jiffies = None
        line = (self.ctx.read("/proc/stat") or "").split("\n", 1)[0]
        if line.startswith("cpu "):
            f = [int(x) for x in line.split()[1:]]
            total_jiffies = sum(f[:8]) if len(f) >= 8 else sum(f)
        current: Dict[int, int] = {}
        rows = []
        for pid_s in self.ctx.listdir("/proc"):
            if not pid_s.isdigit():
                continue
            stat = self.ctx.read("/proc/%s/stat" % pid_s)
            if not stat:
                continue
            rp = stat.rfind(")")
            name = stat[stat.find("(") + 1 : rp]
            fields = stat[rp + 2 :].split()
            if len(fields) < 22:
                continue
            pid = int(pid_s)
            ticks = int(fields[11]) + int(fields[12])
            rss = int(fields[21]) * self._page
            current[pid] = ticks
            rows.append([pid, name, ticks, rss])
        out = []
        if self._last_proc_total is not None and total_jiffies is not None:
            dt = total_jiffies - self._last_proc_total
            for pid, name, ticks, rss in rows:
                prev = self._last_proc.get(pid)
                share = ((ticks - prev) / dt * self._ncpu) if (prev is not None and dt > 0) else 0.0
                out.append({"pid": pid, "name": name, "cpu": round(max(0.0, share), 4), "rss": rss})
            out.sort(key=lambda r: (r["cpu"], r["rss"]), reverse=True)  # type: ignore[arg-type,return-value]
            out = out[: self.process_limit]
        self._last_proc, self._last_proc_total = current, total_jiffies
        return out

    # -- public --------------------------------------------------------------
    def sample(self) -> Dict[str, object]:
        now = time.time()
        data: Dict[str, object] = {"t": round(now, 3)}
        if self.processes:
            # The detail stream (dashboard / System Centre open): process list
            # plus full GPU counters, including hybrid dGPUs and GPU processes.
            data["procs"] = self._processes()
            data["gpus"] = [self._gpu(g) for g in self.gpus]
            return data
        load = (self.ctx.read_line("/proc/loadavg") or "").split()
        up = (self.ctx.read_line("/proc/uptime") or "").split()
        data.update(
            {
                "cpu": self._cpu(),
                "mem": self._mem(),
                "disk": self._disk("/"),
                "net": self._net(now),
                "gpus": [self._gpu(g) for g in self.gpus],
                "load": [float(x) for x in load[:3]] if len(load) >= 3 else None,
                "uptime": float(up[0]) if up else None,
            }
        )
        return data

    def close(self) -> None:
        if self._nv_stream:
            self._nv_stream.stop()


def stream(ctx: Context, interval: float, processes: bool, count: Optional[int] = None) -> int:
    sampler = Sampler(ctx, interval=interval, processes=processes, stream_nvidia=True)
    emitted = 0
    try:
        # Prime the delta counters so the first emitted line already has rates.
        sampler.sample()
        time.sleep(min(0.5, interval))
        while True:
            line = json.dumps(sampler.sample(), separators=(",", ":"))
            sys.stdout.write(line + "\n")
            sys.stdout.flush()
            emitted += 1
            if count is not None and emitted >= count:
                return 0
            time.sleep(interval)
    except (BrokenPipeError, KeyboardInterrupt):
        # The shell went away; exit quietly instead of tracing back.
        try:
            sys.stdout = open(os.devnull, "w")
        except OSError:
            pass
        return 0
    finally:
        sampler.close()


def snapshot(ctx: Context, processes: bool = False) -> Dict[str, object]:
    """Single sample with valid rates (two reads 0.5s apart)."""
    sampler = Sampler(ctx, interval=0.5, processes=processes)
    try:
        sampler.sample()
        time.sleep(0.5)
        return sampler.sample()
    finally:
        sampler.close()
