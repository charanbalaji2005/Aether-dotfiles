"""aether.nvml against a fake libnvidia-ml (ctypes calls with byref outputs)."""

import ctypes
import unittest

from aether import nvml


class FakeLib:
    """Implements the NVML C functions used by aether.nvml, writing results
    through ctypes pointers exactly like the real library."""

    def __init__(self, fail_init=False, devices=("00000000:01:00.0",)):
        self.fail_init = fail_init
        self.devices = devices
        self.shutdowns = 0

    def nvmlInit_v2(self):
        return 3 if self.fail_init else 0

    def nvmlShutdown(self):
        self.shutdowns += 1
        return 0

    def nvmlErrorString(self, rc):
        return b"Driver Not Loaded"

    def nvmlSystemGetDriverVersion(self, buf, n):
        ctypes.memmove(buf, b"580.95.05\x00", 10)
        return 0

    def nvmlDeviceGetHandleByPciBusId_v2(self, bus, handle_ptr):
        return 0 if bus.value.decode() in self.devices else 6

    def nvmlDeviceGetUtilizationRates(self, h, ptr):
        u = ctypes.cast(ptr, ctypes.POINTER(nvml._Utilization)).contents
        u.gpu, u.memory = 37, 12
        return 0

    def nvmlDeviceGetMemoryInfo(self, h, ptr):
        m = ctypes.cast(ptr, ctypes.POINTER(nvml._Memory)).contents
        m.total, m.used, m.free = 6 << 30, 1 << 30, 5 << 30
        return 0

    def nvmlDeviceGetTemperature(self, h, sensor, ptr):
        ctypes.cast(ptr, ctypes.POINTER(ctypes.c_uint)).contents.value = 61
        return 0

    def nvmlDeviceGetPowerUsage(self, h, ptr):
        ctypes.cast(ptr, ctypes.POINTER(ctypes.c_uint)).contents.value = 18250
        return 0

    def nvmlDeviceGetEnforcedPowerLimit(self, h, ptr):
        return 999   # "not supported" on this fake: must become None

    def nvmlDeviceGetClockInfo(self, h, kind, ptr):
        ctypes.cast(ptr, ctypes.POINTER(ctypes.c_uint)).contents.value = 2370
        return 0

    def _procs(self, h, count_ptr, arr, rows):
        count = ctypes.cast(count_ptr, ctypes.POINTER(ctypes.c_uint)).contents
        for i, (pid, mem) in enumerate(rows):
            arr[i].pid, arr[i].usedGpuMemory = pid, mem
        count.value = len(rows)
        return 0

    def nvmlDeviceGetGraphicsRunningProcesses(self, h, count_ptr, arr):
        return self._procs(h, count_ptr, arr, [(100, 200 << 20), (200, 0xFFFFFFFFFFFFFFFF)])

    def nvmlDeviceGetComputeRunningProcesses(self, h, count_ptr, arr):
        return self._procs(h, count_ptr, arr, [(100, 500 << 20)])


class NvmlTests(unittest.TestCase):
    def test_bus_id_translation(self):
        self.assertEqual(nvml.Nvml.nvml_bus_id("0000:01:00.0"), "00000000:01:00.0")
        self.assertEqual(nvml.Nvml.nvml_bus_id("0001:0a:00.0"), "00000001:0A:00.0")

    def test_sample(self):
        n = nvml.Nvml(FakeLib())
        s = n.sample("0000:01:00.0")
        self.assertEqual(s["usage"], 0.37)
        self.assertEqual((s["vramUsed"], s["vramTotal"]), (1 << 30, 6 << 30))
        self.assertEqual((s["tempC"], s["powerW"], s["clockMhz"]), (61.0, 18.2, 2370.0))
        self.assertIsNone(s["powerLimitW"], "unsupported counters are None, not errors")
        self.assertEqual(n.driver_version(), "580.95.05")

    def test_unknown_device(self):
        s = nvml.Nvml(FakeLib()).sample("0000:02:00.0")
        self.assertIn("not found", s["error"])

    def test_processes_merge_and_unavailable_memory(self):
        procs = nvml.Nvml(FakeLib()).processes("0000:01:00.0")
        by_pid = {p["pid"]: p for p in procs}
        self.assertEqual(by_pid[100]["kind"], "graphics+compute")
        self.assertEqual(by_pid[100]["vram"], 500 << 20)
        self.assertIsNone(by_pid[200]["vram"], "ULLONG_MAX means 'not available'")

    def test_init_failure_raises_cleanly(self):
        with self.assertRaises(nvml.NvmlUnavailable) as cm:
            nvml.Nvml(FakeLib(fail_init=True))
        self.assertIn("Driver Not Loaded", str(cm.exception))

    def test_close(self):
        lib = FakeLib()
        nvml.Nvml(lib).close()
        self.assertEqual(lib.shutdowns, 1)


if __name__ == "__main__":
    unittest.main()
