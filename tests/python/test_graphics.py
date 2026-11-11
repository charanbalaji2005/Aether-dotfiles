import os
import tempfile
import unittest

import fixtures
from aether.graphics import hyprconf, nvidia, report
from aether.hw import gpu


def active_lines(text):
    return [l.strip() for l in text.splitlines() if l.strip() and not l.strip().startswith("#")]


class DriverBranchSelection(unittest.TestCase):
    def _rec(self, name, device="2484"):
        s = fixtures.nvidia_no_driver(name, device)
        self.addCleanup(s.cleanup)
        g = gpu.detect(s.ctx())[0]
        return nvidia.recommend(s.ctx(), g)

    def test_current_generations_use_akmod_nvidia(self):
        for name in ("GA104 [GeForce RTX 3070]", "AD102 [GeForce RTX 4090]", "TU117M [GeForce GTX 1650 Mobile / Max-Q]", "GB202 [GeForce RTX 5090]"):
            r = self._rec(name)
            self.assertEqual(r["package"], "akmod-nvidia", name)
            self.assertTrue(r["hyprlandSupported"])
            self.assertIn("xorg-x11-drv-nvidia-cuda", r["extras"])

    def test_pascal_prefers_580xx_when_repo_has_it(self):
        s = fixtures.nvidia_no_driver()
        self.addCleanup(s.cleanup)
        s.cmd("dnf -q list --available akmod-nvidia-580xx", "Available Packages\nakmod-nvidia-580xx.x86_64  3:580.95.05-1.fc41  rpmfusion-nonfree-updates\n")
        r = nvidia.recommend(s.ctx(), gpu.detect(s.ctx())[0])
        self.assertEqual((r["architecture"], r["package"]), ("Pascal", "akmod-nvidia-580xx"))

    def test_pascal_falls_back_with_explicit_warning(self):
        r = self._rec("GP106 [GeForce GTX 1060 6GB]")
        self.assertEqual(r["package"], "akmod-nvidia")
        self.assertTrue(any("580" in n for n in r["notes"]))

    def test_kepler_is_never_installed(self):
        r = self._rec("GK104 [GeForce GTX 770]")
        self.assertIsNone(r["package"])
        self.assertFalse(r["hyprlandSupported"])
        self.assertIn("GBM", r["reason"])

    def test_fermi_is_never_installed(self):
        r = self._rec("GF108 [GeForce GT 430]")
        self.assertIsNone(r["package"])

    def test_unknown_gpu_is_never_guessed(self):
        r = self._rec("Device 2f04")
        self.assertIsNone(r["package"])
        self.assertIn("Refusing", r["reason"])


class InstallPlan(unittest.TestCase):
    def _all_argv(self, plan):
        return [" ".join(st["argv"]) for st in plan["steps"]]

    def test_fresh_install_with_secure_boot(self):
        s = fixtures.nvidia_no_driver("GA106 [GeForce RTX 3060]")
        self.addCleanup(s.cleanup)
        plan = nvidia.install_plan(s.ctx())
        self.assertTrue(plan["ok"], plan["blockers"])
        cmds = self._all_argv(plan)
        self.assertTrue(any("rpmfusion-free-release-41" in c and "rpmfusion-nonfree-release-41" in c for c in cmds), cmds)
        self.assertIn("sudo kmodgenca -a", cmds)
        self.assertIn("sudo mokutil --import /etc/pki/akmods/certs/public_key.der", cmds)
        self.assertIn("sudo dnf install akmod-nvidia xorg-x11-drv-nvidia-cuda", cmds)
        # Secure Boot is explained, never disabled.
        joined = " ".join(cmds).lower()
        for forbidden in ("--disable-validation", "sb-state --disable", "secureboot=0"):
            self.assertNotIn(forbidden, joined)
        # Repo must be enabled before the driver install.
        repo_idx = next(i for i, c in enumerate(cmds) if "rpmfusion" in c)
        drv_idx = next(i for i, c in enumerate(cmds) if "akmod-nvidia" in c)
        self.assertLess(repo_idx, drv_idx)

    def test_no_cuda_and_vaapi_flags(self):
        s = fixtures.nvidia_no_driver("GA106 [GeForce RTX 3060]")
        self.addCleanup(s.cleanup)
        plan = nvidia.install_plan(s.ctx(), with_cuda=False, with_vaapi=True)
        self.assertIn("sudo dnf install akmod-nvidia libva-nvidia-driver", self._all_argv(plan))

    def test_blocks_when_driver_already_works(self):
        s = fixtures.nvidia_desktop()
        self.addCleanup(s.cleanup)
        plan = nvidia.install_plan(s.ctx())
        self.assertFalse(plan["ok"])
        self.assertEqual(plan["steps"], [])
        self.assertTrue(any("already installed" in b for b in plan["blockers"]))

    def test_blocks_without_nvidia_gpu(self):
        s = fixtures.amd_desktop()
        self.addCleanup(s.cleanup)
        plan = nvidia.install_plan(s.ctx())
        self.assertFalse(plan["ok"])
        self.assertTrue(any("No NVIDIA GPU" in b for b in plan["blockers"]))

    def test_blocks_on_non_fedora(self):
        s = fixtures.nvidia_no_driver("GA106 [GeForce RTX 3060]")
        self.addCleanup(s.cleanup)
        s.file("/etc/os-release", fixtures.UBUNTU)
        plan = nvidia.install_plan(s.ctx())
        self.assertFalse(plan["ok"])

    def test_blocks_kepler(self):
        s = fixtures.nvidia_no_driver("GK104 [GeForce GTX 770]")
        self.addCleanup(s.cleanup)
        plan = nvidia.install_plan(s.ctx())
        self.assertFalse(plan["ok"])
        self.assertEqual(plan["steps"], [])

    def test_package_override_is_validated(self):
        s = fixtures.nvidia_no_driver("Device 2f04")
        self.addCleanup(s.cleanup)
        self.assertFalse(nvidia.install_plan(s.ctx(), package_override="akmod-nvidia; rm -rf /")["ok"])
        plan = nvidia.install_plan(s.ctx(), package_override="akmod-nvidia")
        self.assertTrue(plan["ok"], plan["blockers"])

    def test_stale_kernel_warning(self):
        s = fixtures.nvidia_no_driver("GA106 [GeForce RTX 3060]")
        self.addCleanup(s.cleanup)
        s.cmd("rpm -q kernel-core --qf %{VERSION}-%{RELEASE}.%{ARCH}\\n", "6.11.7-300.fc41.x86_64\n6.12.4-200.fc41.x86_64\n")
        plan = nvidia.install_plan(s.ctx())
        self.assertTrue(any("not the newest installed kernel" in w for w in plan["warnings"]))

    def test_secure_boot_off_has_no_key_steps(self):
        s = fixtures.nvidia_no_driver("GA106 [GeForce RTX 3060]")
        self.addCleanup(s.cleanup)
        s.secure_boot(False)
        cmds = self._all_argv(nvidia.install_plan(s.ctx()))
        self.assertFalse(any("mokutil" in c or "kmodgenca" in c for c in cmds))


class HyprlandHardwareConf(unittest.TestCase):
    def test_nvidia_desktop_sets_only_needed_env(self):
        s = fixtures.nvidia_desktop()
        self.addCleanup(s.cleanup)
        text, notes, links = hyprconf.generate_hardware_conf(s.ctx())
        lines = active_lines(text)
        self.assertIn("env = __GLX_VENDOR_LIBRARY_NAME,nvidia", lines)
        # libva-nvidia-driver isn't installed in this fixture -> no LIBVA env.
        self.assertFalse(any("LIBVA_DRIVER_NAME" in l for l in lines))
        for obsolete in ("WLR_NO_HARDWARE_CURSORS", "GBM_BACKEND", "explicit_sync"):
            self.assertFalse(any(obsolete in l for l in lines), obsolete)
        self.assertEqual(links, [])

    def test_nvidia_vaapi_env_when_driver_present(self):
        s = fixtures.nvidia_desktop()
        self.addCleanup(s.cleanup)
        s.file("/usr/lib64/dri/nvidia_drv_video.so", "")
        lines = active_lines(hyprconf.generate_hardware_conf(s.ctx())[0])
        self.assertIn("env = LIBVA_DRIVER_NAME,nvidia", lines)
        self.assertIn("env = NVD_BACKEND,direct", lines)

    def test_hybrid_never_forces_nvidia_globally(self):
        s = fixtures.hybrid_laptop()
        self.addCleanup(s.cleanup)
        text, notes, links = hyprconf.generate_hardware_conf(s.ctx())
        self.assertEqual(active_lines(text), [], "hybrid default must not set any env globally")
        self.assertTrue(any("aether gpu run" in n for n in notes))

    def test_hybrid_explicit_primary_writes_aq_drm_devices(self):
        s = fixtures.hybrid_laptop()
        self.addCleanup(s.cleanup)
        tmp = tempfile.mkdtemp()
        text, notes, links = hyprconf.generate_hardware_conf(s.ctx(), primary_slot="0000:00:02.0", link_dir=tmp)
        lines = active_lines(text)
        aq = [l for l in lines if l.startswith("env = AQ_DRM_DEVICES,")]
        self.assertEqual(len(aq), 1, lines)
        self.assertNotIn("0000:00:02.0", aq[0], "PCI paths contain ':' and must go through symlinks")
        self.assertEqual(links[0][0], "/dev/dri/by-path/pci-0000:00:02.0-card")

    def test_bad_primary_slot_raises(self):
        s = fixtures.hybrid_laptop()
        self.addCleanup(s.cleanup)
        with self.assertRaises(ValueError):
            hyprconf.generate_hardware_conf(s.ctx(), primary_slot="0000:09:00.0")

    def test_amd_and_intel_need_nothing(self):
        for builder in (fixtures.amd_desktop, fixtures.intel_laptop):
            s = builder()
            self.addCleanup(s.cleanup)
            self.assertEqual(active_lines(hyprconf.generate_hardware_conf(s.ctx())[0]), [])

    def test_offload_env(self):
        s = fixtures.hybrid_laptop()
        self.addCleanup(s.cleanup)
        nv = gpu.detect(s.ctx())[1]
        self.assertEqual(hyprconf.offload_env(nv)["__NV_PRIME_RENDER_OFFLOAD"], "1")
        s2 = fixtures.amd_desktop()
        self.addCleanup(s2.cleanup)
        self.assertEqual(hyprconf.offload_env(gpu.detect(s2.ctx())[0]), {"DRI_PRIME": "pci-0000_03_00_0"})

    def test_write_fragment_backs_up_and_is_idempotent(self):
        d = tempfile.mkdtemp()
        path = os.path.join(d, "hardware.conf")
        self.assertIsNone(hyprconf.write_fragment(path, "a\n"))
        self.assertIsNone(hyprconf.write_fragment(path, "a\n"), "unchanged content must not create a backup")
        backup = hyprconf.write_fragment(path, "b\n")
        self.assertTrue(backup and os.path.exists(backup))
        with open(backup) as fh:
            self.assertEqual(fh.read(), "a\n")


class CompatConf(unittest.TestCase):
    DEFAULT_GESTURES = {"workspaceSwipe": True, "swipeUp": "none", "swipeDown": "none"}

    def _for(self, tag, gestures=None):
        s = fixtures.nvidia_desktop()
        self.addCleanup(s.cleanup)
        if tag is None:
            s.bins.discard("hyprctl")
        else:
            s.cmd("hyprctl version -j", '{"tag": "%s"}' % tag)
        return active_lines(hyprconf.generate_compat_conf(s.ctx(), gestures or self.DEFAULT_GESTURES))

    def test_new_gesture_syntax_from_0_51(self):
        self.assertIn("gesture = 3, horizontal, workspace", self._for("v0.51.0"))
        self.assertIn("gesture = 3, horizontal, workspace", self._for("v0.53.1"))

    def test_old_gesture_syntax_before_0_51(self):
        lines = self._for("v0.46.2")
        self.assertIn("workspace_swipe = true", lines)
        self.assertNotIn("gesture = 3, horizontal, workspace", lines)

    def test_unknown_version_writes_nothing_risky(self):
        self.assertEqual(self._for(None), [])

    def test_rules_file_matches_the_rule_syntax_version(self):
        self.assertIn("source = ~/.config/hypr/rules.conf", self._for("v0.52.2"))
        self.assertIn("source = ~/.config/hypr/rules-v2.conf", self._for("v0.53.0"))
        self.assertNotIn("source = ~/.config/hypr/rules.conf", self._for("v0.53.0"))

    def test_vertical_swipes_dispatch_fixed_ipc_calls(self):
        lines = self._for("v0.51.0", {"workspaceSwipe": False, "swipeUp": "overview", "swipeDown": "notifications"})
        self.assertIn("gesture = 3, up, dispatcher, exec, qs -c aether-shell ipc call overview toggle", lines)
        self.assertIn("gesture = 3, down, dispatcher, exec, qs -c aether-shell ipc call notifications toggle", lines)
        self.assertNotIn("gesture = 3, horizontal, workspace", lines)

    def test_unknown_swipe_action_writes_nothing(self):
        lines = self._for("v0.51.0", {"workspaceSwipe": False, "swipeUp": "$(reboot)", "swipeDown": "none"})
        self.assertFalse([l for l in lines if l.startswith("gesture")])

    def test_old_hyprland_explains_missing_vertical_swipes(self):
        text = hyprconf.generate_compat_conf(self._ctx("v0.48.0"), {"workspaceSwipe": True, "swipeUp": "overview", "swipeDown": "none"})
        self.assertIn("need Hyprland 0.51", text)

    def _ctx(self, tag):
        s = fixtures.nvidia_desktop()
        self.addCleanup(s.cleanup)
        s.cmd("hyprctl version -j", '{"tag": "%s"}' % tag)
        return s.ctx()


class Verify(unittest.TestCase):
    def levels(self, checks, needle):
        return [c["level"] for c in checks if needle in c["text"]]

    def test_healthy_nvidia_desktop(self):
        s = fixtures.nvidia_desktop()
        self.addCleanup(s.cleanup)
        checks = report.verify(s.ctx())
        self.assertEqual([c for c in checks if c["level"] == "fail"], [])
        self.assertEqual(self.levels(checks, "modeset"), ["pass"])
        self.assertEqual(self.levels(checks, "Explicit sync"), ["pass"])

    def test_module_built_but_rejected_by_secure_boot(self):
        s = fixtures.nvidia_desktop()
        self.addCleanup(s.cleanup)
        import shutil
        shutil.rmtree(os.path.join(s.root, "sys", "module", "nvidia"))
        s.dir_("/sys/module/nouveau")
        s.cmd("mokutil --test-key /etc/pki/akmods/certs/public_key.der", "/etc/pki/akmods/certs/public_key.der is not enrolled\n", rc=1)
        checks = report.verify(s.ctx())
        fails = [c for c in checks if c["level"] == "fail"]
        self.assertTrue(any("Secure Boot" in c["text"] and "mokutil --import" in c["hint"] for c in fails), fails)
        self.assertTrue(any("NOT enrolled" in c["text"] for c in fails))

    def test_modeset_off_fails(self):
        s = fixtures.nvidia_desktop()
        self.addCleanup(s.cleanup)
        s.file("/sys/module/nvidia_drm/parameters/modeset", "N\n")
        self.assertEqual(self.levels(report.verify(s.ctx()), "modeset is disabled"), ["fail"])

    def test_llvmpipe_is_a_failure(self):
        s = fixtures.amd_desktop()
        self.addCleanup(s.cleanup)
        s.bins.add("eglinfo")
        s.cmd("eglinfo -B", "OpenGL renderer string: llvmpipe (LLVM 19.1.0, 256 bits)\n")
        self.assertEqual(self.levels(report.verify(s.ctx()), "software rendering"), ["fail"])

    def test_amd_missing_h264_on_fedora_warns(self):
        s = fixtures.amd_desktop()
        self.addCleanup(s.cleanup)
        checks = report.verify(s.ctx())
        self.assertEqual(self.levels(checks, "No H.264"), ["warn"])

    def test_suspended_dgpu_is_not_queried(self):
        s = fixtures.hybrid_laptop()
        self.addCleanup(s.cleanup)
        ctx = s.ctx()
        report.verify(ctx)
        self.assertFalse(any("renderD129" in c for c in ctx.calls), "vainfo must not wake the sleeping dGPU")

    def test_detect_does_not_probe_sleeping_dgpu(self):
        s = fixtures.hybrid_laptop()
        self.addCleanup(s.cleanup)
        s.bins.add("vainfo")
        ctx = s.ctx()
        data = report.detect(ctx)
        self.assertEqual(data["gpus"][1]["vaapi"]["status"], "skipped")
        self.assertFalse(any("renderD129" in c for c in ctx.calls), ctx.calls)

    def test_hybrid_conf_forcing_nvidia_warns(self):
        s = fixtures.hybrid_laptop()
        self.addCleanup(s.cleanup)
        d = tempfile.mkdtemp()
        conf = os.path.join(d, "hardware.conf")
        with open(conf, "w") as fh:
            fh.write("env = __GLX_VENDOR_LIBRARY_NAME,nvidia\n")
        self.assertEqual(self.levels(report.verify(s.ctx(), conf), "forces NVIDIA"), ["warn"])

    def test_no_gpu(self):
        s = fixtures.empty_system()
        self.addCleanup(s.cleanup)
        checks = report.verify(s.ctx())
        self.assertEqual([c["level"] for c in checks], ["fail"])

    def test_drivers_recommendations(self):
        s = fixtures.amd_desktop()
        self.addCleanup(s.cleanup)
        recs = report.drivers(s.ctx())
        self.assertIsNone(recs[0]["package"])
        self.assertTrue(any("freeworld" in c for c in recs[0]["codecs"]))


if __name__ == "__main__":
    unittest.main()
