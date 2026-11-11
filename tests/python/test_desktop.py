"""Desktop-layer backend: config schema & migrations, automation rules,
palettes, snapshots, profiles, layouts, capabilities, system status,
terminal generation, appearance themes — plus the contracts shared with
the QML shell (schema, action ids, rule tables, palette table)."""

import io
import json
import os
import re
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest import mock

import fixtures
from aether import (appearance, automation, capabilities, config, layouts, palettes, profiles,
                    snapshots, sysinfo)
from aether.graphics import hyprconf
from aether.util import Context

SHELL = os.path.join(fixtures.REPO, "config", "quickshell", "aether-shell")


def slurp(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def spit(path, text):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


class IsolatedHome(unittest.TestCase):
    """Every test gets its own XDG config/state/cache directories."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="aether-home-")
        self.home = self._tmp.name
        env = {"HOME": self.home, "XDG_CONFIG_HOME": os.path.join(self.home, "config"),
               "XDG_STATE_HOME": os.path.join(self.home, "state"), "XDG_CACHE_HOME": os.path.join(self.home, "cache")}
        self._env = mock.patch.dict(os.environ, env)
        self._env.start()
        self.addCleanup(self._env.stop)
        self.addCleanup(self._tmp.cleanup)

    def write_config(self, data):
        os.makedirs(os.path.dirname(config.config_file()), exist_ok=True)
        with open(config.config_file(), "w", encoding="utf-8") as fh:
            json.dump(data, fh)


# -- shared contracts -----------------------------------------------------------

class Contracts(unittest.TestCase):
    def test_schema_data_is_generated_from_config_qml(self):
        r = subprocess.run([sys.executable, os.path.join(fixtures.REPO, "tools", "gen_schema.py"), "--check"],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_action_ids_match_the_shell(self):
        with open(os.path.join(SHELL, "services", "ActionService.qml"), encoding="utf-8") as fh:
            qml_ids = re.findall(r'\{ id: "([a-z-]+)"', fh.read())
        self.assertEqual(sorted(qml_ids), sorted(config.ACTIONS))

    def test_automation_tables_match_the_shell(self):
        with open(os.path.join(SHELL, "automation", "Rules.js"), encoding="utf-8") as fh:
            js = fh.read()

        def table(name):
            body = re.search(r"var %s = (\{.*?\n\});" % name, js, re.S).group(1)
            return json.loads(re.sub(r",(\s*\})", r"\1", body))

        self.assertEqual(table("TRIGGERS"), automation.TRIGGERS)
        self.assertEqual(table("CONDITIONS"), automation.CONDITIONS)
        self.assertEqual(table("ACTIONS"), automation.ACTIONS)

    def test_every_palette_defines_every_token(self):
        table = palettes.load()
        self.assertGreaterEqual(len(table), 12)
        for pid, p in table.items():
            for tok in palettes.TOKENS:
                self.assertRegex(p[tok], r"^#[0-9A-F]{6}$", "%s.%s" % (pid, tok))
            self.assertEqual(len(p["ansi"]), 16, pid)
            self.assertIsInstance(p["dark"], bool)


# -- config -------------------------------------------------------------------

class ConfigSchema(IsolatedHome):
    def test_defaults_validate_cleanly(self):
        clean, problems = config.validate(config.defaults())
        self.assertEqual(problems, [])
        self.assertEqual(clean, config.defaults())

    def test_bad_values_are_repaired_and_reported(self):
        clean, problems = config.validate({
            "bar": {"height": 500, "position": "diagonal", "nope": 1},
            "appearance": {"accent": "red", "palette": "made-up", "barOpacity": "0.5"},
            "general": {"reducedMotion": "yes"},
            "mystery": {},
        })
        self.assertEqual(clean["bar"]["height"], 64)            # clamped
        self.assertEqual(clean["bar"]["position"], "top")       # default
        self.assertNotIn("nope", clean["bar"])
        self.assertEqual(clean["appearance"]["accent"], "#7C9CFF")
        self.assertEqual(clean["appearance"]["palette"], "aether")
        self.assertIs(clean["general"]["reducedMotion"], False)
        self.assertNotIn("mystery", clean)
        self.assertEqual(len(problems), 8)

    def test_numbers_reject_nan_bool_and_fractional_ints(self):
        _c, p = config.validate({"bar": {"height": float("nan")}})
        self.assertTrue(p)
        _c, p = config.validate({"bar": {"height": True}})
        self.assertTrue(p)
        _c, p = config.validate({"bar": {"height": 38.5}})
        self.assertTrue(p)

    def test_gesture_actions_are_allowlisted(self):
        _c, p = config.validate({"gestures": {"edgeLeft": "rm -rf ~"}})
        self.assertTrue(p)
        c, p = config.validate({"gestures": {"edgeLeft": "overview"}})
        self.assertEqual(p, [])

    def test_set_keys_is_all_or_nothing(self):
        self.write_config({"bar": {"height": 40}})
        ok, problems = config.set_keys({"bar": {"height": 50}, "appearance": {"accent": "nope"}})
        self.assertFalse(ok)
        self.assertEqual(config.load()[0]["bar"]["height"], 40)
        ok, _ = config.set_keys({"bar": {"height": 50}})
        self.assertTrue(ok)
        self.assertEqual(config.load()[0]["bar"]["height"], 50)

    def test_config_file_is_private(self):
        config.save({"bar": {"height": 40}})
        self.assertEqual(os.stat(config.config_file()).st_mode & 0o777, 0o600)

    def test_migration_from_unversioned_file(self):
        new, notes = config.migrate({"appearance": {"panelOpacity": 0.55}, "general": {"reducedMotion": True}})
        self.assertEqual(new["meta"]["schemaVersion"], config.SCHEMA_VERSION)
        self.assertEqual(new["appearance"]["glassStyle"], "heavy")
        self.assertIs(new["effects"]["particles"], False)
        self.assertIs(new["wallpaper"]["parallax"], False)
        self.assertEqual(new["general"]["motionProfile"], "none")
        self.assertEqual(len(notes), 3)

    def test_migration_keeps_explicit_choices(self):
        new, _ = config.migrate({"appearance": {"panelOpacity": 0.55, "glassStyle": "ultra"}})
        self.assertEqual(new["appearance"]["glassStyle"], "ultra")

    def test_newer_file_is_refused(self):
        with self.assertRaises(ValueError):
            config.migrate({"meta": {"schemaVersion": config.SCHEMA_VERSION + 1}})

    def test_terminal_paths_and_fonts_are_validated(self):
        _c, p = config.validate({"terminal": {"customProfile": "relative/path"}})
        self.assertTrue(p)
        _c, p = config.validate({"terminal": {"fontFamily": "Mono; rm -rf"}})
        self.assertTrue(p)


# -- automation ---------------------------------------------------------------

class Automation(unittest.TestCase):
    RULE = {"id": "r1", "name": "Dim on battery", "trigger": {"type": "power-disconnected"},
            "action": {"type": "set-quality", "value": "eco"}}

    def test_valid_rule(self):
        clean, err = automation.validate_rule(self.RULE)
        self.assertEqual(err, "")
        self.assertTrue(clean["enabled"])

    def test_there_is_no_command_action(self):
        for kind in ("run", "exec", "shell", "command", "run-command"):
            _c, err = automation.validate_rule(dict(self.RULE, action={"type": kind, "value": "id"}))
            self.assertIn("unknown action", err)

    def test_launch_app_takes_an_id_not_a_command_line(self):
        _c, err = automation.validate_rule(dict(self.RULE, action={"type": "launch-app", "app": "firefox --new-window"}))
        self.assertTrue(err)
        _c, err = automation.validate_rule(dict(self.RULE, action={"type": "launch-app", "app": "org.mozilla.firefox"}))
        self.assertEqual(err, "")

    def test_extra_fields_and_traversal_are_rejected(self):
        _c, err = automation.validate_rule(dict(self.RULE, action={"type": "set-quality", "value": "eco", "cmd": "x"}))
        self.assertIn("unexpected", err)
        _c, err = automation.validate_rule(dict(self.RULE, action={"type": "set-wallpaper", "value": "/srv/u/../../etc/shadow"}))
        self.assertTrue(err)

    def test_conflicts_and_loops(self):
        a = dict(self.RULE)
        b = dict(self.RULE, id="r2", action={"type": "set-quality", "value": "ultra"})
        loop1 = {"id": "l1", "trigger": {"type": "workspace-active", "value": 1}, "action": {"type": "switch-workspace", "value": 2}}
        loop2 = {"id": "l2", "trigger": {"type": "workspace-active", "value": 2}, "action": {"type": "switch-workspace", "value": 1}}
        good, problems = automation.validate_rules([a, b, loop1, loop2])
        self.assertEqual(problems, [])
        found = automation.find_conflicts(good)
        self.assertTrue(any("r1 and r2" in f for f in found))
        self.assertTrue(any("loop" in f for f in found))

    def test_duplicates_and_limits(self):
        good, problems = automation.validate_rules([self.RULE, self.RULE])
        self.assertEqual(len(good), 1)
        self.assertTrue(problems)
        good, problems = automation.validate_rules([dict(self.RULE, id="x%d" % i) for i in range(80)])
        self.assertEqual(len(good), automation.MAX_RULES)


# -- palettes / terminals -----------------------------------------------------

class Terminal(IsolatedHome):
    def test_apply_writes_only_aether_files(self):
        ctx = Context(sysroot="/", command_fixtures={}, fixture_bins=[])
        res = palettes.apply(ctx, "nord", "#ff0000", True)
        base = os.path.join(self.home, "config", "aether-shell")
        for rel in ("terminal/kitty-theme.conf", "terminal/foot-theme.ini", "terminal/alacritty-theme.toml",
                    "terminal/ghostty-theme", "terminal/kitty-local.conf", "terminal/zsh-profile.zsh", "hypr/theme.conf"):
            self.assertTrue(os.path.isfile(os.path.join(base, rel)), rel)
        for path in res["written"]:
            self.assertTrue(path.startswith(base), path)
        kitty = slurp(os.path.join(base, "terminal/kitty-theme.conf"))
        self.assertIn("background            #2E3440".replace("#2E3440", palettes.resolve("nord")["bg0"]), kitty)
        self.assertNotIn("#ff0000", kitty, "named palettes keep their own accent")

    def test_custom_accent_applies_to_builtin_palette(self):
        ctx = Context(sysroot="/", command_fixtures={}, fixture_bins=[])
        res = palettes.apply(ctx, "aether", "#FF0000", True)
        self.assertEqual(res["accent"], "#FF0000")

    def test_second_apply_is_a_no_op(self):
        ctx = Context(sysroot="/", command_fixtures={}, fixture_bins=[])
        palettes.apply(ctx, "dracula", None, True)
        self.assertEqual(palettes.apply(ctx, "dracula", None, True)["written"], [])

    def test_custom_zsh_profile_path_is_quoted(self):
        t = dict(config.defaults()["terminal"], zshProfile="custom", customProfile="/tmp/a'b; touch /tmp/x; $(id)")
        text = palettes.render_zsh_profile(t, "/repo/config/zsh")
        line = text.splitlines()[-1]
        self.assertEqual(line.count("'/tmp/a'\\''b; touch /tmp/x; $(id)'"), 2)

    def test_hypr_border_colours(self):
        text = palettes.render_hypr(palettes.resolve("gruvbox"), "#FABD2F")
        self.assertIn("col.active_border = rgba(fabd2fee) rgba(fe8019ee) 45deg", text)


# -- snapshots ----------------------------------------------------------------

class Snapshots(IsolatedHome):
    def setUp(self):
        super().setUp()
        self.write_config({"bar": {"height": 40}, "meta": {"schemaVersion": config.SCHEMA_VERSION}})
        frag = os.path.join(self.home, "config", "aether-shell", "hypr")
        os.makedirs(frag)
        with open(os.path.join(frag, "profile.conf"), "w") as fh:
            fh.write("# profile\n")

    def test_create_verify_restore_roundtrip(self):
        path = snapshots.create("test")
        self.assertTrue(snapshots.verify(path)[0])
        config.set_keys({"bar": {"height": 60}})
        prev = snapshots.preview(path)
        self.assertEqual([c["path"] for c in prev["changes"]], ["config.json"])
        res = snapshots.restore(path)
        self.assertTrue(res["ok"])
        self.assertEqual(config.load()[0]["bar"]["height"], 40)
        self.assertTrue(res["undo"] and os.path.isfile(res["undo"]), "restore snapshots the current state first")

    def test_tampered_archive_is_rejected(self):
        path = snapshots.create("test")
        with tarfile.open(path, "r:gz") as tar:
            members = [(m, tar.extractfile(m).read()) for m in tar]
        with tarfile.open(path, "w:gz") as tar:
            for m, data in members:
                if m.name == "config.json":
                    data = b'{"bar": {"height": 28}}'
                    m.size = len(data)
                tar.addfile(m, io.BytesIO(data))
        ok, problems = snapshots.verify(path)
        self.assertFalse(ok)
        self.assertTrue(any("checksum" in p for p in problems))
        self.assertFalse(snapshots.restore(path)["ok"])

    def _evil(self, name, data=b"x", kind=tarfile.REGTYPE):
        path = os.path.join(self.home, "evil.tar.gz")
        manifest = json.dumps({"format": 1, "files": {}, "schemaVersion": 1}).encode()
        with tarfile.open(path, "w:gz") as tar:
            for n, d, k in (("MANIFEST.json", manifest, tarfile.REGTYPE), (name, data, kind)):
                info = tarfile.TarInfo(n)
                info.type = k
                info.size = len(d) if k == tarfile.REGTYPE else 0
                if k == tarfile.SYMTYPE:
                    info.linkname = "/etc/passwd"
                tar.addfile(info, io.BytesIO(d) if k == tarfile.REGTYPE else None)
        return path

    def test_traversal_unknown_paths_and_links_are_refused(self):
        for name, kind in (("../../.ssh/authorized_keys", tarfile.REGTYPE), (".bashrc", tarfile.REGTYPE),
                           ("hypr/profile.conf", tarfile.SYMTYPE)):
            ok, problems = snapshots.verify(self._evil(name, kind=kind))
            self.assertFalse(ok, name)
        self.assertFalse(os.path.exists(os.path.join(self.home, ".ssh")))

    def test_last_known_good_and_retention(self):
        snapshots.create(snapshots.LKG)
        for i in range(snapshots.KEEP + 3):
            snapshots.create("n%d" % i)
        names = [s["name"] for s in snapshots.listing()]
        self.assertIn(snapshots.LKG, names)
        self.assertEqual(len(names), snapshots.KEEP + 1)
        self.assertEqual(snapshots.resolve(snapshots.LKG).endswith(snapshots.LKG + ".tar.gz"), True)

    def test_only_selected_components(self):
        path = snapshots.create("shell-only", ["shell"])
        with tarfile.open(path) as tar:
            self.assertEqual(sorted(m.name for m in tar), ["MANIFEST.json", "config.json"])


# -- profiles -----------------------------------------------------------------

class Profiles(IsolatedHome):
    def test_every_builtin_profile_is_valid(self):
        for name in profiles.BUILTIN:
            prof, err = profiles.get(name)
            self.assertIsNotNone(prof, "%s: %s" % (name, err))

    def test_apply_changes_only_listed_keys_and_snapshots_first(self):
        self.write_config({"notifications": {"timeoutLow": 9000}, "bar": {"height": 40}})
        res = profiles.apply("minimal")
        self.assertTrue(res["ok"])
        data = config.load()[0]
        self.assertEqual(data["notifications"]["timeoutLow"], 9000)
        self.assertEqual(data["bar"]["style"], "full")
        self.assertTrue(os.path.isfile(res["undo"]))

    def test_import_rejects_rules_unknown_fields_and_bad_values(self):
        src = os.path.join(self.home, "p.json")
        for doc in ({"label": "x", "config": {}, "script": "curl | sh"},
                    {"label": "x", "config": {"bar": {"height": "tall"}}},
                    {"label": "x", "hyprland": "turbo", "config": {}}):
            with open(src, "w") as fh:
                json.dump(doc, fh)
            self.assertFalse(profiles.import_file(src, "shared")["ok"], doc)
        with open(src, "w") as fh:
            json.dump({"label": "x", "config": {"automation": {"enabled": True, "rules": [{"id": "a"}]}}}, fh)
        res = profiles.import_file(src, "shared")
        self.assertFalse(res["ok"], "invalid rules make the profile invalid")

    def test_save_current_drops_machine_paths(self):
        self.write_config({"appearance": {"wallpaper": "/media/me/secret.jpg", "palette": "nord"}, "wallpaper": {"video": "/x.mp4"}})
        res = profiles.save_current("mine")
        self.assertTrue(res["ok"])
        saved = json.loads(slurp(res["path"]))
        self.assertNotIn("wallpaper", saved["config"].get("appearance", {}))
        self.assertNotIn("video", saved["config"].get("wallpaper", {}))
        self.assertEqual(saved["config"]["appearance"]["palette"], "nord")


# -- layouts ------------------------------------------------------------------

MONITOR = [{"id": 0, "name": "DP-1", "x": 0, "y": 0, "width": 2560, "height": 1440, "scale": 1.0, "transform": 0,
            "reserved": [0, 46, 0, 0], "focused": True, "activeWorkspace": {"id": 3}}]
CLIENTS = [
    {"address": "0x1", "class": "kitty", "title": "zsh", "workspace": {"id": 3}, "floating": False, "at": [0, 46], "size": [800, 600], "mapped": True},
    {"address": "0x2", "class": "firefox", "title": "Web", "workspace": {"id": 5}, "floating": True, "at": [10, 60], "size": [900, 700], "mapped": True},
]


class Layouts(IsolatedHome):
    def ctx(self, extra_bins=(), monitors=MONITOR, clients=CLIENTS):
        cmds = {"hyprctl -j monitors": {"out": json.dumps(monitors)}, "hyprctl -j clients": {"out": json.dumps(clients)}}
        return Context(sysroot="/", command_fixtures=cmds, fixture_bins=["hyprctl"] + list(extra_bins))

    def test_usable_area_handles_scale_rotation_and_panels(self):
        self.assertEqual(layouts.usable_area(MONITOR[0]), (0, 46, 2560, 1394))
        rot = dict(MONITOR[0], scale=2.0, transform=1, reserved=[0, 0, 0, 0])
        self.assertEqual(layouts.usable_area(rot), (0, 0, 720, 1280))

    def test_plan_matches_existing_windows_and_launchers(self):
        p = layouts.plan(self.ctx(extra_bins=["code"]), "developer")
        self.assertTrue(p["ok"])
        by_role = {s["role"]: s for s in p["slots"]}
        self.assertEqual(by_role["terminal"]["window"]["address"], "0x1")
        self.assertEqual(by_role["browser"]["window"]["address"], "0x2")
        self.assertEqual(by_role["editor"]["launch"], ["code"])
        t = by_role["terminal"]
        self.assertEqual((t["x"], t["y"]), (8, 46 + 8))

    def test_missing_app_is_skipped_not_faked(self):
        p = layouts.plan(self.ctx(), "developer")
        self.assertIn("no editor application is installed", [s for s in p["slots"] if s["role"] == "editor"][0]["skip"])

    def test_tiny_monitor_skips_small_regions(self):
        small = [dict(MONITOR[0], width=640, height=480, reserved=[0, 0, 0, 0])]
        p = layouts.plan(self.ctx(monitors=small), "research")
        self.assertTrue(any(s["skip"] and "too small" in s["skip"] for s in p["slots"]))

    def test_apply_dispatches_validated_geometry_and_records_undo(self):
        cmds = {"hyprctl -j monitors": {"out": json.dumps(MONITOR)}, "hyprctl -j clients": {"out": json.dumps(CLIENTS)}}
        for c in ("movetoworkspacesilent 3,address:0x1", "setfloating address:0x1", "movetoworkspacesilent 3,address:0x2"):
            cmds["hyprctl dispatch " + c] = {"out": "ok"}
        ctx = Context(sysroot="/", command_fixtures=cmds, fixture_bins=["hyprctl"])
        # Geometry dispatches have computed arguments: answer them generically.
        orig = ctx.run
        def run(argv, timeout=15.0, input_text=None):
            if argv[:2] == ["hyprctl", "dispatch"] and argv[2] in ("resizewindowpixel", "movewindowpixel"):
                ctx.calls.append(" ".join(argv))
                from aether.util import CommandResult
                return CommandResult(argv, 0, "ok")
            return orig(argv, timeout, input_text)
        ctx.run = run
        res = layouts.apply(ctx, "developer", launch=False, sleep=lambda s: None)
        self.assertEqual(sorted(res["placed"]), ["browser", "terminal"])
        self.assertIn("hyprctl dispatch setfloating address:0x1", ctx.calls)
        self.assertNotIn("hyprctl dispatch setfloating address:0x2", ctx.calls, "already floating")
        self.assertTrue(any(c.startswith("hyprctl dispatch resizewindowpixel exact 649 1378,address:0x1") for c in ctx.calls), ctx.calls)
        undo = json.loads(slurp(layouts.undo_file()))
        self.assertEqual({w["address"] for w in undo["windows"]}, {"0x1", "0x2"})

    def test_user_layout_validation(self):
        self.assertIsNone(layouts.check({"slots": [{"role": "terminal", "x": 0.5, "y": 0, "w": 0.7, "h": 1}]})[0])
        self.assertIsNone(layouts.check({"slots": [{"role": "shell", "x": 0, "y": 0, "w": 1, "h": 1}]})[0])
        self.assertIsNotNone(layouts.check({"slots": [{"role": "terminal", "x": 0, "y": 0, "w": 1, "h": 1}]})[0])


# -- capabilities -------------------------------------------------------------

class Capabilities(unittest.TestCase):
    def _tier(self, scenario, env=None):
        s = scenario()
        self.addCleanup(s.cleanup)
        return capabilities.summary(s.ctx(env))

    def test_discrete_desktop_gets_ultra(self):
        self.assertEqual(self._tier(fixtures.nvidia_desktop)["tier"], "ultra")

    def test_hybrid_laptop_stays_balanced_and_never_queries_the_dgpu(self):
        s = fixtures.hybrid_laptop()
        self.addCleanup(s.cleanup)
        ctx = s.ctx()
        res = capabilities.summary(ctx)
        self.assertEqual(res["tier"], "balanced")
        self.assertTrue(res["hybrid"])
        self.assertFalse([c for c in ctx.calls if "nvidia-smi" in c or "vulkaninfo" in c or "glxinfo" in c], ctx.calls)

    def test_no_gpu_and_forced_software_disable_shaders(self):
        self.assertEqual(self._tier(fixtures.empty_system)["shaders"], False)
        res = self._tier(fixtures.amd_desktop, {"QT_QUICK_BACKEND": "software"})
        self.assertEqual((res["tier"], res["shaders"]), ("eco", False))


# -- system status ------------------------------------------------------------

class SystemStatus(unittest.TestCase):
    def test_check_update_parsing(self):
        out = ("\nkernel.x86_64          6.11.8-300.fc41   updates\n"
               "mesa-dri-drivers.i686  24.2.8-1.fc41     updates-testing\n"
               "Obsoleting Packages\nold.noarch 1-1 updates\n")
        pkgs = sysinfo.parse_check_update(out)
        self.assertEqual([p["name"] for p in pkgs], ["kernel", "mesa-dri-drivers"])

    def test_updates_reports_count_and_reboot(self):
        ctx = Context(sysroot="/", command_fixtures={
            "dnf -q check-update": {"rc": 100, "out": "bash.x86_64 5.2.32-1.fc41 updates\n"},
            "dnf needs-restarting -r": {"rc": 1, "out": "Reboot is required"}}, fixture_bins=["dnf"])
        res = sysinfo.updates(ctx)
        self.assertEqual((res["count"], res["rebootRequired"]), (1, True))
        self.assertEqual(res["command"][:2], ["sudo", "dnf"])

    def test_service_action_validates_unit_names(self):
        ctx = Context(sysroot="/", command_fixtures={}, fixture_bins=["systemctl"])
        self.assertFalse(sysinfo.service_action(ctx, "restart", "foo; rm -rf ~")["ok"])
        self.assertFalse(sysinfo.service_action(ctx, "mask", "aether-shell.service")["ok"])
        self.assertEqual(ctx.calls, [])


# -- appearance ---------------------------------------------------------------

class Appearance(IsolatedHome):
    def setUp(self):
        super().setUp()
        icons = os.path.join(self.home, ".local", "share", "icons")
        for name, sub, idx in (("Papirus", "48x48", True), ("Bibata", "cursors", True), ("broken", None, False)):
            os.makedirs(os.path.join(icons, name, sub or "x"))
            if idx:
                with open(os.path.join(icons, name, "index.theme"), "w") as fh:
                    fh.write("[Icon Theme]\nName=%s Theme\n" % name)
        os.environ["XDG_DATA_DIRS"] = os.path.join(self.home, "none")
        self.ctx = Context(sysroot="/", command_fixtures={}, fixture_bins=[])

    def test_detection(self):
        t = appearance.themes(self.ctx)
        self.assertEqual([x["id"] for x in t["icons"]], ["Papirus"])
        self.assertEqual([x["id"] for x in t["cursors"]], ["Bibata"])

    def test_unknown_theme_is_refused_and_known_one_written(self):
        self.assertFalse(appearance.set_icons(self.ctx, "Nonexistent")["ok"])
        self.assertTrue(appearance.set_icons(self.ctx, "Papirus")["ok"])
        qt = slurp(os.path.join(self.home, "config", "qt6ct", "qt6ct.conf"))
        self.assertIn("[Appearance]\nicon_theme=Papirus", qt)
        res = appearance.set_cursor(self.ctx, "Bibata", 32)
        self.assertTrue(res["ok"])
        conf = slurp(os.path.join(self.home, "config", "aether-shell", "hypr", "cursor.conf"))
        self.assertIn("env = XCURSOR_THEME,Bibata", conf)
        self.assertFalse(appearance.set_cursor(self.ctx, "Bibata", 999)["ok"])


# -- Hyprland fragments ---------------------------------------------------------

class Fragments(IsolatedHome):
    def test_compat_staleness(self):
        s = fixtures.nvidia_desktop()
        self.addCleanup(s.cleanup)
        s.cmd("hyprctl version -j", '{"tag": "v0.52.1"}')
        ctx = s.ctx()
        path = os.path.join(self.home, "compat.conf")
        self.assertTrue(hyprconf.compat_is_stale(ctx, path))                     # missing
        spit(path, "# Placeholder created by AetherOS.\n")
        self.assertTrue(hyprconf.compat_is_stale(ctx, path))                     # placeholder
        spit(path, hyprconf.generate_compat_conf(ctx, {"workspaceSwipe": True}))
        self.assertFalse(hyprconf.compat_is_stale(ctx, path))                    # current
        s.cmd("hyprctl version -j", '{"tag": "v0.53.0"}')
        self.assertTrue(hyprconf.compat_is_stale(s.ctx(), path))                 # upgraded

    def test_idle_conf_stages(self):
        text = hyprconf.generate_idle_conf(5, 0, 30)
        self.assertIn("timeout = 300", text)
        self.assertIn("timeout = 1800", text)
        self.assertNotIn("dpms off", text)
        self.assertIn("lock_cmd = qs -c aether-shell ipc call sessionlock lock", text)


if __name__ == "__main__":
    unittest.main()
