import unittest

import fixtures
from aether.hw import cpu, gpu, system


class CpuDetection(unittest.TestCase):
    def test_intel_identity_topology_and_temperature(self):
        s = fixtures.nvidia_desktop()
        self.addCleanup(s.cleanup)
        info = cpu.summary(s.ctx())
        self.assertEqual(info["vendor"], "Intel")
        self.assertIn("i7-12700H", info["model"])
        self.assertEqual(info["topology"], {"threads": 8, "cores": 4, "sockets": 1})
        self.assertEqual(info["virtualization"], "Intel VT-x")
        self.assertEqual(info["kvmAvailable"], "yes")
        self.assertEqual(info["temperatureC"], 48.0, "must prefer the 'Package id 0' sensor over per-core sensors")
        self.assertEqual(info["scaling"]["driver"], "intel_pstate")
        self.assertEqual(info["scaling"]["boost"], "enabled")
        self.assertEqual(info["frequency"]["maxMhz"], 4700)

    def test_amd_identity_and_k10temp(self):
        s = fixtures.amd_desktop()
        self.addCleanup(s.cleanup)
        info = cpu.summary(s.ctx())
        self.assertEqual(info["vendor"], "AMD")
        self.assertEqual(info["topology"]["cores"], 8)
        self.assertEqual(info["topology"]["threads"], 16)
        self.assertEqual(info["virtualization"], "AMD-V")
        self.assertEqual(info["temperatureC"], 61.2)
        self.assertEqual(info["scaling"]["driver"], "amd-pstate-epp")

    def test_missing_everything_is_unavailable_not_invented(self):
        s = fixtures.empty_system()
        self.addCleanup(s.cleanup)
        info = cpu.summary(s.ctx())
        self.assertIsNone(info["model"])
        self.assertIsNone(info["temperatureC"])
        self.assertIsNone(info["frequency"]["currentMhz"])
        self.assertIsNone(info["topology"]["threads"])


class GpuDetection(unittest.TestCase):
    def test_nvidia_desktop(self):
        s = fixtures.nvidia_desktop()
        self.addCleanup(s.cleanup)
        gpus = gpu.detect(s.ctx())
        self.assertEqual(len(gpus), 1)
        g = gpus[0]
        self.assertEqual((g["vendor"], g["driver"], g["kind"], g["codename"]), ("nvidia", "nvidia", "discrete", "GA104"))
        self.assertTrue(g["bootVga"])
        self.assertEqual(g["drm"], {"card": "card0", "render": "renderD128"})
        topo = gpu.topology(gpus)
        self.assertEqual(topo["layout"], "single")
        self.assertTrue(topo["nvidiaIsPrimary"])

    def test_amd_gpu_is_discrete(self):
        s = fixtures.amd_desktop()
        self.addCleanup(s.cleanup)
        g = gpu.detect(s.ctx())[0]
        self.assertEqual((g["vendor"], g["driver"], g["kind"]), ("amd", "amdgpu", "discrete"))
        self.assertFalse(gpu.topology([g])["hasNvidia"])

    def test_intel_igpu(self):
        s = fixtures.intel_laptop()
        self.addCleanup(s.cleanup)
        g = gpu.detect(s.ctx())[0]
        self.assertEqual((g["vendor"], g["driver"], g["kind"]), ("intel", "i915", "integrated"))

    def test_hybrid_layout_orders_boot_gpu_first(self):
        s = fixtures.hybrid_laptop()
        self.addCleanup(s.cleanup)
        gpus = gpu.detect(s.ctx())
        self.assertEqual([g["vendor"] for g in gpus], ["intel", "nvidia"])
        topo = gpu.topology(gpus)
        self.assertEqual(topo["layout"], "hybrid")
        self.assertTrue(topo["hybrid"])
        self.assertFalse(topo["nvidiaIsPrimary"])
        self.assertEqual(gpus[1]["runtimeStatus"], "suspended")

    def test_pci_ids_fallback_when_lspci_missing(self):
        s = fixtures.amd_desktop()
        self.addCleanup(s.cleanup)
        s.bins.discard("lspci")
        s.file("/usr/share/hwdata/pci.ids", "1002  Advanced Micro Devices, Inc. [AMD/ATI]\n\t73df  Navi 22 [Radeon RX 6700 XT]\n\t\t1002 0e36  subsystem\n10de  NVIDIA Corporation\n")
        g = gpu.detect(s.ctx())[0]
        self.assertEqual(g["name"], "Navi 22 [Radeon RX 6700 XT]")

    def test_raw_id_when_no_name_source(self):
        s = fixtures.amd_desktop()
        self.addCleanup(s.cleanup)
        s.bins.discard("lspci")
        g = gpu.detect(s.ctx())[0]
        self.assertEqual(g["name"], "AMD device 1002:73df")

    def test_no_gpu(self):
        s = fixtures.empty_system()
        self.addCleanup(s.cleanup)
        self.assertEqual(gpu.detect(s.ctx()), [])
        self.assertEqual(gpu.topology([])["layout"], "none")

    def test_codename_parsing(self):
        cases = {
            "GA104 [GeForce RTX 3070]": "GA104",
            "AD102 [GeForce RTX 4090]": "AD102",
            "TU117M [GeForce GTX 1650 Mobile / Max-Q]": None,  # TU117M: suffix M isn't a code name
            "GP106 [GeForce GTX 1060 6GB]": "GP106",
            "GB202 [GeForce RTX 5090]": "GB202",
            "GK104 [GeForce GTX 770]": "GK104",
            "NVIDIA device 10de:abcd": None,
        }
        for name, want in cases.items():
            got = gpu.nvidia_codename(name)
            if want is None and name.startswith("TU117M"):
                # Mobile parts are written TU117M in pci.ids; must still map to Turing.
                self.assertIsNotNone(got, name)
                self.assertTrue(got.startswith("TU117"), got)
            else:
                self.assertEqual(got, want, name)


class SystemDetection(unittest.TestCase):
    def test_secure_boot_from_mokutil(self):
        s = fixtures.nvidia_desktop()
        self.addCleanup(s.cleanup)
        self.assertEqual(system.secure_boot(s.ctx())["state"], "enabled")

    def test_secure_boot_from_efivar_without_mokutil(self):
        s = fixtures.nvidia_desktop()
        self.addCleanup(s.cleanup)
        s.bins.discard("mokutil")
        del s.commands["mokutil --sb-state"]
        sb = system.secure_boot(s.ctx())
        self.assertEqual(sb, {"state": "enabled", "detail": "read from EFI variable"})

    def test_legacy_bios(self):
        s = fixtures.empty_system()
        self.addCleanup(s.cleanup)
        self.assertEqual(system.secure_boot(s.ctx())["state"], "unsupported")

    def test_fedora_and_hyprland_version(self):
        s = fixtures.nvidia_desktop()
        self.addCleanup(s.cleanup)
        ctx = s.ctx()
        self.assertTrue(system.is_fedora(ctx))
        self.assertEqual(system.kernel_release(ctx), fixtures.KERNEL)
        self.assertEqual(system.hyprland_version(ctx), "0.46.2")


if __name__ == "__main__":
    unittest.main()
