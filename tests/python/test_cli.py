"""End-to-end CLI tests: theme/performance helpers plus the real `aether`
argument parsing and dispatch, run against fixtures AND against whatever
machine the tests run on (to prove graceful behaviour with no GPU/sysfs)."""

import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest

import fixtures
from aether import cli, performance, theme, util

LIB = os.path.join(fixtures.REPO, "lib")
LAUNCH = "import sys; sys.path.insert(0, sys.argv.pop(1)); from aether.cli import main; sys.exit(main(sys.argv[1:]))"


def run_cli(*args, env=None):
    full_env = dict(os.environ)
    full_env.update(env or {})
    full_env["HOME"] = full_env.get("AETHER_TEST_HOME", tempfile.mkdtemp())
    full_env["XDG_STATE_HOME"] = os.path.join(full_env["HOME"], "state")
    full_env["XDG_CONFIG_HOME"] = os.path.join(full_env["HOME"], "config")
    return subprocess.run([sys.executable, "-I", "-c", LAUNCH, LIB] + list(args),
                          stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=full_env, timeout=60)


class Theme(unittest.TestCase):
    HIST = (
        "    9000: (  20, 22, 30) #14161E srgb(20,22,30)\n"      # dark grey background
        "    3000: (200,200,200) #C8C8C8 srgb(200,200,200)\n"    # light grey
        "     900: (230, 60, 90) #E63C5A srgb(230,60,90)\n"      # vivid red-pink
        "     300: ( 40,200,120) #28C878 srgb(40,200,120)\n"     # vivid green, smaller
    )

    def test_histogram_parsing(self):
        hist = theme.parse_histogram(self.HIST)
        self.assertEqual(len(hist), 4)
        self.assertEqual(hist[2], (900, (230, 60, 90)))

    def test_16bit_histogram_is_scaled(self):
        self.assertEqual(theme.parse_histogram("  5: (65535,0,32896) #FFFF00008080")[0][1], (255, 0, 128))

    def test_picks_vivid_dominant_colour_not_grey(self):
        import colorsys
        colour = theme.pick_accent(theme.parse_histogram(self.HIST), "dark")
        r, g, b = (int(colour[i:i + 2], 16) / 255 for i in (1, 3, 5))
        h, l, s = colorsys.rgb_to_hls(r, g, b)
        self.assertTrue(h > 0.9 or h < 0.05, "expected the red/pink hue, got %s" % colour)
        self.assertGreaterEqual(l, 0.6, "dark mode accent must be light enough for contrast")

    def test_light_mode_is_darker(self):
        dark = theme.pick_accent(theme.parse_histogram(self.HIST), "dark")
        light = theme.pick_accent(theme.parse_histogram(self.HIST), "light")
        self.assertLess(int(light[1:3], 16) + int(light[3:5], 16), int(dark[1:3], 16) + int(dark[3:5], 16))

    def test_monochrome_image_still_returns_a_colour(self):
        self.assertRegex(theme.pick_accent([(100, (30, 30, 34))]), r"^#[0-9A-F]{6}$")

    def test_missing_imagemagick_is_an_error_not_a_guess(self):
        s = fixtures.empty_system()
        self.addCleanup(s.cleanup)
        img = os.path.join(s.root, "w.png")
        open(img, "wb").close()
        colour, err = theme.extract_accent(s.ctx(), img)
        self.assertIsNone(colour)
        self.assertIn("ImageMagick", err)

    def test_update_shell_config_preserves_other_keys_and_refuses_corrupt_file(self):
        home = tempfile.mkdtemp()
        old = os.environ.get("XDG_CONFIG_HOME")
        os.environ["XDG_CONFIG_HOME"] = home
        try:
            path = theme.config_file()
            os.makedirs(os.path.dirname(path))
            with open(path, "w") as fh:
                json.dump({"bar": {"height": 40}, "appearance": {"accent": "#000000"}}, fh)
            ok, _ = theme.update_shell_config("appearance", "accent", "#7C9CFF")
            self.assertTrue(ok)
            with open(path) as fh:
                data = json.load(fh)
            self.assertEqual(data, {"bar": {"height": 40}, "appearance": {"accent": "#7C9CFF"}})
            with open(path, "w") as fh:
                fh.write("{ not json")
            ok, msg = theme.update_shell_config("appearance", "accent", "#FFFFFF")
            self.assertFalse(ok)
            with open(path) as fh:
                self.assertEqual(fh.read(), "{ not json", "corrupt file must not be overwritten")
        finally:
            if old is None:
                os.environ.pop("XDG_CONFIG_HOME", None)
            else:
                os.environ["XDG_CONFIG_HOME"] = old


class Performance(unittest.TestCase):
    def test_power_profiles(self):
        s = fixtures.amd_desktop()
        self.addCleanup(s.cleanup)
        s.bins.add("powerprofilesctl")
        s.cmd("powerprofilesctl get", "balanced\n")
        s.cmd("powerprofilesctl list", "  performance:\n    CpuDriver:\tamd_pstate\n\n* balanced:\n    CpuDriver:\tamd_pstate\n\n  power-saver:\n    CpuDriver:\tamd_pstate\n")
        s.cmd("powerprofilesctl set performance", "")
        st = performance.power_profile_state(s.ctx())
        self.assertEqual((st["active"], sorted(st["profiles"])), ("balanced", ["balanced", "performance", "power-saver"]))
        self.assertTrue(performance.set_power_profile(s.ctx(), "performance")["ok"])
        self.assertFalse(performance.set_power_profile(s.ctx(), "turbo")["ok"])

    def test_profile_missing_on_machine(self):
        s = fixtures.amd_desktop()
        self.addCleanup(s.cleanup)
        s.bins.add("powerprofilesctl")
        s.cmd("powerprofilesctl get", "balanced\n")
        s.cmd("powerprofilesctl list", "* balanced:\n\n  power-saver:\n")
        res = performance.set_power_profile(s.ctx(), "performance")
        self.assertFalse(res["ok"])
        self.assertIn("does not offer", res["error"])

    def test_no_powerprofilesctl(self):
        s = fixtures.empty_system()
        self.addCleanup(s.cleanup)
        self.assertFalse(performance.power_profile_state(s.ctx())["available"])

    def test_hyprland_profiles_render_and_roundtrip(self):
        d = tempfile.mkdtemp()
        for name in performance.HYPR_PROFILES:
            text = performance.render_hypr_profile(name)
            self.assertEqual(text.count("{"), text.count("}"), name)
            path = os.path.join(d, name + ".conf")
            with open(path, "w") as fh:
                fh.write(text)
            self.assertEqual(performance.current_hypr_profile(path), name)
        self.assertIn("enabled = false", performance.render_hypr_profile("battery"))


class CommandLine(unittest.TestCase):
    def fixture_env(self, scenario):
        cmds = os.path.join(scenario.root, "commands.json")
        with open(cmds, "w") as fh:
            json.dump({"commands": scenario.commands, "bins": sorted(scenario.bins)}, fh)
        return {"AETHER_SYSROOT": scenario.root, "AETHER_COMMAND_FIXTURES": cmds}

    def test_help_and_version(self):
        r = run_cli("--help")
        self.assertEqual(r.returncode, 0)
        for cmd in ("system", "hardware", "graphics", "gpu", "cpu", "performance", "diagnostics", "repair"):
            self.assertIn(cmd, r.stdout)
        self.assertIn("aether 0.", run_cli("--version").stdout)

    def test_hardware_json_against_fixture(self):
        s = fixtures.hybrid_laptop()
        self.addCleanup(s.cleanup)
        r = run_cli("hardware", "--json", env=self.fixture_env(s))
        self.assertEqual(r.returncode, 0, r.stderr)
        data = json.loads(r.stdout)
        self.assertEqual(data["gpuTopology"]["layout"], "hybrid")
        self.assertEqual(data["cpu"]["vendor"], "Intel")

    def test_graphics_drivers_and_install_plan_json(self):
        s = fixtures.nvidia_no_driver("GA106 [GeForce RTX 3060]")
        self.addCleanup(s.cleanup)
        env = self.fixture_env(s)
        recs = json.loads(run_cli("graphics", "drivers", "--json", env=env).stdout)
        self.assertEqual(recs[0]["package"], "akmod-nvidia")
        r = run_cli("graphics", "install-nvidia", "--dry-run", env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("nothing was executed", r.stdout)
        self.assertIn("mokutil --import", r.stdout)

    def test_install_nvidia_without_tty_does_not_execute(self):
        s = fixtures.nvidia_no_driver("GA106 [GeForce RTX 3060]")
        self.addCleanup(s.cleanup)
        r = run_cli("graphics", "install-nvidia", env=self.fixture_env(s))
        self.assertEqual(r.returncode, 1)
        # Linux: "stdin is not a terminal" path. Windows reports NUL as a TTY,
        # so input() hits EOF instead. Either way: abort, execute nothing.
        self.assertIn("Aborted", r.stdout)
        self.assertNotIn(">>> ", r.stdout, "no step may run without confirmation")

    def test_graphics_configure_dry_run_and_write(self):
        s = fixtures.nvidia_desktop()
        self.addCleanup(s.cleanup)
        home = tempfile.mkdtemp()
        env = dict(self.fixture_env(s), AETHER_TEST_HOME=home)
        r = run_cli("graphics", "configure", "--dry-run", env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("__GLX_VENDOR_LIBRARY_NAME", r.stdout)
        conf = os.path.join(home, "config", "aether-shell", "hypr", "hardware.conf")
        self.assertFalse(os.path.exists(conf))
        r = run_cli("graphics", "configure", "--yes", env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(os.path.exists(conf))
        r = run_cli("graphics", "configure", "--yes", env=env)
        self.assertIn("Already up to date", r.stdout)

    def test_performance_hyprland_writes_profile(self):
        home = tempfile.mkdtemp()
        r = run_cli("performance", "hyprland", "battery", env={"AETHER_TEST_HOME": home})
        self.assertEqual(r.returncode, 0, r.stderr)
        path = os.path.join(home, "config", "aether-shell", "hypr", "profile.conf")
        self.assertEqual(performance.current_hypr_profile(path), "battery")
        self.assertNotEqual(run_cli("performance", "hyprland", "turbo").returncode, 0)

    def test_repair_recreates_fragments(self):
        home = tempfile.mkdtemp()
        r = run_cli("repair", "--dry-run", env={"AETHER_TEST_HOME": home})
        self.assertIn("Recreate missing Hyprland fragment", r.stdout)
        r = run_cli("repair", env={"AETHER_TEST_HOME": home})
        self.assertTrue(os.path.exists(os.path.join(home, "config", "aether-shell", "hypr", "hardware.conf")))
        self.assertTrue(os.path.exists(os.path.join(home, "config", "aether-shell", "hypr", "profile.conf")))

    def test_telemetry_stream_emits_json_lines(self):
        s = fixtures.amd_desktop()
        self.addCleanup(s.cleanup)
        r = run_cli("telemetry", "--stream", "--interval", "0.5", "--count", "2", env=self.fixture_env(s))
        self.assertEqual(r.returncode, 0, r.stderr)
        lines = [json.loads(l) for l in r.stdout.splitlines()]
        self.assertEqual(len(lines), 2)
        self.assertEqual(lines[0]["gpus"][0]["vendor"], "amd")

    def test_real_host_degrades_gracefully(self):
        """Runs against the actual machine executing the tests (CI runner or a
        developer's PC). Whatever it is, these commands must not crash."""
        for args in (("system", "--json"), ("hardware", "--json"), ("graphics", "verify", "--json"),
                     ("gpu", "--json"), ("cpu", "--json"), ("performance", "--json"), ("telemetry",)):
            r = run_cli(*args)
            self.assertNotIn("Traceback", r.stderr, "%s crashed:\n%s" % (" ".join(args), r.stderr))
            json.loads(r.stdout)


if __name__ == "__main__":
    unittest.main()
