"""CLI commands added in AetherOS 1.0: render diagnostics, custom themes,
input, displays, autostart, workspaces/sessions, the assistant, widgets,
audit/logs, island posts. Registered by cli.py next to cli_desktop."""

from __future__ import annotations

import json
import os
import re
import sys
from typing import Any, Dict

from . import audit, autostart, config as config_mod, displays, inputconf, render, themes, widgets, workspaces
from .redact import redact
from .util import Context, Output, confirm, get_logger, state_dir


def _json(data: Any) -> int:
    sys.stdout.write(json.dumps(data, indent=2) + "\n")
    return 0


def _result(args, res: Dict[str, Any], ok_text: str = "Done.") -> int:
    if getattr(args, "json", False):
        _json(res)
        return 0 if res.get("ok", True) else 1
    out = Output()
    if res.get("ok", True):
        out.status("pass", ok_text)
    for p in res.get("problems", []) or ([res["error"]] if res.get("error") else []):
        out.status("fail", p)
    return 0 if res.get("ok", True) else 1


def _section(name: str) -> Dict[str, Any]:
    out = dict(config_mod.defaults()[name])
    data, _err = config_mod.load()
    clean, _p = config_mod.validate({name: (data or {}).get(name, {})})
    out.update(clean.get(name, {}))
    return out


# -- render -------------------------------------------------------------------

def cmd_render(ctx: Context, args) -> int:
    if args.probe and not args.json:
        Output().note("Probing loads the GPU drivers: on a hybrid laptop this wakes the discrete GPU briefly.")
    data = render.report(ctx, probe=args.probe)
    if args.json:
        return _json(data)
    out = Output()
    out.heading("Rendering")
    out.kv("Qt Quick backend", data["effectiveBackend"] + (" (forced by environment)" if data["forcedBackend"] else ""))
    for name, b in data["qtBackends"].items():
        out.status("pass" if b["available"] else "warn", "%-8s %s" % (name, "available" if b["available"] else "unavailable — " + b["why"]))
    out.kv("EGL vendors", ", ".join(data["eglVendors"]) or "none")
    out.kv("Vulkan drivers", ", ".join("%s (%s)" % (i["file"], i["vendor"]) for i in data["vulkanIcds"]) or "none")
    out.kv("VA-API drivers", ", ".join(data["vaapiDrivers"]) or "none")
    out.kv("Compositor GPU", ", ".join(data["compositorDrmDevices"]) or "default (first DRM device)")
    for n in data["notes"]:
        out.bullet(n)
    if data["probed"]:
        egl, vk = data["egl"], data["vulkan"]
        out.heading("Probe")
        if egl.get("available"):
            for p in egl["platforms"]:
                out.kv("EGL %s" % p["platform"], "%s — %s" % (p["renderer"], p["version"]))
        else:
            out.status("warn", "EGL: " + egl["why"])
        if vk.get("available"):
            for d in vk["devices"]:
                out.kv("Vulkan", "%s (%s, %s)" % (d.get("deviceName"), d.get("deviceType"), d.get("driverName")))
        else:
            out.status("warn", "Vulkan: " + vk["why"])
    return 0


# -- custom themes ------------------------------------------------------------

def cmd_themes(ctx: Context, args) -> int:
    sub = args.themes_cmd or "list"
    if sub == "list":
        data = themes.listing()
        if args.json:
            return _json(data)
        for tid, t in data.items():
            Output().bullet("%-20s %s (%s)" % (tid, t["label"], "dark" if t["dark"] else "light"))
        if not data:
            Output().note("No custom themes. Create one: aether themes create my-theme --from nord --accent '#ff8800'")
        return 0
    if sub == "create":
        over = {}
        for tok in ("accent", "accentAlt", "bg0", "bg1", "bg2", "glass", "surface", "text"):
            v = getattr(args, tok.lower(), None)
            if v:
                over[tok] = v
        res = themes.create(args.id, args.base, over, args.label or "", None if args.mode is None else args.mode == "dark")
        if res["ok"]:
            get_logger().info("custom theme %s created", args.id)
        return _result(args, res, "Theme %s saved. Select it in Settings → Style." % args.id)
    if sub == "import":
        return _result(args, themes.import_file(args.file, args.id), "Imported %s." % args.id)
    if sub == "export":
        return _result(args, themes.export(args.id, args.file), "Exported to %s." % args.file)
    if sub == "delete":
        if not confirm("Delete the custom theme %s?" % args.id, args.yes):
            return 1
        return _result(args, themes.delete(args.id), "Deleted.")
    return 2


# -- input --------------------------------------------------------------------

def cmd_input(ctx: Context, args) -> int:
    sub = args.input_cmd or "show"
    if sub == "layouts":
        cat = inputconf.xkb_catalog(ctx)
        if args.json:
            return _json(cat)
        for code, desc in sorted(cat["layouts"].items()):
            Output().bullet("%-8s %s" % (code, desc))
        return 0
    s = _section("input")
    if sub == "show":
        if args.json:
            return _json(s)
        sys.stdout.write(inputconf.render(s))
        return 0
    res = inputconf.apply(ctx, s, live=not args.no_live)
    return _result(args, res, "Input settings written%s." % (" and applied" if res.get("live") else ""))


# -- displays -----------------------------------------------------------------

def cmd_display(ctx: Context, args) -> int:
    sub = args.display_cmd or "list"
    if sub == "list":
        mons = displays.monitors(ctx)
        if mons is None:
            return _result(args, {"ok": False, "error": "Hyprland is not running"})
        if args.json:
            return _json(mons)
        out = Output()
        for m in mons:
            out.heading("%s — %s" % (m["name"], m["description"]))
            out.kv("Mode", "%dx%d @ %.2f Hz, scale %g, at %d,%d%s" % (m["width"], m["height"], m["refresh"], m["scale"], m["x"], m["y"], " (disabled)" if m["disabled"] else ""))
            out.kv("Available", ", ".join(m["modes"][:8]) + (" …" if len(m["modes"]) > 8 else ""))
        return 0
    if sub == "apply":
        res = displays.apply(ctx, args.monitor, args.mode, args.position, args.scale, args.confirm_within)
        if res.get("ok"):
            get_logger().info("display change %s (confirm within %ss)", res["applied"], args.confirm_within)
            audit.record("user", "display-apply", {"line": res["applied"]})
        return _result(args, res, "Applied. Keep it with `aether display confirm` within %d s, or it reverts." % args.confirm_within)
    if sub == "confirm":
        ok = displays.confirm()
        return _result(args, {"ok": ok, "error": None if ok else "nothing to confirm"}, "Display configuration kept.")
    if sub == "revert":
        return _result(args, displays.revert(ctx), "Previous display configuration restored.")
    if sub == "save-profile":
        return _result(args, displays.save_profile(ctx, args.name), "Profile saved for the connected monitors.")
    if sub == "auto":
        res = displays.auto_profile(ctx)
        return _result(args, res, "Applied profile %s." % res.get("applied") if res.get("applied") else "No saved profile matches these monitors.")
    return 2


# -- autostart ----------------------------------------------------------------

def cmd_autostart(ctx: Context, args) -> int:
    sub = args.start_cmd or "list"
    if sub == "list":
        data = autostart.entries()
        if args.json:
            return _json(data)
        for e in data:
            Output().bullet("%-40s %-8s %s%s" % (e["id"], "on" if e["enabled"] else "off", e["name"], "" if e["appliesHere"] else "  (not for Hyprland)"))
        return 0
    if sub == "run":
        return _result(args, autostart.run(ctx, _section("general").get("xdgAutostart", True)), "Autostart target started.")
    fn = {"enable": autostart.enable, "disable": autostart.disable, "add": autostart.add, "remove": autostart.remove}[sub]
    return _result(args, fn(args.id), "%s: %s" % (sub, args.id))


# -- workspaces ---------------------------------------------------------------

def cmd_workspace(ctx: Context, args) -> int:
    sub = args.ws_cmd or "rules"
    if sub == "rules":
        return _result(args, workspaces.write_rules(ctx, _section("workspaces")["appRules"]), "Workspace rules written.")
    if sub == "save":
        res = workspaces.save_session(ctx)
        return _result(args, res, "Saved %s app(s)%s." % (res.get("saved"), ("; skipped " + ", ".join(res["skipped"])) if res.get("skipped") else ""))
    if sub == "restore":
        if args.if_enabled and not _section("workspaces")["restoreSession"]:
            return 0
        res = workspaces.restore_session(ctx, dry_run=args.dry_run)
        return _result(args, res, "%s %d app(s)." % ("Would launch" if args.dry_run else "Launched", len(res.get("launched", []))))
    return 2


# -- assistant ----------------------------------------------------------------

def cmd_ai(ctx: Context, args) -> int:
    from .ai import registry, secrets, service
    sub = args.ai_cmd or "status"
    if sub == "status":
        data = service.status(ctx, probe=args.probe)
        if args.json:
            return _json(data)
        out = Output()
        out.kv("Enabled", data["enabled"])
        out.kv("Provider", "%s at %s, model %s" % (data["provider"], data["endpoint"], data["model"]))
        out.kv("Local only", data["localOnly"])
        out.kv("API key", "stored in keyring" if data["keyStored"] else "none")
        if data["endpointProblem"]:
            out.status("warn", data["endpointProblem"])
        if args.probe:
            out.status("pass" if data["reachable"] else "fail", ("reachable; models: " + ", ".join(data["models"][:10])) if data["reachable"] else data.get("error", "unreachable"))
        return 0
    if sub == "set-key":
        if sys.stdin.isatty():
            import getpass
            key = getpass.getpass("API key for %s (input hidden): " % args.provider)
        else:
            key = sys.stdin.read()
        err = secrets.store(ctx, args.provider, key)
        if err is None:
            audit.record("user", "ai-set-key", {"provider": args.provider})
        return _result(args, {"ok": err is None, "error": err}, "Key stored in the keyring.")
    if sub == "clear-key":
        ok = secrets.clear(ctx, args.provider)
        return _result(args, {"ok": ok, "error": None if ok else "nothing removed"}, "Key removed.")
    if sub == "actions":
        data = [{"id": k, "params": list(v["params"]), "description": v["description"]} for k, v in registry.ACTIONS.items()]
        if args.json:
            return _json(data)
        for d in data:
            sys.stdout.write("%-18s %s\n" % (d["id"], d["description"]))
        return 0
    if sub == "history":
        if args.clear:
            service.clear_history()
            return _result(args, {"ok": True}, "History cleared.")
        try:
            with open(service.history_path(), encoding="utf-8") as fh:
                sys.stdout.write(fh.read())
        except OSError:
            Output().note("No history (Settings → AI assistant → keep history is off by default).")
        return 0
    if sub == "ask":
        # The conversation arrives on stdin as JSON ({"messages": [...]}) —
        # never in argv, which other users can read in `ps`.
        try:
            raw = json.loads(sys.stdin.read() or "{}")
        except ValueError:
            raw = {}
        msgs = raw.get("messages") if isinstance(raw, dict) else None
        if args.question:
            msgs = [{"role": "user", "content": " ".join(args.question)}]
        if not isinstance(msgs, list):
            sys.stdout.write(json.dumps({"type": "error", "error": "no messages"}) + "\n")
            return 1
        rc = 0
        for event in service.ask(ctx, msgs):
            if args.stream:
                sys.stdout.write(json.dumps(event) + "\n")
                sys.stdout.flush()
            elif event["type"] == "final":
                sys.stdout.write(event["text"] + "\n")
                for a in event["actions"]:
                    sys.stdout.write("  proposed: %s %s\n" % (a["action"], json.dumps(a["args"])))
                for r in event["rejected"]:
                    sys.stdout.write("  rejected: %s\n" % r)
            elif event["type"] == "error":
                sys.stderr.write(event["error"] + "\n")
                rc = 1
        return rc
    if sub == "log-action":
        # The shell reports what the user confirmed (or declined).
        try:
            data = json.loads(args.data)
        except ValueError:
            return 2
        audit.record("ai", "user-%s" % ("ran" if args.ran else "declined"), data)
        return 0
    return 2


# -- widgets ------------------------------------------------------------------

def cmd_widget(ctx: Context, args) -> int:
    sub = args.widget_cmd or "list"
    if sub == "list":
        data = widgets.listing()
        if args.json:
            return _json(data)
        for w in data:
            Output().status("pass" if w["valid"] else "fail", "%-14s %-8s %s  [%s]" % (w["id"], w["source"], w["name"], ", ".join(w["permissions"])))
        return 0
    if sub == "inspect":
        return _json(widgets.inspect(args.path)) if args.json else _result(args, widgets.inspect(args.path), "Widget is valid.")
    if sub == "install":
        info = widgets.inspect(args.path) if os.path.isdir(args.path) else None
        if info and info["ok"] and not args.yes and sys.stdin.isatty():
            perms = info["manifest"]["permissions"]
            print("This widget asks for: %s" % (", ".join("%s (%s)" % (p, widgets.PERMISSIONS[p]) for p in perms) or "nothing"))
            if not confirm("Install %s?" % info["manifest"]["name"], False):
                return 1
        res = widgets.install(args.path, force=args.force)
        if res.get("ok"):
            audit.record("user", "widget-install", {"id": res["id"], "permissions": res["permissions"]})
        return _result(args, res, "Installed %s. Add it in Settings → Widgets." % res.get("id"))
    if sub == "remove":
        res = widgets.remove(args.id)
        if res.get("ok"):
            audit.record("user", "widget-remove", {"id": args.id})
        return _result(args, res, "Removed %s." % args.id)
    return 2


# -- logs / audit / island -------------------------------------------------------

def cmd_logs(ctx: Context, args) -> int:
    if args.audit:
        data = audit.tail(args.lines)
        if args.json:
            return _json(data)
        for e in data:
            sys.stdout.write("%s  %-10s %-20s %s %s\n" % (e.get("time"), e.get("actor"), e.get("action"), e.get("result"), json.dumps(e.get("args"))))
        return 0
    path = os.path.join(state_dir(), "aether.log")
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.readlines()[-args.lines:]
    except OSError:
        lines = []
    sys.stdout.write("".join(redact(l) for l in lines))
    if args.shell and ctx.which("journalctl"):
        res = ctx.run(["journalctl", "--user", "-u", "aether-shell", "-n", str(args.lines), "--no-pager", "-o", "short-iso"], timeout=15)
        sys.stdout.write("\n--- aether-shell journal ---\n" + redact(res.out))
    return 0


def cmd_island(ctx: Context, args) -> int:
    title = args.title[:80]
    body = (args.body or "")[:200]
    if not ctx.which("qs"):
        return _result(args, {"ok": False, "error": "quickshell (qs) not found"})
    res = ctx.run(["qs", "-c", "aether-shell", "ipc", "call", "island", "post", title, body], timeout=5)
    return _result(args, {"ok": res.ok, "error": None if res.ok else (res.err or "the shell isn't running").strip()}, "Posted.")


def cmd_config_reset_section(ctx: Context, args) -> int:
    from . import snapshots
    if args.section not in config_mod.SCHEMA:
        return _result(args, {"ok": False, "error": "unknown section %r" % args.section})
    data, err = config_mod.load()
    if data is None:
        return _result(args, {"ok": False, "error": err})
    snapshots.create("pre-reset")
    data.pop(args.section, None)
    config_mod.save(data)
    return _result(args, {"ok": True}, "%s reset to defaults (a snapshot was taken first)." % args.section)


# -- parser -------------------------------------------------------------------

def register(sub, add) -> None:
    sp = add("render", "rendering diagnostics: Qt Quick backend, EGL/Vulkan/VA-API drivers, PRIME (files only unless --probe)")
    sp.add_argument("--probe", action="store_true", help="also run eglinfo/vulkaninfo (may wake a discrete GPU)")

    sp = add("themes", "custom colour themes: list | create | import | export | delete")
    ts = sp.add_subparsers(dest="themes_cmd", metavar="<subcommand>")
    ts.add_parser("list").add_argument("--json", action="store_true")
    x = ts.add_parser("create", help="new theme from a palette with overrides")
    x.add_argument("id")
    x.add_argument("--from", dest="base", default="aether")
    x.add_argument("--label")
    x.add_argument("--mode", choices=("dark", "light"))
    for tok in ("accent", "accentalt", "bg0", "bg1", "bg2", "glass", "surface", "text"):
        x.add_argument("--" + tok, metavar="#RRGGBB")
    x.add_argument("--json", action="store_true")
    for name in ("import", "export"):
        x = ts.add_parser(name)
        x.add_argument("file" if name == "import" else "id")
        x.add_argument("id" if name == "import" else "file")
        x.add_argument("--json", action="store_true")
    x = ts.add_parser("delete")
    x.add_argument("id")
    x.add_argument("--yes", action="store_true")
    x.add_argument("--json", action="store_true")

    sp = add("input", "keyboard/mouse/touchpad: show | apply | layouts")
    ins = sp.add_subparsers(dest="input_cmd", metavar="<subcommand>")
    ins.add_parser("show").add_argument("--json", action="store_true")
    ins.add_parser("layouts").add_argument("--json", action="store_true")
    x = ins.add_parser("apply", help="write input.conf from settings and apply live")
    x.add_argument("--no-live", action="store_true")
    x.add_argument("--json", action="store_true")

    sp = add("display", "monitors: list | apply (auto-reverts unless confirmed) | confirm | revert | save-profile | auto")
    ds = sp.add_subparsers(dest="display_cmd", metavar="<subcommand>")
    ds.add_parser("list").add_argument("--json", action="store_true")
    x = ds.add_parser("apply")
    x.add_argument("monitor")
    x.add_argument("mode", help="e.g. 2560x1600@165.00Hz, or 'preferred'")
    x.add_argument("--position", default="auto")
    x.add_argument("--scale", type=float, default=1.0)
    x.add_argument("--confirm-within", type=int, default=15, help="seconds before it reverts (0 = keep without asking)")
    x.add_argument("--json", action="store_true")
    for name in ("confirm", "revert", "auto"):
        ds.add_parser(name).add_argument("--json", action="store_true")
    x = ds.add_parser("save-profile")
    x.add_argument("name")
    x.add_argument("--json", action="store_true")

    sp = add("autostart", "startup applications (XDG autostart): list | enable | disable | add | remove | run")
    au = sp.add_subparsers(dest="start_cmd", metavar="<subcommand>")
    au.add_parser("list").add_argument("--json", action="store_true")
    au.add_parser("run", help="start entries for this session (used at login)").add_argument("--json", action="store_true")
    for name in ("enable", "disable", "add", "remove"):
        x = au.add_parser(name)
        x.add_argument("id", help="desktop entry id, e.g. org.gnome.Software.desktop")
        x.add_argument("--json", action="store_true")

    sp = add("workspace", "workspaces: rules (write app→workspace rules) | save | restore (session)")
    ws = sp.add_subparsers(dest="ws_cmd", metavar="<subcommand>")
    ws.add_parser("rules").add_argument("--json", action="store_true")
    ws.add_parser("save", help="remember open apps and their workspaces").add_argument("--json", action="store_true")
    x = ws.add_parser("restore", help="reopen saved apps on their workspaces")
    x.add_argument("--dry-run", action="store_true")
    x.add_argument("--if-enabled", action="store_true", help="only when Settings → Workspaces → restore session is on (login)")
    x.add_argument("--json", action="store_true")

    sp = add("ai", "assistant: status | ask | actions | set-key | clear-key | history")
    ai = sp.add_subparsers(dest="ai_cmd", metavar="<subcommand>")
    x = ai.add_parser("status")
    x.add_argument("--probe", action="store_true", help="contact the provider and list models")
    x.add_argument("--json", action="store_true")
    x = ai.add_parser("ask", help="question as arguments, or {\"messages\": [...]} on stdin")
    x.add_argument("question", nargs="*")
    x.add_argument("--stream", action="store_true", help="JSON lines: delta… then final")
    ai.add_parser("actions").add_argument("--json", action="store_true")
    for name in ("set-key", "clear-key"):
        x = ai.add_parser(name, help="stored in the desktop keyring; read from stdin" if name == "set-key" else None)
        x.add_argument("--provider", default="openai")
        x.add_argument("--json", action="store_true")
    ai.add_parser("history").add_argument("--clear", action="store_true")
    x = ai.add_parser("log-action")
    x.add_argument("data")
    x.add_argument("--ran", action="store_true")

    sp = add("widget", "desktop widgets: list | inspect | install | remove")
    wd = sp.add_subparsers(dest="widget_cmd", metavar="<subcommand>")
    wd.add_parser("list").add_argument("--json", action="store_true")
    x = wd.add_parser("inspect")
    x.add_argument("path")
    x.add_argument("--json", action="store_true")
    x = wd.add_parser("install", help="a widget directory or .zip (validated; asks to confirm its permissions)")
    x.add_argument("path")
    x.add_argument("--force", action="store_true")
    x.add_argument("--yes", action="store_true")
    x.add_argument("--json", action="store_true")
    x = wd.add_parser("remove")
    x.add_argument("id")
    x.add_argument("--json", action="store_true")

    sp = add("logs", "recent AetherOS log lines (redacted); --audit for the action audit trail")
    sp.add_argument("--audit", action="store_true")
    sp.add_argument("--shell", action="store_true", help="also the aether-shell journal")
    sp.add_argument("--lines", type=int, default=60)

    sp = add("island", "post a message to the Dynamic Island from your own scripts")
    sp.add_argument("title")
    sp.add_argument("body", nargs="?")

    sp = add("reset-section", "reset one settings section to its defaults (snapshot first)")
    sp.add_argument("section")


HANDLERS = {
    "render": cmd_render, "themes": cmd_themes, "input": cmd_input, "display": cmd_display, "autostart": cmd_autostart,
    "workspace": cmd_workspace, "ai": cmd_ai, "widget": cmd_widget, "logs": cmd_logs, "island": cmd_island,
    "reset-section": cmd_config_reset_section,
}

DEFAULTS = {"start_cmd": None, "probe": False, "themes_cmd": None, "input_cmd": None, "display_cmd": None, "ws_cmd": None, "ai_cmd": None,
            "widget_cmd": None, "no_live": False, "if_enabled": False, "stream": False, "question": [], "clear": False,
            "audit": False, "shell": False, "ran": False}
