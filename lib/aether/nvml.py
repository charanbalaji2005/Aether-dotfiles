"""NVIDIA Management Library (NVML) through ctypes.

NVML is the library nvidia-smi itself uses (libnvidia-ml.so.1, installed
with the proprietary driver: on Fedora, xorg-x11-drv-nvidia-cuda-libs). Reading it
in-process means no subprocess per sample, no root, and access to per-process
GPU memory — which nvidia-smi's CSV query can't give cheaply.

Rules this module keeps:
  * It is never loaded or initialised for a GPU whose PCI runtime status is
    "suspended" (callers check first): nvmlInit itself wakes every NVIDIA GPU.
  * Every call is guarded; a missing symbol, an old driver or a GPU that
    doesn't support a counter yields None for that value, never an exception
    to the caller.
  * It never changes GPU state (no clocks, no power limits, no persistence mode).
"""

from __future__ import annotations

import ctypes
import ctypes.util
from typing import Any, Dict, List, Optional

NVML_SUCCESS = 0
NVML_TEMPERATURE_GPU = 0
NVML_CLOCK_GRAPHICS = 0


class _Memory(ctypes.Structure):
    _fields_ = [("total", ctypes.c_ulonglong), ("free", ctypes.c_ulonglong), ("used", ctypes.c_ulonglong)]


class _Utilization(ctypes.Structure):
    _fields_ = [("gpu", ctypes.c_uint), ("memory", ctypes.c_uint)]


class _ProcessInfo(ctypes.Structure):
    # nvmlProcessInfo_v1 layout: the oldest, accepted by every driver that
    # exports the un-suffixed nvmlDeviceGet*RunningProcesses symbols.
    _fields_ = [("pid", ctypes.c_uint), ("usedGpuMemory", ctypes.c_ulonglong)]


class NvmlUnavailable(Exception):
    pass


class Nvml:
    """A small, defensive wrapper. Construct once; call close() when done."""

    def __init__(self, lib: Any = None) -> None:
        self._lib = lib if lib is not None else self._load()
        rc = self._call("nvmlInit_v2") if hasattr(self._lib, "nvmlInit_v2") else self._call("nvmlInit")
        if rc != NVML_SUCCESS:
            raise NvmlUnavailable("nvmlInit failed (%s)" % self.error_string(rc))
        self._handles: Dict[str, Any] = {}

    @staticmethod
    def _load() -> Any:
        for name in ("libnvidia-ml.so.1", ctypes.util.find_library("nvidia-ml")):
            if not name:
                continue
            try:
                return ctypes.CDLL(name)
            except OSError:
                continue
        raise NvmlUnavailable("libnvidia-ml.so.1 not found (install the NVIDIA driver's CUDA/NVML libraries)")

    def _call(self, fn: str, *args: Any) -> int:
        f = getattr(self._lib, fn, None)
        if f is None:
            return -1
        try:
            return int(f(*args))
        except Exception:  # noqa: BLE001 — a foreign library: never let it crash telemetry
            return -1

    def error_string(self, rc: int) -> str:
        f = getattr(self._lib, "nvmlErrorString", None)
        if f is None or rc < 0:
            return "error %d" % rc
        try:
            f.restype = ctypes.c_char_p
        except AttributeError:
            pass  # not a ctypes function (tests); its return value is used as is
        try:
            out = f(rc)
            return out.decode("utf-8", "replace") if isinstance(out, bytes) else str(out)
        except Exception:  # noqa: BLE001
            return "error %d" % rc

    def close(self) -> None:
        self._call("nvmlShutdown")

    # -- devices -----------------------------------------------------------------
    @staticmethod
    def nvml_bus_id(sysfs_slot: str) -> str:
        """sysfs "0000:01:00.0" → NVML "00000000:01:00.0" (upper-case hex)."""
        dom, rest = sysfs_slot.split(":", 1)
        return ("%08X:%s" % (int(dom, 16), rest)).upper()

    def handle(self, slot: str) -> Optional[Any]:
        if slot in self._handles:
            return self._handles[slot]
        h = ctypes.c_void_p()
        bus = self.nvml_bus_id(slot).encode("ascii")
        fn = "nvmlDeviceGetHandleByPciBusId_v2" if hasattr(self._lib, "nvmlDeviceGetHandleByPciBusId_v2") else "nvmlDeviceGetHandleByPciBusId"
        if self._call(fn, ctypes.c_char_p(bus), ctypes.byref(h)) != NVML_SUCCESS:
            return None
        self._handles[slot] = h
        return h

    def driver_version(self) -> Optional[str]:
        buf = ctypes.create_string_buffer(96)
        if self._call("nvmlSystemGetDriverVersion", buf, ctypes.c_uint(96)) != NVML_SUCCESS:
            return None
        return buf.value.decode("ascii", "replace")

    def sample(self, slot: str) -> Dict[str, Any]:
        """usage (0-1), memUsage, vramUsed/Total (bytes), tempC, powerW,
        powerLimitW, clockMhz — each None when unsupported."""
        out: Dict[str, Any] = {"usage": None, "memUsage": None, "vramUsed": None, "vramTotal": None,
                               "tempC": None, "powerW": None, "powerLimitW": None, "clockMhz": None}
        h = self.handle(slot)
        if h is None:
            out["error"] = "device %s not found by NVML" % slot
            return out
        u = _Utilization()
        if self._call("nvmlDeviceGetUtilizationRates", h, ctypes.byref(u)) == NVML_SUCCESS:
            out["usage"] = min(1.0, u.gpu / 100.0)
            out["memUsage"] = min(1.0, u.memory / 100.0)
        m = _Memory()
        if self._call("nvmlDeviceGetMemoryInfo", h, ctypes.byref(m)) == NVML_SUCCESS:
            out["vramUsed"], out["vramTotal"] = int(m.used), int(m.total)
        t = ctypes.c_uint()
        if self._call("nvmlDeviceGetTemperature", h, ctypes.c_int(NVML_TEMPERATURE_GPU), ctypes.byref(t)) == NVML_SUCCESS:
            out["tempC"] = float(t.value)
        p = ctypes.c_uint()
        if self._call("nvmlDeviceGetPowerUsage", h, ctypes.byref(p)) == NVML_SUCCESS:
            out["powerW"] = round(p.value / 1000.0, 1)
        if self._call("nvmlDeviceGetEnforcedPowerLimit", h, ctypes.byref(p)) == NVML_SUCCESS:
            out["powerLimitW"] = round(p.value / 1000.0, 1)
        c = ctypes.c_uint()
        if self._call("nvmlDeviceGetClockInfo", h, ctypes.c_int(NVML_CLOCK_GRAPHICS), ctypes.byref(c)) == NVML_SUCCESS:
            out["clockMhz"] = float(c.value)
        return out

    def processes(self, slot: str, limit: int = 32) -> List[Dict[str, Any]]:
        """Processes with a context on the GPU: {pid, vram (bytes or None), kind}.
        Graphics and compute lists are merged by pid."""
        h = self.handle(slot)
        if h is None:
            return []
        merged: Dict[int, Dict[str, Any]] = {}
        for fn, kind in (("nvmlDeviceGetGraphicsRunningProcesses", "graphics"), ("nvmlDeviceGetComputeRunningProcesses", "compute")):
            count = ctypes.c_uint(limit)
            arr = (_ProcessInfo * limit)()
            if self._call(fn, h, ctypes.byref(count), arr) != NVML_SUCCESS:
                continue
            for i in range(min(count.value, limit)):
                pid = int(arr[i].pid)
                used = int(arr[i].usedGpuMemory)
                # NVML reports "not available" as ULLONG_MAX (common on WDDM/MIG/unprivileged).
                vram = None if used >= 0xFFFFFFFFFFFF0000 else used
                e = merged.setdefault(pid, {"pid": pid, "vram": vram, "kind": kind})
                if e["kind"] != kind:
                    e["kind"] = "graphics+compute"
                if vram is not None:
                    e["vram"] = max(e["vram"] or 0, vram)
        return sorted(merged.values(), key=lambda e: -(e["vram"] or 0))


def try_open() -> Optional[Nvml]:
    try:
        return Nvml()
    except NvmlUnavailable:
        return None
