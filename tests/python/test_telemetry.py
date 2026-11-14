import unittest

import fixtures
from aether import telemetry


class Telemetry(unittest.TestCase):
    def test_cpu_usage_from_proc_stat_deltas(self):
        s = fixtures.amd_desktop()
        self.addCleanup(s.cleanup)
        sm = telemetry.Sampler(s.ctx())
        first = sm.sample()
        self.assertIsNone(first["cpu"]["usage"], "no delta yet -> unknown, not 0")
        # +300 busy, +100 idle jiffies => 75% busy
        s.file("/proc/stat", "cpu  1200 0 600 8100 100 0 0 0 0 0\ncpu0 600 0 300 4050 50 0 0 0 0 0\ncpu1 600 0 300 4050 50 0 0 0 0 0\n")
        second = sm.sample()
        self.assertAlmostEqual(second["cpu"]["usage"], 0.75, places=3)
        self.assertEqual(len(second["cpu"]["cores"]), 2)
        self.assertEqual(second["cpu"]["tempC"], 61.2)

    def test_memory_swap_load_uptime(self):
        s = fixtures.amd_desktop()
        self.addCleanup(s.cleanup)
        d = telemetry.Sampler(s.ctx()).sample()
        self.assertEqual(d["mem"]["total"], 32768000 * 1024)
        self.assertEqual(d["mem"]["used"], (32768000 - 20000000) * 1024)
        self.assertEqual(d["mem"]["swapUsed"], (8388604 - 8000000) * 1024)
        self.assertEqual(d["load"], [0.52, 0.48, 0.40])
        self.assertEqual(d["uptime"], 12345.67)

    def test_network_rate_uses_default_route_interface(self):
        s = fixtures.amd_desktop()
        self.addCleanup(s.cleanup)
        sm = telemetry.Sampler(s.ctx())
        sm.sample()
        sm._last_net_t -= 2.0  # pretend two seconds passed
        s.file("/proc/net/dev",
               "h1\nh2\n    lo: 9999999 10 0 0 0 0 0 0 9999999 10 0 0 0 0 0 0\n"
               "wlp2s0: 700000 400 0 0 0 0 0 0 140000 300 0 0 0 0 0 0\n")
        net = sm.sample()["net"]
        self.assertEqual(net["iface"], "wlp2s0")
        self.assertAlmostEqual(net["rxBps"], 100000, delta=2000)  # loopback traffic excluded
        self.assertAlmostEqual(net["txBps"], 20000, delta=500)

    def test_amd_gpu_metrics(self):
        s = fixtures.amd_desktop()
        self.addCleanup(s.cleanup)
        g = telemetry.Sampler(s.ctx()).sample()["gpus"][0]
        self.assertEqual(g["usage"], 0.37)
        self.assertEqual(g["tempC"], 52.0)
        self.assertEqual(g["vramTotal"], 12884901888)
        self.assertEqual(g["powerW"], 35.0)

    def test_intel_reports_usage_unavailable_with_reason(self):
        s = fixtures.intel_laptop()
        self.addCleanup(s.cleanup)
        g = telemetry.Sampler(s.ctx()).sample()["gpus"][0]
        self.assertIsNone(g["usage"])
        self.assertEqual(g["clockMhz"], 350)
        self.assertIn("perf counters", g["note"])

    def test_sleeping_dgpu_is_never_woken(self):
        s = fixtures.hybrid_laptop()
        self.addCleanup(s.cleanup)
        ctx = s.ctx()
        sm = telemetry.Sampler(ctx)
        data = sm.sample()
        nv = [g for g in data["gpus"] if g["vendor"] == "nvidia"][0]
        self.assertEqual(nv["state"], "suspended")
        self.assertIsNone(nv["usage"])
        self.assertFalse(any(c.startswith("nvidia-smi") for c in ctx.calls), ctx.calls)

    def test_awake_hybrid_dgpu_uses_one_shot_query(self):
        s = fixtures.hybrid_laptop()
        self.addCleanup(s.cleanup)
        s.file("/sys/bus/pci/devices/0000:01:00.0/power/runtime_status", "active\n")
        s.cmd("nvidia-smi --query-gpu=pci.bus_id,utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw,clocks.gr "
              "--format=csv,noheader,nounits -i 0000:01:00.0",
              "00000000:01:00.0, 23, 51, 512, 4096, 9.85, 1395\n")
        # Bar-level sampling must not touch an awake hybrid dGPU (any query
        # resets its autosuspend timer and would keep it awake).
        ctx = s.ctx()
        nv = [g for g in telemetry.Sampler(ctx).sample()["gpus"] if g["vendor"] == "nvidia"][0]
        self.assertIsNone(nv["usage"])
        self.assertIn("keeps the GPU awake", nv["note"])
        self.assertFalse(any(c.startswith("nvidia-smi") for c in ctx.calls), ctx.calls)
        # A detail view (processes=True) gets one-shot counters (nvidia-smi here: no NVML in fixtures).
        nv = [g for g in telemetry.Sampler(s.ctx(), processes=True).sample()["gpus"] if g["vendor"] == "nvidia"][0]
        self.assertEqual((nv["usage"], nv["tempC"], nv["vramTotal"]), (0.23, 51.0, 4096 * 1048576))

    def test_nvml_preferred_on_desktop_gpu(self):
        s = fixtures.nvidia_desktop()
        self.addCleanup(s.cleanup)
        fake = FakeNvml()
        sm = telemetry.Sampler(s.ctx(), processes=True)
        sm.nvml_factory = lambda: fake
        g = sm.sample()["gpus"][0]
        self.assertEqual(g["source"], "nvml")
        self.assertEqual((g["usage"], g["vramUsed"], g["powerLimitW"]), (0.42, 2 << 30, 115.0))
        self.assertEqual(g["processes"][0]["pid"], 4242)
        self.assertFalse([c for c in sm.ctx.calls if c.startswith("nvidia-smi")], "no subprocess when NVML works")
        self.assertEqual(fake.closed, 0, "desktop GPUs keep one NVML session")

    def test_nvml_on_hybrid_is_transient_and_only_for_detail_views(self):
        s = fixtures.hybrid_laptop()
        self.addCleanup(s.cleanup)
        s.file("/sys/bus/pci/devices/0000:01:00.0/power/runtime_status", "active\n")
        opened = []

        def factory():
            f = FakeNvml()
            opened.append(f)
            return f
        bar = telemetry.Sampler(s.ctx())
        bar.nvml_factory = factory
        bar.sample()
        self.assertEqual(opened, [], "bar sampling never opens NVML on a hybrid dGPU")
        detail = telemetry.Sampler(s.ctx(), processes=True)
        detail.nvml_factory = factory
        g = [x for x in detail.sample()["gpus"] if x["vendor"] == "nvidia"][0]
        self.assertEqual(g["usage"], 0.42)
        self.assertEqual(len(opened), 1)
        self.assertEqual(opened[0].closed, 1, "the session is closed right after the sample")

    def test_nvml_failure_falls_back(self):
        s = fixtures.nvidia_desktop()
        self.addCleanup(s.cleanup)

        def broken():
            raise OSError("no libnvidia-ml")
        sm = telemetry.Sampler(s.ctx())
        sm.nvml_factory = broken
        g = sm.sample()["gpus"][0]
        self.assertNotEqual(g.get("source"), "nvml")

    def test_nvidia_without_smi_explains(self):
        s = fixtures.nvidia_desktop()
        self.addCleanup(s.cleanup)
        s.bins.discard("nvidia-smi")
        g = telemetry.Sampler(s.ctx()).sample()["gpus"][0]
        self.assertIsNone(g["usage"])
        self.assertIn("nvidia-smi not installed", g["note"])

    def test_nvidia_smi_parser(self):
        row = telemetry.parse_nvidia_smi_line("00000000:01:00.0, 87, 71, 6144, 8192, [N/A], 1905\n")
        self.assertEqual(row["bus"], "0000:01:00.0")
        self.assertEqual(row["usage"], 0.87)
        self.assertIsNone(row["powerW"], "[N/A] must become null, not 0")
        self.assertIsNone(telemetry.parse_nvidia_smi_line("garbage"))

    def test_empty_system_degrades_to_nulls(self):
        s = fixtures.empty_system()
        self.addCleanup(s.cleanup)
        sm = telemetry.Sampler(s.ctx())
        sm.sample()
        d = sm.sample()
        self.assertIsNone(d["cpu"]["usage"])
        self.assertIsNone(d["cpu"]["tempC"])
        self.assertIsNotNone(d["cpu"]["tempNote"])
        self.assertEqual(d["gpus"], [])
        self.assertIsNone(d["mem"]["total"])
        self.assertFalse(d["net"]["connected"])

    def test_process_table(self):
        s = fixtures.amd_desktop()
        self.addCleanup(s.cleanup)
        stat = "{pid} ({name}) S 1 1 1 0 -1 4194304 100 0 0 0 {ut} {st} 0 0 20 0 1 0 100 1000000 {rss} 0 0 0\n"
        s.file("/proc/100/stat", stat.format(pid=100, name="firefox", ut=100, st=50, rss=50000))
        s.file("/proc/200/stat", stat.format(pid=200, name="Web Content", ut=10, st=5, rss=20000))
        sm = telemetry.Sampler(s.ctx(), processes=True)
        self.assertEqual(sm.sample()["procs"], [], "first sample has no deltas")
        s.file("/proc/stat", "cpu  1200 0 600 8100 100 0 0 0 0 0\n")  # +400 jiffies total
        s.file("/proc/100/stat", stat.format(pid=100, name="firefox", ut=180, st=70, rss=50000))
        procs = sm.sample()["procs"]
        self.assertEqual(procs[0]["name"], "firefox")
        self.assertGreater(procs[0]["cpu"], procs[1]["cpu"])
        self.assertEqual(procs[1]["name"], "Web Content")


if __name__ == "__main__":
    unittest.main()


class FakeNvml:
    """Stands in for aether.nvml.Nvml in tests (the real one needs the driver)."""

    def __init__(self):
        self.closed = 0

    def sample(self, slot):
        return {"usage": 0.42, "memUsage": 0.1, "vramUsed": 2 << 30, "vramTotal": 6 << 30, "tempC": 55.0,
                "powerW": 21.5, "powerLimitW": 115.0, "clockMhz": 1800.0}

    def processes(self, slot):
        return [{"pid": 4242, "vram": 300 << 20, "kind": "graphics"}]

    def close(self):
        self.closed += 1



class NvmlFailures(unittest.TestCase):
    def test_nvml_failure_reason_is_reported_not_zeroes(self):
        s = fixtures.nvidia_desktop()
        self.addCleanup(s.cleanup)
        s.bins.discard("nvidia-smi")

        def mismatch():
            raise RuntimeError("nvmlInit failed (Driver/library version mismatch) — reboot after a driver update")
        sm = telemetry.Sampler(s.ctx())
        sm.nvml_factory = mismatch
        g = sm.sample()["gpus"][0]
        self.assertIsNone(g["usage"])
        self.assertIsNone(g["vramUsed"])
        self.assertIn("version mismatch", g["note"])

    def test_close_releases_the_nvml_session(self):
        s = fixtures.nvidia_desktop()
        self.addCleanup(s.cleanup)
        fake = FakeNvml()
        sm = telemetry.Sampler(s.ctx())
        sm.nvml_factory = lambda: fake
        sm.sample()
        sm.close()
        self.assertEqual(fake.closed, 1)
