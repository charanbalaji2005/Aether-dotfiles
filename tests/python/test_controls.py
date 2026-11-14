"""Control Centre registry and layout persistence (lib/aether/controls.py)."""

import os
import shutil
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "lib"))

from aether import controls as ctl  # noqa: E402


class Registry(unittest.TestCase):
    def test_every_control_is_complete(self):
        for cid, c in ctl.CONTROLS.items():
            with self.subTest(control=cid):
                self.assertEqual(cid, c.cid)
                self.assertIn(c.kind, ("toggle", "slider", "button", "media", "cluster"))
                self.assertIn(c.size, ("small", "wide", "tall", "big"))
                for m in c.members:
                    self.assertIn(m, ctl.CONTROLS)
                    self.assertNotEqual(ctl.CONTROLS[m].kind, "cluster")
                self.assertTrue(c.name and c.glyph and c.category)

    def test_default_layout_uses_known_controls(self):
        self.assertTrue(set(ctl.DEFAULT_LAYOUT) <= set(ctl.CONTROLS))

    def test_missing_program_is_reported_not_faked(self):
        with mock.patch.object(ctl.shutil, "which", return_value=None):
            rc, out = ctl.sh("definitely-not-a-program")
        self.assertEqual(rc, 127)
        self.assertIn("not installed", out)


class Layout(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp()
        self.env = mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": self.home})
        self.env.start()

    def tearDown(self):
        self.env.stop()
        shutil.rmtree(self.home)

    def test_default_when_nothing_saved(self):
        self.assertEqual(ctl.load_layout(), ctl.DEFAULT_LAYOUT)

    def test_add_remove_move_reset_persist(self):
        ctl.add("settings", 0)
        self.assertEqual(ctl.load_layout()[0], "settings")
        ctl.move("settings", 1)
        self.assertEqual(ctl.load_layout()[1], "settings")
        ctl.remove("music")
        self.assertNotIn("music", ctl.load_layout())
        ctl.add("settings")  # no duplicates
        self.assertEqual(ctl.load_layout().count("settings"), 1)
        self.assertEqual(ctl.reset(), ctl.DEFAULT_LAYOUT)
        self.assertEqual(ctl.load_layout(), ctl.DEFAULT_LAYOUT)

    def test_unknown_and_corrupt_layouts_are_safe(self):
        ctl.save_layout(["wifi", "nope", "wifi"])
        self.assertEqual(ctl.load_layout(), ["wifi"])
        ctl.layout_path().write_text("{not json", encoding="utf-8")
        self.assertEqual(ctl.load_layout(), ctl.DEFAULT_LAYOUT)


if __name__ == "__main__":
    unittest.main()
