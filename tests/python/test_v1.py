"""AetherOS 1.0 backend: rendering diagnostics, desktop entries, input,
displays (with auto-revert), autostart, workspaces/sessions, custom themes,
the assistant (real local HTTP servers for Ollama and OpenAI-compatible
streaming), secret storage, redaction, audit, widgets, automation v2."""

import http.server
import io
import json
import os
import shlex
import socketserver
import sys
import tempfile
import threading
import unittest
import zipfile

import fixtures
from test_desktop import IsolatedHome, slurp, spit
from aether import (apps, audit, automation, autostart, config, displays, inputconf, palettes, render, themes, widgets,
                    workspaces)
from aether.ai import providers, registry, secrets, service
from aether.redact import redact
from aether.util import Context


def ctx_with(cmds=None, bins=(), env=None, sysroot="/"):
    return Context(sysroot=sysroot, command_fixtures=cmds or {}, fixture_bins=list(bins), env=env or {})


# -- rendering ----------------------------------------------------------------

class Render(unittest.TestCase):
    def scenario(self):
        s = fixtures.empty_system()
        self.addCleanup(s.cleanup)
        s.file("/usr/share/glvnd/egl_vendor.d/10_nvidia.json", '{"ICD": {"library_path": "libEGL_nvidia.so.0"}}')
        s.file("/usr/share/glvnd/egl_vendor.d/50_mesa.json", '{"ICD": {"library_path": "libEGL_mesa.so.0"}}')
        s.file("/usr/share/vulkan/icd.d/nvidia_icd.json", '{"ICD": {"library_path": "libGLX_nvidia.so.0"}}')
        s.file("/usr/share/vulkan/icd.d/lvp_icd.x86_64.json", '{"ICD": {"library_path": "libvulkan_lvp.so"}}')
        s.file("/usr/lib64/dri/nvidia_drv_video.so", "")
        return s

    def test_files_only_report(self):
        s = self.scenario()
        ctx = s.ctx({"AQ_DRM_DEVICES": "/dev/dri/card1:/dev/dri/card0"})
        r = render.report(ctx)
        self.assertEqual(r["eglVendors"], ["mesa", "nvidia"])
        self.assertTrue(r["qtBackends"]["vulkan"]["available"])
        self.assertEqual(r["vaapiDrivers"], ["nvidia"])
        self.assertEqual(r["compositorDrmDevices"], ["/dev/dri/card1", "/dev/dri/card0"])
        self.assertEqual(ctx.calls, [], "the default report runs nothing (never wakes a GPU)")

    def test_explains_forced_and_session_wide_offload(self):
        s = self.scenario()
        r = render.report(s.ctx({"QSG_RHI_BACKEND": "vulkan", "__NV_PRIME_RENDER_OFFLOAD": "1"}))
        self.assertEqual(r["effectiveBackend"], "vulkan")
        self.assertTrue(any("PRIME render offload" in n for n in r["notes"]))

    def test_only_lavapipe_is_not_hardware_vulkan(self):
        s = fixtures.empty_system()
        self.addCleanup(s.cleanup)
        s.file("/usr/share/vulkan/icd.d/lvp_icd.x86_64.json", '{"ICD": {"library_path": "libvulkan_lvp.so"}}')
        self.assertFalse(render.report(s.ctx())["qtBackends"]["vulkan"]["available"])

    def test_probe_parses_tools(self):
        s = self.scenario()
        s.bins.update({"eglinfo", "vulkaninfo"})
        s.cmd("eglinfo -B", "GBM platform:\nEGL API version: 1.5\nOpenGL core profile renderer: NVIDIA GeForce RTX 4050 Laptop GPU/PCIe/SSE2\n"
                            "OpenGL core profile version: 4.6.0 NVIDIA 580.95.05\n")
        s.cmd("vulkaninfo --summary", "Vulkan Instance Version: 1.4.309\nDevices:\n========\nGPU0:\n\tapiVersion = 1.4.303\n"
                                      "\tdeviceType = PHYSICAL_DEVICE_TYPE_DISCRETE_GPU\n\tdeviceName = NVIDIA GeForce RTX 4050 Laptop GPU\n\tdriverName = NVIDIA\n")
        r = render.report(s.ctx(), probe=True)
        self.assertIn("RTX 4050", r["egl"]["platforms"][0]["renderer"])
        self.assertEqual(r["vulkan"]["devices"][0]["deviceType"], "PHYSICAL_DEVICE_TYPE_DISCRETE_GPU")


# -- desktop entries / autostart / sessions -----------------------------------

def write_app(base, app_id, extra=""):
    os.makedirs(base, exist_ok=True)
    spit(os.path.join(base, app_id), "[Desktop Entry]\nType=Application\nName=%s\nExec=%s\n%s" % (app_id[:-8], extra or app_id[:-8] + " %U", ""))


class Apps(IsolatedHome):
    def setUp(self):
        super().setUp()
        self.apps_dir = os.path.join(self.home, ".local/share/applications")
        os.environ["XDG_DATA_HOME"] = os.path.join(self.home, ".local/share")
        os.environ["XDG_DATA_DIRS"] = os.path.join(self.home, "none")
        os.makedirs(self.apps_dir)
        spit(os.path.join(self.apps_dir, "org.mozilla.firefox.desktop"),
             "[Desktop Entry]\nType=Application\nName=Firefox\nExec=firefox --name \"My Profile\" %u\nStartupWMClass=firefox\n")
        spit(os.path.join(self.apps_dir, "kitty.desktop"), "[Desktop Entry]\nType=Application\nName=kitty\nExec=kitty\n")

    def test_exec_parsing_strips_field_codes_and_keeps_quoting(self):
        a = apps.all_apps()["org.mozilla.firefox.desktop"]
        self.assertEqual(apps.argv(a), ["firefox", "--name", "My Profile"])

    def test_class_mapping(self):
        self.assertEqual(apps.for_class("firefox")["id"], "org.mozilla.firefox.desktop")
        self.assertEqual(apps.for_class("kitty")["id"], "kitty.desktop")
        self.assertIsNone(apps.for_class("unknown-thing"))

    def test_session_save_and_restore_quote_everything(self):
        clients = [{"class": "firefox", "workspace": {"id": 2}}, {"class": "kitty", "workspace": {"id": 1}},
                   {"class": "mystery", "workspace": {"id": 3}}, {"class": "kitty", "workspace": {"id": -98}}]
        ctx = ctx_with({"hyprctl -j clients": {"out": json.dumps(clients)}}, bins=["hyprctl"])
        res = workspaces.save_session(ctx)
        self.assertEqual((res["saved"], res["skipped"]), (2, ["mystery"]))
        # Restore with nothing running; also tamper with the file to name a command.
        data = json.loads(slurp(workspaces.session_path()))
        data["entries"].append({"app": "kitty.desktop; rm -rf ~", "workspace": 4})
        spit(workspaces.session_path(), json.dumps(data))
        out = workspaces.restore_session(ctx_with({"hyprctl -j clients": {"out": "[]"}}, bins=["hyprctl"]), dry_run=True)
        cmds = {l["app"]: l["command"] for l in out["launched"]}
        self.assertEqual(cmds["org.mozilla.firefox.desktop"], "[workspace 2 silent] firefox --name 'My Profile'")
        self.assertIn("kitty.desktop; rm -rf ~", out["skipped"], "unknown app ids are skipped, never executed")
        self.assertEqual(shlex.split(cmds["org.mozilla.firefox.desktop"].split("] ", 1)[1]), ["firefox", "--name", "My Profile"])

    def test_restore_skips_running_apps(self):
        os.makedirs(os.path.dirname(workspaces.session_path()), exist_ok=True)
        spit(workspaces.session_path(), json.dumps({"entries": [{"app": "kitty.desktop", "class": "kitty", "workspace": 1}]}))
        out = workspaces.restore_session(ctx_with({"hyprctl -j clients": {"out": '[{"class": "kitty"}]'}}, bins=["hyprctl"]), dry_run=True)
        self.assertEqual(out["launched"], [])

    def test_app_rules_both_syntaxes(self):
        rules = [{"app": "firefox", "workspace": 2, "silent": True}, {"app": "bad class", "workspace": 3}]
        legacy = workspaces.render_rules(rules, v2=False)
        self.assertIn("windowrule = workspace 2 silent, class:^(firefox)$", legacy)
        self.assertIn("windowrule = match:class ^(firefox)$, workspace 2 silent", workspaces.render_rules(rules, v2=True))
        self.assertNotIn("bad class", legacy)


class Autostart(IsolatedHome):
    def setUp(self):
        super().setUp()
        self.sysdir = os.path.join(self.home, "etc-xdg")
        os.environ["XDG_CONFIG_DIRS"] = self.sysdir
        write_app(os.path.join(self.sysdir, "autostart"), "tracker.desktop")
        spit(os.path.join(self.sysdir, "autostart", "gnome-only.desktop"),
             "[Desktop Entry]\nType=Application\nName=GNOME thing\nExec=x\nOnlyShowIn=GNOME;\n")
        os.environ["XDG_DATA_HOME"] = os.path.join(self.home, ".local/share")
        os.environ["XDG_DATA_DIRS"] = os.path.join(self.home, "none")
        write_app(os.path.join(self.home, ".local/share/applications"), "syncthing.desktop")

    def test_disable_and_enable_system_entry_with_override(self):
        self.assertTrue(autostart.disable("tracker.desktop")["ok"])
        e = {x["id"]: x for x in autostart.entries()}["tracker.desktop"]
        self.assertEqual((e["enabled"], e["source"]), (False, "override"))
        self.assertTrue(autostart.enable("tracker.desktop")["ok"])
        self.assertFalse(os.path.exists(os.path.join(autostart.user_dir(), "tracker.desktop")), "override removed")
        self.assertTrue({x["id"]: x for x in autostart.entries()}["tracker.desktop"]["enabled"])

    def test_only_show_in_is_reported(self):
        self.assertFalse({x["id"]: x for x in autostart.entries()}["gnome-only.desktop"]["appliesHere"])

    def test_add_and_remove_user_entry_never_system_files(self):
        self.assertTrue(autostart.add("syncthing.desktop")["ok"])
        self.assertFalse(autostart.add("syncthing.desktop")["ok"])
        self.assertFalse(autostart.remove("tracker.desktop")["ok"], "system entries are disabled, not deleted")
        self.assertTrue(autostart.remove("syncthing.desktop")["ok"])
        self.assertFalse(autostart.add("../evil.desktop")["ok"])

    def test_run_respects_setting(self):
        ctx = ctx_with(bins=["systemctl"])
        self.assertFalse(autostart.run(ctx, False)["started"])
        self.assertEqual(ctx.calls, [])
        ctx = ctx_with({"systemctl --user start xdg-desktop-autostart.target": {"out": ""}}, bins=["systemctl"])
        self.assertTrue(autostart.run(ctx, True)["started"])


# -- input --------------------------------------------------------------------

EVDEV = """! model
  pc105           Generic 105-key PC

! layout
  us              English (US)
  de              German

! variant
  dvorak          us: English (Dvorak)
  nodeadkeys      de: German (no dead keys)

! option
  grp                  Switching to another layout
  grp:alt_shift_toggle Alt+Shift
  caps:escape          Make Caps Lock an additional Esc
"""


class Input(IsolatedHome):
    def ctx(self, hypr=True):
        s = fixtures.empty_system()
        self.addCleanup(s.cleanup)
        s.file("/usr/share/X11/xkb/rules/evdev.lst", EVDEV)
        s.bins.add("hyprctl")
        return s, s.ctx({"HYPRLAND_INSTANCE_SIGNATURE": "x"} if hypr else {})

    def settings(self, **kw):
        s = dict(config.defaults()["input"])
        s.update(kw)
        return s

    def test_catalog(self):
        _s, ctx = self.ctx()
        cat = inputconf.xkb_catalog(ctx)
        self.assertEqual(sorted(cat["layouts"]), ["de", "us"])
        self.assertIn("dvorak", cat["variants"]["us"])
        self.assertIn("caps:escape", cat["options"])

    def test_validation(self):
        _s, ctx = self.ctx()
        cat = inputconf.xkb_catalog(ctx)
        self.assertEqual(inputconf.validate(self.settings(kbLayout="us,de", kbVariant="dvorak,nodeadkeys", kbOptions="grp:alt_shift_toggle"), cat), [])
        self.assertTrue(inputconf.validate(self.settings(kbLayout="xx"), cat))
        self.assertTrue(inputconf.validate(self.settings(kbLayout="us", kbVariant="nodeadkeys"), cat))
        self.assertTrue(inputconf.validate(self.settings(kbOptions="caps:escape ; exec rm"), cat))

    def test_apply_writes_and_applies_live(self):
        s, ctx = self.ctx()
        st = self.settings(kbLayout="de", tapToClick=False, sensitivity=-0.25)
        s.cmd("hyprctl --batch " + " ; ".join(inputconf.live_commands(st)), "ok")
        res = inputconf.apply(ctx, st)
        self.assertTrue(res["ok"] and res["live"])
        text = slurp(inputconf.path())
        self.assertIn("kb_layout = de", text)
        self.assertIn("tap-to-click = false", text)
        self.assertIn("sensitivity = -0.25", text)

    def test_invalid_is_not_written(self):
        _s, ctx = self.ctx()
        self.assertFalse(inputconf.apply(ctx, self.settings(kbLayout="nope"))["ok"])
        self.assertFalse(os.path.exists(inputconf.path()))


# -- displays -----------------------------------------------------------------

MONS = [{"name": "eDP-1", "description": "BOE 0x0BCA", "width": 2560, "height": 1600, "refreshRate": 165.0, "x": 0, "y": 0,
         "scale": 1.6, "transform": 0, "disabled": False, "focused": True,
         "availableModes": ["2560x1600@165.00Hz", "2560x1600@60.00Hz", "1920x1200@60.00Hz"]}]


class Displays(IsolatedHome):
    def ctx(self):
        cmds = {"hyprctl -j monitors all": {"out": json.dumps(MONS)}}
        ctx = ctx_with(cmds, bins=["hyprctl"])
        orig = ctx.run

        def run(argv, timeout=15.0, input_text=None):
            if argv[:2] == ["hyprctl", "keyword"]:
                ctx.calls.append(" ".join(argv))
                from aether.util import CommandResult
                return CommandResult(argv, 0, "ok")
            return orig(argv, timeout, input_text)
        ctx.run = run
        return ctx

    def test_rejects_modes_the_monitor_does_not_offer(self):
        res = displays.apply(self.ctx(), "eDP-1", "3840x2160@60.00Hz", spawn=lambda s: None)
        self.assertFalse(res["ok"])
        res = displays.apply(self.ctx(), "eDP-1", "2560x1600@60.00Hz", scale=1.7, spawn=lambda s: None)
        self.assertFalse(res["ok"])

    def test_apply_then_watchdog_reverts_unless_confirmed(self):
        ctx = self.ctx()
        started = []
        res = displays.apply(ctx, "eDP-1", "2560x1600@60.00Hz", scale=1.6, confirm_within=15, spawn=started.append)
        self.assertTrue(res["ok"])
        self.assertEqual(started, [15])
        self.assertIn("monitor = desc:BOE 0x0BCA,2560x1600@60.00,auto,1.6", slurp(displays.fragment_path()))
        self.assertFalse(displays.apply(ctx, "eDP-1", "1920x1200@60.00Hz", spawn=lambda s: None)["ok"], "one change at a time")
        self.assertTrue(displays.watchdog(15, ctx=ctx, sleep=lambda s: None))
        self.assertNotIn("2560x1600@60", slurp(displays.fragment_path()))
        self.assertTrue(any("2560x1600@165.000" in c for c in ctx.calls), "previous live mode re-applied")

    def test_confirmed_change_is_kept(self):
        ctx = self.ctx()
        displays.apply(ctx, "eDP-1", "2560x1600@60.00Hz", scale=1.6, spawn=lambda s: None)
        self.assertTrue(displays.confirm())
        self.assertFalse(displays.watchdog(15, ctx=ctx, sleep=lambda s: None))
        self.assertIn("2560x1600@60.00", slurp(displays.fragment_path()))

    def test_profiles_match_monitor_sets(self):
        ctx = self.ctx()
        self.assertTrue(displays.save_profile(ctx, "laptop")["ok"])
        self.assertEqual(displays.auto_profile(ctx)["applied"], "laptop")
        other = ctx_with({"hyprctl -j monitors all": {"out": json.dumps(MONS + [dict(MONS[0], name="DP-1", description="Dell U2723QE")])}}, bins=["hyprctl"])
        self.assertIsNone(displays.auto_profile(other)["applied"])


# -- themes -------------------------------------------------------------------

class Themes(IsolatedHome):
    def test_create_from_base_with_overrides(self):
        res = themes.create("sunset", "nord", {"accent": "#ff8800"}, "Sunset")
        self.assertTrue(res["ok"], res)
        t = themes.listing()["sunset"]
        self.assertEqual((t["accent"], t["bg0"]), ("#FF8800", palettes.resolve("nord")["bg0"]))
        self.assertIn("sunset", palettes.load())

    def test_validation(self):
        self.assertFalse(themes.create("nord", "aether", {})["ok"], "can't shadow a built-in")
        self.assertFalse(themes.create("x", "aether", {})["ok"], "id too short")
        self.assertFalse(themes.create("bad-colour", "aether", {"accent": "orange"})["ok"])
        src = os.path.join(self.home, "t.json")
        good = dict(palettes.resolve("dracula"), label="D2")
        spit(src, json.dumps(dict(good, script="rm -rf ~")))
        self.assertFalse(themes.import_file(src, "d-two")["ok"], "unknown fields reject the file")
        spit(src, json.dumps(good))
        self.assertTrue(themes.import_file(src, "d-two")["ok"])

    def test_user_theme_reaches_terminals(self):
        themes.create("sunset", "nord", {"accent": "#ff8800"}, "Sunset")
        res = palettes.apply(ctx_with(), "sunset", None, True)
        self.assertIn("#FF8800", slurp(os.path.join(self.home, "config/aether-shell/terminal/kitty-theme.conf")))


# -- assistant ----------------------------------------------------------------

class _Handler(http.server.BaseHTTPRequestHandler):
    reply = "Opening Settings for you.\n```aether-actions\n" \
            '[{"action": "open-settings", "args": {"section": "gpu"}}, {"action": "run-shell", "args": {"cmd": "rm -rf ~"}}]\n```'
    seen = []

    def log_message(self, *a):
        pass

    def do_GET(self):
        body = {"/api/tags": {"models": [{"name": "llama3.2"}]}, "/v1/models": {"data": [{"id": "gpt-x"}]}}.get(self.path)
        self.send_response(200 if body else 404)
        self.end_headers()
        self.wfile.write(json.dumps(body or {}).encode())

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        req = json.loads(self.rfile.read(length))
        _Handler.seen.append({"path": self.path, "auth": self.headers.get("Authorization"), "body": req})
        self.send_response(200)
        self.end_headers()
        words = [w + " " for w in self.reply.split(" ")]
        if self.path == "/api/chat":
            for w in words:
                self.wfile.write((json.dumps({"message": {"content": w}, "done": False}) + "\n").encode())
            self.wfile.write((json.dumps({"done": True}) + "\n").encode())
        else:
            for w in words:
                self.wfile.write(("data: " + json.dumps({"choices": [{"delta": {"content": w}}]}) + "\n\n").encode())
            self.wfile.write(b"data: [DONE]\n\n")


class Assistant(IsolatedHome):
    @classmethod
    def setUpClass(cls):
        cls.server = socketserver.ThreadingTCPServer(("127.0.0.1", 0), _Handler)
        cls.port = cls.server.server_address[1]
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def configure(self, **ai):
        base = {"enabled": True, "provider": "ollama", "endpoint": "http://127.0.0.1:%d" % self.port, "model": "llama3.2", "localOnly": True}
        base.update(ai)
        self.write_config({"ai": base})

    def run_ask(self, ctx=None):
        return list(service.ask(ctx or ctx_with(), [{"role": "user", "content": "open gpu settings"}]))

    def test_disabled_by_default(self):
        ev = self.run_ask()
        self.assertEqual(ev[-1]["type"], "error")
        self.assertIn("off", ev[-1]["error"])

    def test_ollama_streaming_and_action_validation(self):
        self.configure()
        _Handler.seen.clear()
        ev = self.run_ask()
        deltas = [e for e in ev if e["type"] == "delta"]
        final = ev[-1]
        self.assertGreater(len(deltas), 5, "streamed in pieces")
        self.assertEqual(final["type"], "final")
        self.assertEqual(final["text"], "Opening Settings for you.")
        self.assertEqual([a["action"] for a in final["actions"]], ["open-settings"])
        self.assertTrue(any("run-shell" in r for r in final["rejected"]), "no shell action exists")
        sent = _Handler.seen[-1]["body"]["messages"]
        self.assertEqual(sent[0]["role"], "system")
        self.assertIn("cannot run shell commands", sent[0]["content"])
        trail = audit.tail()
        self.assertEqual(trail[-1]["action"], "reply")

    def test_openai_compatible_with_key_from_keyring(self):
        self.configure(provider="openai", endpoint="http://127.0.0.1:%d" % self.port)
        _Handler.seen.clear()
        ctx = ctx_with({"secret-tool lookup service aetheros-ai provider openai": {"out": "sk-testkey1234567890abcdef\n"}}, bins=["secret-tool"])
        ev = self.run_ask(ctx)
        self.assertEqual(ev[-1]["type"], "final", ev[-1])
        self.assertEqual(_Handler.seen[-1]["path"], "/v1/chat/completions")
        self.assertEqual(_Handler.seen[-1]["auth"], "Bearer sk-testkey1234567890abcdef")
        self.assertNotIn("sk-testkey", slurp(audit.path()), "keys never reach the audit log")

    def test_local_only_refuses_remote(self):
        self.configure(endpoint="https://api.example.com")
        ev = self.run_ask()
        self.assertIn("local-only", ev[-1]["error"])
        self.assertIsNotNone(providers.check_endpoint("http://user:pw@127.0.0.1", False))
        self.assertIsNotNone(providers.check_endpoint("http://api.example.com", False), "remote needs https")
        self.assertIsNone(providers.check_endpoint("https://api.example.com", False))

    def test_unreachable_provider_is_an_error_not_a_crash(self):
        self.configure(endpoint="http://127.0.0.1:1")
        ev = self.run_ask()
        self.assertEqual(ev[-1]["type"], "error")
        self.assertIn("can't reach", ev[-1]["error"])

    def test_status_probe_lists_models(self):
        self.configure()
        st = service.status(ctx_with(), probe=True)
        self.assertTrue(st["reachable"])
        self.assertEqual(st["models"], ["llama3.2"])

    def test_history_is_opt_in_and_redacted(self):
        self.configure()
        self.run_ask()
        self.assertFalse(os.path.exists(service.history_path()))
        self.configure(keepHistory=True)
        list(service.ask(ctx_with(), [{"role": "user", "content": "my key is sk-abcdefghijklmnopqrstu"}]))
        h = slurp(service.history_path())
        self.assertIn("sk-[REDACTED]", h)
        self.assertEqual(os.stat(service.history_path()).st_mode & 0o777, 0o600)


class Registry(unittest.TestCase):
    CHECKS = {"app": lambda v: v == "firefox.desktop", "layout": lambda v: v == "developer",
              "profile": lambda v: v == "minimal", "palette": lambda v: v == "nord"}

    def v(self, action, **args):
        return registry.validate({"action": action, "args": args}, self.CHECKS)

    def test_valid_and_invalid(self):
        self.assertIsNotNone(self.v("launch-app", app="firefox.desktop")[0])
        self.assertIn("doesn't exist", self.v("launch-app", app="steam.desktop")[1])
        self.assertIn("bad or missing", self.v("set-volume", value=150)[1])
        self.assertIn("unexpected", self.v("set-dnd", value=True, then="rm")[1])
        self.assertIn("unknown action", self.v("exec", cmd="ls")[1])

    def test_extract_limits_and_bad_json(self):
        many = "```aether-actions\n" + json.dumps([{"action": "lock-screen", "args": {}}] * 9) + "\n```"
        _t, acts, _r = registry.extract(many, self.CHECKS)
        self.assertEqual(len(acts), 5)
        _t, acts, rej = registry.extract("```aether-actions\nnot json\n```", self.CHECKS)
        self.assertEqual((acts, len(rej)), ([], 1))


class Secrets(unittest.TestCase):
    def test_key_goes_through_stdin_not_argv(self):
        ctx = ctx_with({"secret-tool store --label=AetherOS assistant (openai) service aetheros-ai provider openai": {"out": ""}}, bins=["secret-tool"])
        self.assertIsNone(secrets.store(ctx, "openai", "sk-secret-value-1234567890"))
        self.assertFalse(any("sk-secret" in c for c in ctx.calls), ctx.calls)

    def test_rejects_malformed_and_missing_keyring(self):
        self.assertIsNotNone(secrets.store(ctx_with(bins=["secret-tool"]), "openai", "a\nb"))
        self.assertIn("secret-tool not found", secrets.store(ctx_with(), "openai", "k"))
        self.assertEqual(secrets.lookup(ctx_with(env={"AETHER_AI_API_KEY": "envkey"}), "openai"), "envkey")


class Redaction(unittest.TestCase):
    def test_patterns(self):
        text = redact("sk-abcdefghijklmnopqrstuvwx Bearer eyJhbGciOiJIUzI1NiJ9.x password=hunter2 api_key: 'zz9' https://u:p@h/x ghp_" + "a" * 36)
        for secret in ("abcdefghijklmnop", "eyJhbGci", "hunter2", "zz9", "u:p@", "aaaaaaaaaaaa"):
            self.assertNotIn(secret, text)

    def test_nested_and_secret_keys(self):
        self.assertEqual(redact({"apiKey": "x", "nested": ["password=1"]}), {"apiKey": "[REDACTED]", "nested": ["password=[REDACTED]"]})


class Audit(IsolatedHome):
    def test_private_and_rotating(self):
        audit.record("user", "test", {"token": "abc"})
        self.assertEqual(os.stat(audit.path()).st_mode & 0o777, 0o600)
        self.assertEqual(audit.tail()[-1]["args"], {"token": "[REDACTED]"})
        with open(audit.path(), "a") as fh:
            fh.write("x" * (audit.MAX + 10))
        audit.record("user", "after-rotate")
        self.assertTrue(os.path.exists(audit.path() + ".1"))
        self.assertEqual(audit.tail()[-1]["action"], "after-rotate")


# -- widgets ------------------------------------------------------------------

def make_widget(base, wid="hello", qml="import QtQuick\nItem { property var api: null }\n", **manifest):
    d = os.path.join(base, wid)
    os.makedirs(d)
    m = {"aetherWidget": 1, "id": wid, "name": "Hello", "version": "1.0.0", "api": 1, "entry": "Widget.qml", "permissions": ["time"]}
    m.update(manifest)
    spit(os.path.join(d, "widget.json"), json.dumps(m))
    spit(os.path.join(d, "Widget.qml"), qml)
    return d


class Widgets(IsolatedHome):
    def setUp(self):
        super().setUp()
        os.environ["XDG_DATA_HOME"] = os.path.join(self.home, ".local/share")
        self.src = os.path.join(self.home, "src")
        os.makedirs(self.src)

    def test_builtin_widgets_pass_the_same_scanner(self):
        built = [w for w in widgets.listing() if w["source"] == "builtin"]
        self.assertEqual(len(built), 7)
        self.assertTrue(all(w["valid"] for w in built), [w["problems"] for w in built if not w["valid"]])

    def test_scanner_blocks_capability_escapes(self):
        bad = {
            "quickshell": "import Quickshell.Io\nItem {}",
            "xhr": "import QtQuick\nItem { Component.onCompleted: new XMLHttpRequest() }",
            "url": 'import QtQuick\nImage { source: "file:///etc/passwd" }',
            "abs": 'import QtQuick\nImage { source: "/etc/ssh/ssh_host_ed25519_key" }',
            "up": 'import QtQuick\nImage { source: "../../x.png" }',
            "dyn": 'import QtQuick\nItem { Component.onCompleted: Qt.createQmlObject("import Quickshell.Io; Process {}", this) }',
            "eval": "import QtQuick\nItem { Component.onCompleted: eval('1') }",
            "relimport": 'import "../../services"\nItem {}',
            "comment-trick": 'import QtQuick\nImage { source: "http://x" + "" } // harmless comment',
            "url-in-single": "import QtQuick\nImage { source: 'file:///etc/shadow' }",
        }
        for name, qml in bad.items():
            d = make_widget(self.src, "w-" + name, qml)
            self.assertTrue(widgets.scan(d), "%s should be rejected" % name)
        ok = make_widget(self.src, "w-ok", 'import QtQuick\nimport QtQuick.Layouts\nItem { property string s: used + " / " + total; property real used; property real total }')
        self.assertEqual(widgets.scan(ok), [])

    def test_manifest_validation(self):
        for kw in ({"api": 2}, {"permissions": ["filesystem"]}, {"version": "1"}, {"id": "Bad Id"}, {"evil": 1}):
            d = make_widget(self.src, "m%d" % len(os.listdir(self.src)), **kw)
            self.assertIsNone(widgets.read_manifest(d)[0], kw)

    def test_install_dir_and_zip_with_traversal_rejected(self):
        d = make_widget(self.src)
        res = widgets.install(d)
        self.assertTrue(res["ok"], res)
        self.assertFalse(widgets.install(d)["ok"], "no silent overwrite")
        self.assertTrue(widgets.install(d, force=True)["ok"])
        self.assertTrue(widgets.remove("hello")["ok"])
        z = os.path.join(self.home, "evil.zip")
        with zipfile.ZipFile(z, "w") as zf:
            zf.writestr("../../.bashrc", "pwned")
        self.assertFalse(widgets.install(z)["ok"])
        self.assertFalse(os.path.exists(os.path.join(self.home, ".bashrc")))
        z2 = os.path.join(self.home, "ok.zip")
        with zipfile.ZipFile(z2, "w") as zf:
            for f in ("widget.json", "Widget.qml"):
                zf.write(os.path.join(d, f), "hello/" + f)
        self.assertTrue(widgets.install(z2)["ok"])

    def test_builtin_ids_cannot_be_shadowed_or_removed(self):
        d = make_widget(self.src, "clock")
        self.assertFalse(widgets.install(d)["ok"])
        self.assertFalse(widgets.remove("clock")["ok"])


# -- automation v2 ------------------------------------------------------------

class AutomationV2(unittest.TestCase):
    def test_multiple_actions_and_legacy_form(self):
        multi = {"id": "m", "trigger": {"type": "startup"}, "actions": [{"type": "set-dock", "value": True}, {"type": "apply-layout", "value": "developer"}]}
        clean, err = automation.validate_rule(multi)
        self.assertEqual(err, "")
        self.assertEqual(len(clean["actions"]), 2)
        legacy, err = automation.validate_rule({"id": "l", "trigger": {"type": "power-connected"}, "action": {"type": "set-quality", "value": "ultra"}})
        self.assertEqual(legacy["actions"], [{"type": "set-quality", "value": "ultra"}])
        _c, err = automation.validate_rule(dict(multi, action={"type": "next-wallpaper"}))
        self.assertIn("either", err)
        _c, err = automation.validate_rule(dict(multi, actions=[{"type": "next-wallpaper"}] * 6))
        self.assertTrue(err)

    def test_new_triggers_and_actions(self):
        for t in ({"type": "startup"}, {"type": "profile-applied", "value": "gaming"}, {"type": "profile-applied"}):
            self.assertEqual(automation.validate_rule({"id": "x", "trigger": t, "actions": [{"type": "set-motion", "value": "reduced"}]})[1], "")


if __name__ == "__main__":
    unittest.main()


class ShellContracts(unittest.TestCase):
    """Lists the shell and backend must agree on."""
    SHELL = os.path.join(fixtures.REPO, "config", "quickshell", "aether-shell")

    def test_settings_sections_index_and_files_agree(self):
        import re
        settings = slurp(os.path.join(self.SHELL, "shell/settings/Settings.qml"))
        ids = re.findall(r'\{ id: "([a-z]+)", label', settings)
        index = re.findall(r'\{ id: "([a-z]+)", title', slurp(os.path.join(self.SHELL, "shell/settings/SettingsIndex.js")))
        self.assertEqual(sorted(ids), sorted(index), "every section is searchable, every index entry exists")
        for f in re.findall(r'file: "(\w+)"', settings):
            self.assertTrue(os.path.isfile(os.path.join(self.SHELL, "shell/settings/sections/%s.qml" % f)), f)
        self.assertEqual(sorted(registry.SETTINGS_SECTIONS), sorted(ids), "the assistant can open every section, and only real ones")

    def test_assistant_actions_are_handled_by_the_shell(self):
        import re
        svc = slurp(os.path.join(self.SHELL, "services/AssistantService.qml"))
        handled = set(re.findall(r'case "([a-z-]+)":', svc))
        self.assertEqual(sorted(set(registry.ACTIONS)), sorted(handled & set(registry.ACTIONS)))
        self.assertEqual(handled - set(registry.ACTIONS), set(), "no shell handler for an action the registry doesn't allow")

    def test_automation_actions_are_handled_by_the_shell(self):
        import re
        svc = slurp(os.path.join(self.SHELL, "services/AutomationService.qml"))
        body = svc[svc.index("function _runAction"):]
        self.assertEqual(sorted(set(re.findall(r'case "([a-z-]+)":', body))), sorted(automation.ACTIONS))
