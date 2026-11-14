"""Unit tests for the classic interface's colour engine (lib/aether/classic_colors.py)."""

import json
import os
import shutil
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "lib"))

from aether import classic_colors as cc  # noqa: E402


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def write(path, text=""):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)

ROLES = ("background", "foreground", "accent", "accent2", "on_accent", "surface", "surface2",
         "surface3", "border", "text", "subtext", "muted", "urgent", "ok", "warn", "info")

HISTOGRAM = """\
      9000: ( 12, 18, 30) #0C121E srgb(12,18,30)
      4000: ( 30, 60,110) #1E3C6E srgb(30,60,110)
      2500: (220,120, 40) #DC7828 srgb(220,120,40)
      1500: ( 60,170, 90) #3CAA5A srgb(60,170,90)
       900: (240,236,228) #F0ECE4 srgb(240,236,228)
       700: (200, 60, 80) #C83C50 srgb(200,60,80)
"""


class Maths(unittest.TestCase):
    def test_hex_roundtrip(self):
        self.assertEqual(cc.rgb_to_hex(cc.hex_to_rgb("#7F9cF5")), "#7f9cf5")

    def test_bad_hex_rejected(self):
        for bad in ("#12345", "red", "#zzzzzz", ""):
            with self.assertRaises(ValueError):
                cc.hex_to_rgb(bad)

    def test_contrast_extremes(self):
        self.assertAlmostEqual(cc.contrast("#000000", "#ffffff"), 21.0, places=1)
        self.assertAlmostEqual(cc.contrast("#777777", "#777777"), 1.0, places=3)

    def test_ensure_contrast_reaches_target(self):
        out = cc.ensure_contrast("#20242c", "#101218", 4.5)
        self.assertGreaterEqual(cc.contrast(out, "#101218"), 4.5)


class Palettes(unittest.TestCase):
    def check(self, p, mode):
        for k in ROLES + tuple("color%d" % i for i in range(16)):
            self.assertIn(k, p)
            cc.hex_to_rgb(p[k])
        self.assertEqual(p["mode"], mode)
        self.assertGreaterEqual(cc.contrast(p["text"], p["background"]), 7)
        self.assertGreaterEqual(cc.contrast(p["accent"], p["background"]), 3)
        self.assertGreaterEqual(cc.contrast(p["on_accent"], p["accent"]), 3)
        gap = abs(cc.hls(p["accent"])[0] - cc.hls(p["accent2"])[0])
        self.assertGreater(min(gap, 1 - gap), 0.05, "the two accents should differ in hue")

    def test_every_preset_is_readable(self):
        for name, pr in cc.PRESETS.items():
            with self.subTest(preset=name):
                self.check(cc.preset_palette(name), pr["mode"])

    def test_histogram_dark_and_light(self):
        for mode in cc.MODES:
            with self.subTest(mode=mode):
                p = cc.palette_from_histogram(HISTOGRAM, mode)
                self.check(p, mode)
                light_bg = cc.luminance(p["background"]) > 0.5
                self.assertEqual(light_bg, mode == "light")

    def test_histogram_too_small(self):
        with self.assertRaises(ValueError):
            cc.palette_from_histogram("1: (0,0,0) #000000\n", "dark")

    def test_wallust_json_validated(self):
        data = {k: "#202020" for k in ["background", "foreground", "cursor"] + ["color%d" % i for i in range(16)]}
        data["background"] = "#0a0a0a"
        p = cc.palette_from_wallust_json(data, "dark")
        self.assertGreaterEqual(cc.contrast(p["foreground"], p["background"]), 7)
        data["color3"] = "{{color3}}"  # an unrendered template must not pass
        with self.assertRaises(ValueError):
            cc.palette_from_wallust_json(data, "dark")


class Templates(unittest.TestCase):
    def test_formats(self):
        v = {"a": "#102030", "mode": "dark"}
        self.assertEqual(cc.render("{{a}} {{ a.hex }} {{a.rgb}}", v), "#102030 102030 16, 32, 48")
        self.assertEqual(cc.render("{{a.rgba(0.5)}}", v), "rgba(16, 32, 48, 0.5)")
        self.assertEqual(cc.render("{{a.hypr(ee)}}", v), "rgba(102030ee)")

    def test_unknown_variable_is_an_error(self):
        with self.assertRaises(KeyError):
            cc.render("{{nope}}", {})

    def test_every_template_renders_with_a_real_palette(self):
        values = cc.template_values(cc.preset_palette("graphite"), {"wallpaper": "/w.png", "glass": "deep"})
        self.assertEqual(values["glass_background"], "rgba(16, 18, 24, 0.60)")
        self.assertEqual(values["glass_kitty"], "0.58")
        tdir = cc.template_dir()
        names = sorted(os.listdir(tdir))
        self.assertGreaterEqual(len(names), 7)
        for name in names:
            with self.subTest(template=name):
                out = cc.render(read(os.path.join(tdir, name)), values)
                self.assertNotIn("{{", out)


class Apply(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp()
        self.env = mock.patch.dict(os.environ, {"HOME": self.home, "XDG_CONFIG_HOME": os.path.join(self.home, ".config")})
        self.env.start()
        os.makedirs(os.path.join(self.home, ".config", "waybar", "styles"))
        write(os.path.join(self.home, ".config", "waybar", "styles", "pills.css"))

    def tearDown(self):
        self.env.stop()
        shutil.rmtree(self.home)

    def test_init_writes_everything_without_a_wallpaper(self):
        self.assertEqual(cc.main(["init"]), 0)
        self.assertFalse(cc.outputs_missing())
        for _, dest in cc.targets():
            self.assertTrue(dest.exists(), dest)
        pal = json.loads((cc.classic_dir() / "colors" / "palette.json").read_text())
        self.assertEqual(pal["mode"], "dark")
        # init is a no-op once everything exists
        mtime = (cc.classic_dir() / "colors" / "rofi.rasi").stat().st_mtime_ns
        self.assertEqual(cc.main(["init"]), 0)
        self.assertEqual((cc.classic_dir() / "colors" / "rofi.rasi").stat().st_mtime_ns, mtime)

    def test_mode_toggle_and_presets(self):
        cc.main(["source", "preset", "paper", "--no-reload"])
        self.assertEqual(cc.read_state()["mode"], "light")
        cc.main(["mode", "toggle", "--no-reload"])
        st = cc.read_state()
        self.assertEqual(st["mode"], "dark")
        self.assertEqual(st["preset"], cc.DEFAULT_PRESET["dark"])

    def test_bad_input_is_rejected(self):
        self.assertEqual(cc.main(["source", "rainbow"]), 2)
        self.assertEqual(cc.main(["source", "preset", "nope"]), 2)
        self.assertEqual(cc.main(["waybar-style", "../../etc"]), 2)
        self.assertEqual(cc.main(["mode", "purple"]), 2)

    def test_missing_style_falls_back_to_pills(self):
        st = cc.read_state()
        st["waybar_style"] = "doesnotexist"
        cc.write_outputs(cc.preset_palette("graphite"), st)
        wrapper = (cc.classic_dir() / "waybar" / "style.css").read_text()
        self.assertIn("styles/pills.css", wrapper)

    def test_hyprland_fragment_only_for_classic(self):
        iface = os.path.join(self.home, ".config", "aether-shell", "interface")
        os.makedirs(os.path.dirname(iface), exist_ok=True)
        write(iface, "aether\n")
        frag = os.path.join(self.home, ".config", "aether-shell", "hypr", "interface-theme.conf")
        cc.main(["apply", "--no-reload"])
        self.assertFalse(os.path.exists(frag))
        write(iface, "classic\n")
        cc.main(["apply", "--no-reload"])
        self.assertIn("col.active_border", read(frag))

    def test_unreadable_wallpaper_falls_back_to_preset(self):
        bogus = os.path.join(self.home, "not-an-image.png")
        write(bogus, "x")
        with mock.patch.object(cc.shutil, "which", return_value=None):
            pal, used, notes = cc.resolve_palette({"mode": "dark", "source": "wallust", "wallpaper": bogus})
        self.assertTrue(used.startswith("preset:"))
        self.assertEqual(len(notes), 2)


if __name__ == "__main__":
    unittest.main()
