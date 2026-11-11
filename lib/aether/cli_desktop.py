"""CLI commands for the desktop layer: config, snapshots, profiles, palettes,
layouts, capabilities, system status, automation, idle, safe mode, recovery.

Kept apart from cli.py (hardware/graphics) so each file stays readable;
cli.py calls ``register`` and merges ``HANDLERS``.
"""

from __future__ import annotations

import json
import os
import sys
import time
from typing import Any, Dict, List, Optional

from . import appearance, automation, capabilities, config as config_mod, layouts, palettes, profiles, snapshots, sysinfo
from .graphics import hyprconf
from .util import Context, Output, config_dir, confirm, get_logger, state_dir


def _json(data: Any) -> int:
    sys.stdout.write(json.dumps(data, indent=2) + "\n")
    return 0


def _only(args) -> Optional[List[str]]:
    raw = getattr(args, "only", None)
    return [c.strip() for c in raw.split(",") if c.strip()] if raw else None


# -- safe mode ----------------------------------------------------------------

def safe_mode_flag() -> str:
    return os.path.join(config_dir(), "safe-mode")


def safe_mode_active(ctx: Context) -> bool:
    return ctx.env.get("AETHER_SAFE_MODE") == "1" or os.path.exists(safe_mode_flag())


def shader_cache_dir() -> str:
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.environ.get("HOME", ""), ".cache")
    return os.path.join(base, "aether-shell", "shaders")


def shader_status() -> Dict[str, Any]:
    """Whether locally compiled shaders exist for every shader source."""
    src = os.path.join(palettes.shell_dir(), "graphics", "shaders")
    try:
        sources = sorted(f for f in os.listdir(src) if f.endswith(".frag"))
    except OSError:
        sources = []
    cache = shader_cache_dir()
    built = [f for f in sources if os.path.isfile(os.path.join(cache, f + ".qsb"))
             and os.path.getmtime(os.path.join(cache, f + ".qsb")) >= os.path.getmtime(os.path.join(src, f))]
    bundled = [f for f in sources if os.path.isfile(os.path.join(src, f + ".qsb"))]
    return {"sources": len(sources), "local": len(built), "bundled": len(bundled),
            "dir": cache if sources and len(built) == len(sources) else None}


def cmd_capabilities(ctx: Context, args) -> int:
    data = capabilities.summary(ctx)
    data["safeMode"] = safe_mode_active(ctx)
    data["shaderDir"] = shader_status()["dir"]
    if data["safeMode"]:
        data["tier"], data["shaders"] = "eco", False
        data["reasons"].insert(0, "Safe mode is on (aether safe-mode off to leave it).")
    if args.json:
        return _json(data)
    out = Output()
    out.heading("Graphics capabilities")
    out.kv("Recommended quality", data["tier"])
    out.kv("Shader effects", "allowed" if data["shaders"] else "disabled")
    out.kv("Desktop GPU", data["desktopGpu"]["name"] if data["desktopGpu"] else "none detected")
    out.kv("Memory", "%s GiB" % data["memoryGiB"] if data["memoryGiB"] else "unknown")
    out.kv("Refresh rates", ", ".join("%g Hz" % r for r in data["refreshRates"]) or "unknown (no Hyprland session)")
    for r in data["reasons"]:
        out.bullet(r)
    return 0


def cmd_safe_mode(ctx: Context, args) -> int:
    out = Output()
    sub = args.safe_cmd or "status"
    flag = safe_mode_flag()
    if sub == "on":
        os.makedirs(os.path.dirname(flag), exist_ok=True)
        with open(flag, "w", encoding="utf-8") as fh:
            fh.write("enabled %s\n" % time.strftime("%Y-%m-%d %H:%M:%S"))
        get_logger().info("safe mode enabled")
        out.status("pass", "Safe mode on: no shaders, particles, parallax, video wallpaper or automation.")
        out.note("Restart the shell to apply: aether shell-reload")
    elif sub == "off":
        try:
            os.remove(flag)
        except FileNotFoundError:
            pass
        get_logger().info("safe mode disabled")
        out.status("pass", "Safe mode off.")
        out.note("Restart the shell to apply: aether shell-reload")
    else:
        if args.json:
            return _json({"active": safe_mode_active(ctx), "flag": os.path.exists(flag), "env": ctx.env.get("AETHER_SAFE_MODE") == "1"})
        out.kv("Safe mode", "ON" if safe_mode_active(ctx) else "off")
    return 0


# -- config -------------------------------------------------------------------

def cmd_config(ctx: Context, args) -> int:
    out = Output()
    sub = args.config_cmd or "validate"
    path = config_mod.config_file()
    data, err = config_mod.load()

    if sub == "validate":
        if data is None:
            if args.json:
                return _json({"ok": False, "problems": [err]}) or 1
            out.status("fail", str(err))
            out.note("Fix: aether config reset   (your current file is kept as a backup)")
            return 1
        _clean, problems = config_mod.validate(data)
        ver = config_mod.version_of(data) if data else config_mod.SCHEMA_VERSION
        if args.json:
            _json({"ok": not problems, "problems": problems, "version": ver, "current": config_mod.SCHEMA_VERSION})
            return 1 if problems else 0
        out.kv("File", path if data else path + " (not created yet — defaults apply)")
        out.kv("Schema version", "%d (current: %d)" % (ver, config_mod.SCHEMA_VERSION))
        if ver < config_mod.SCHEMA_VERSION:
            out.status("warn", "Older file: run `aether config migrate`.")
        for p in problems:
            out.status("warn", p)
        if not problems:
            out.status("pass", "config.json is valid")
        return 1 if problems else 0

    if sub == "migrate":
        if data is None:
            out.status("fail", str(err))
            return 1
        try:
            new, notes = config_mod.migrate(data)
        except ValueError as exc:
            out.status("fail", str(exc))
            return 1
        new, problems = config_mod.validate(new)
        if new == data:
            out.status("pass", "Already at schema version %d; nothing to do." % config_mod.SCHEMA_VERSION)
            return 0
        if args.dry_run:
            for n in notes + problems:
                out.bullet(n)
            out.note("Dry run: nothing written.")
            return 0
        snap = snapshots.create("pre-migrate")
        backup = config_mod.save(new)
        get_logger().info("config migrated to v%d", config_mod.SCHEMA_VERSION)
        out.status("pass", "Migrated to schema version %d" % config_mod.SCHEMA_VERSION)
        for n in notes + problems:
            out.bullet(n)
        if backup:
            out.note("Previous file: %s" % backup)
        if snap:
            out.note("Snapshot: %s" % snap)
        return 0

    if sub == "reset":
        if not confirm("Reset every shell setting to its default? (the current file is backed up)", args.yes):
            return 1
        snap = snapshots.create("pre-reset")
        if os.path.exists(path):
            keep = "%s.bak-%s" % (path, time.strftime("%Y%m%d-%H%M%S"))
            os.replace(path, keep)
            out.note("Previous file: %s" % keep)
        config_mod.save({"meta": {"schemaVersion": config_mod.SCHEMA_VERSION}}, backup=False)
        out.status("pass", "Settings reset to defaults.")
        if snap:
            out.note("Undo with: aether snapshot restore %s" % os.path.basename(snap)[:-7])
        return 0

    if sub == "export":
        if data is None:
            out.status("fail", str(err))
            return 1
        clean, _problems = config_mod.validate(data)
        with open(args.file, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(clean, fh, indent=2)
            fh.write("\n")
        out.status("pass", "Exported to %s" % args.file)
        return 0

    if sub == "import":
        raw, ierr = config_mod.load(args.file)
        if raw is None or not raw:
            out.status("fail", ierr or "%s is empty" % args.file)
            return 1
        try:
            raw, notes = config_mod.migrate(raw)
        except ValueError as exc:
            out.status("fail", str(exc))
            return 1
        clean, problems = config_mod.validate(raw)
        for p in problems:
            out.status("warn", p)
        if problems and not args.force:
            out.status("fail", "Not imported: the file has %d problem(s). Use --force to import the valid part." % len(problems))
            return 1
        if not confirm("Replace your shell settings with %s?" % args.file, args.yes):
            return 1
        snap = snapshots.create("pre-import")
        config_mod.save(clean)
        out.status("pass", "Imported %s" % args.file)
        if snap:
            out.note("Undo with: aether snapshot restore %s" % os.path.basename(snap)[:-7])
        return 0

    if sub in ("get", "set"):
        if "." not in args.key:
            sys.stderr.write("key must be section.name, e.g. appearance.palette\n")
            return 2
        section, key = args.key.split(".", 1)
        if section not in config_mod.SCHEMA or key not in config_mod.SCHEMA[section]:
            sys.stderr.write("unknown setting %s\n" % args.key)
            return 2
        if sub == "get":
            cur = (data or {}).get(section, {}).get(key, config_mod.SCHEMA[section][key]["default"])
            sys.stdout.write(json.dumps(cur) + "\n")
            return 0
        try:
            value = json.loads(args.value)
        except ValueError:
            value = args.value  # bare words are text
        ok, problems = config_mod.set_keys({section: {key: value}})
        if not ok:
            for p in problems:
                out.status("fail", p)
            return 1
        out.status("pass", "%s = %s" % (args.key, json.dumps(value)))
        return 0
    return 2


# -- snapshots ----------------------------------------------------------------

def cmd_snapshot(ctx: Context, args) -> int:
    out = Output()
    sub = args.snap_cmd or "list"
    if sub == "create":
        try:
            path = snapshots.create(args.label, _only(args))
        except ValueError as exc:
            out.status("fail", str(exc))
            return 2
        if args.json:
            return _json({"path": path})
        if path is None:
            out.status("warn", "Nothing to snapshot yet (no AetherOS settings exist).")
            return 0
        out.status("pass", "Snapshot: %s" % path)
        return 0
    if sub == "mark-good":
        path = snapshots.create(snapshots.LKG)
        if args.json:
            return _json({"path": path})
        out.status("pass", "Last-known-good configuration recorded." if path else "Nothing to record yet.")
        return 0
    if sub == "list":
        snaps = snapshots.listing()
        if args.json:
            return _json(snaps)
        out.heading("Snapshots (%s)" % snapshots.snapshot_dir())
        if not snaps:
            out.note("None yet. Create one with: aether snapshot create")
        for s in snaps:
            out.bullet("%-36s %s  %d file(s)%s%s" % (s["name"], s["created"] or "?", s["files"],
                                                    "  [last-known-good]" if s["lastKnownGood"] else "",
                                                    "" if s["valid"] else "  [INVALID]"))
        return 0
    path = snapshots.resolve(args.name)
    if path is None:
        out.status("fail", "No snapshot named %r (see: aether snapshot list)" % args.name)
        return 1
    if sub == "verify":
        ok, problems = snapshots.verify(path)
        if args.json:
            _json({"ok": ok, "problems": problems})
            return 0 if ok else 1
        for p in problems:
            out.status("fail", p)
        if ok:
            out.status("pass", "%s is intact" % os.path.basename(path))
        return 0 if ok else 1
    if sub == "preview":
        prev = snapshots.preview(path, _only(args))
        if args.json:
            return _json(prev)
        for p in prev["problems"]:
            out.status("fail", p)
        if not prev["changes"]:
            out.status("pass", "Restoring this snapshot would change nothing.")
        for c in prev["changes"]:
            out.heading("%s  %s" % (c["change"], c["path"]))
            out.write(c["diff"].rstrip() or "(no textual difference)")
        return 0 if prev["valid"] else 1
    if sub == "restore":
        prev = snapshots.preview(path, _only(args))
        if not prev["valid"]:
            for p in prev["problems"]:
                out.status("fail", p)
            return 1
        if not prev["changes"]:
            out.status("pass", "Already identical to this snapshot.")
            return 0
        out.write("Files that will change: %s" % ", ".join(c["path"] for c in prev["changes"]))
        if not confirm("Restore %s?" % os.path.basename(path), args.yes):
            return 1
        res = snapshots.restore(path, _only(args))
        if args.json:
            _json(res)
            return 0 if res["ok"] else 1
        if not res["ok"]:
            for p in res["problems"]:
                out.status("fail", p)
            return 1
        get_logger().info("snapshot %s restored", path)
        out.status("pass", "Restored %d file(s)." % len(res["restored"]))
        if res.get("undo"):
            out.note("Undo with: aether snapshot restore %s" % os.path.basename(res["undo"])[:-7])
        return 0
    return 2


# -- profiles -----------------------------------------------------------------

def cmd_profile(ctx: Context, args) -> int:
    out = Output()
    sub = args.profile_cmd or "list"
    if sub == "list":
        items = profiles.listing()
        if args.json:
            return _json(items)
        out.heading("Desktop profiles")
        for p in items:
            out.bullet("%-14s %s%s" % (p["name"], p["summary"] or p["label"], "" if p["builtin"] else "  (yours)"))
        out.note("Apply with: aether profile apply <name>")
        return 0
    if sub == "show":
        prof, err = profiles.get(args.name)
        if prof is None:
            out.status("fail", err)
            return 1
        return _json(prof)
    if sub == "apply":
        res = profiles.apply(args.name, dry_run=args.dry_run)
        if res["ok"] and not args.dry_run and res.get("hyprland") and not args.no_hyprland:
            from . import performance
            from .hw import system
            from .util import parse_version, version_at_least
            ver = parse_version(system.hyprland_version(ctx))
            text = performance.render_hypr_profile(res["hyprland"], bool(ver and version_at_least(ver, (0, 53))))
            hyprconf.write_fragment(hyprconf.profile_conf_path(), text)
        if args.json:
            _json(res)
            return 0 if res["ok"] else 1
        if not res["ok"]:
            out.status("fail", res["error"])
            return 1
        if args.dry_run:
            out.write(json.dumps(res["config"], indent=2))
            out.note("Hyprland profile: %s. Dry run: nothing written." % res["hyprland"])
            return 0
        get_logger().info("profile %s applied", args.name)
        out.status("pass", "Profile '%s' applied (the running shell picks it up immediately)." % args.name)
        if res.get("undo"):
            out.note("Undo with: aether snapshot restore %s" % os.path.basename(res["undo"])[:-7])
        return 0
    if sub == "save":
        res = profiles.save_current(args.name, args.label or "")
    elif sub == "import":
        res = profiles.import_file(args.file, args.name)
    elif sub == "export":
        prof, err = profiles.get(args.name)
        if prof is None:
            out.status("fail", err)
            return 1
        with open(args.file, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(dict(prof, aetherProfile=1), fh, indent=2)
            fh.write("\n")
        res = {"ok": True, "path": args.file}
    else:
        return 2
    if args.json:
        _json(res)
        return 0 if res["ok"] else 1
    out.status("pass" if res["ok"] else "fail", res.get("path") or res.get("error") or "")
    return 0 if res["ok"] else 1


# -- palettes / terminals -----------------------------------------------------

def _shell_theme_state() -> Dict[str, Any]:
    data, _err = config_mod.load()
    app = dict(config_mod.defaults()["appearance"])
    clean, _p = config_mod.validate({"appearance": (data or {}).get("appearance", {})})
    app.update(clean.get("appearance", {}))
    return app


def cmd_theme_extra(ctx: Context, args) -> Optional[int]:
    """Handles the palette-related `theme` subcommands; returns None for the
    ones cli.py already implements."""
    sub = getattr(args, "theme_cmd", None)
    out = Output()
    if sub == "palettes":
        table = palettes.load()
        if args.json:
            return _json([{"id": k, "label": v["label"], "dark": v["dark"], "accent": v["accent"], "bg": v["bg0"]}
                          for k, v in table.items() if k != "aether-light"])
        for k in palettes.ids():
            out.bullet("%-18s %s" % (k, table[k]["label"]))
        return 0
    if sub == "terminals":
        terms = palettes.detect_terminals(ctx)
        if args.json:
            return _json(terms)
        for t in terms:
            out.bullet("%-16s %s%s" % (t["name"], "installed" if t["installed"] else "not installed",
                                       ", themed by AetherOS" if t["themed"] and t["installed"] else ""))
        return 0
    if sub == "icons":
        if args.set:
            res = appearance.set_icons(ctx, args.set)
            if args.json:
                return _json(res) if res["ok"] else (_json(res) or 1)
            out.status("pass" if res["ok"] else "fail", ", ".join(res.get("applied", [])) or res.get("error", ""))
            return 0 if res["ok"] else 1
        data = appearance.themes(ctx)
        if args.json:
            return _json(data)
        for t in data["icons"]:
            out.bullet("%-28s %s%s" % (t["id"], t["name"], "  (current)" if t["id"] == data["current"]["icons"] else ""))
        return 0
    if sub == "cursor":
        if args.set:
            res = appearance.set_cursor(ctx, args.set, args.size)
            if args.json:
                return _json(res) if res["ok"] else (_json(res) or 1)
            out.status("pass" if res["ok"] else "fail", ", ".join(res.get("applied", [])) or res.get("error", ""))
            return 0 if res["ok"] else 1
        data = appearance.themes(ctx)
        if args.json:
            return _json(data)
        for t in data["cursors"]:
            out.bullet("%-28s %s%s" % (t["id"], t["name"], "  (current)" if t["id"] == data["current"]["cursor"] else ""))
        return 0
    if sub in ("palette", "apply"):
        app = _shell_theme_state()
        pid = app["palette"]
        if sub == "palette":
            pid = args.id
            ok, problems = config_mod.set_keys({"appearance": {"palette": pid}})
            if not ok:
                out.status("fail", "; ".join(problems))
                return 1
        dark = getattr(args, "mode", None) != "light" if getattr(args, "mode", None) else app["theme"] != "light"
        res = palettes.apply(ctx, pid, app["accent"], dark)
        if args.json:
            return _json(res)
        out.status("pass", "%s applied to terminal and Hyprland theme files" % res["label"])
        for w in res["written"]:
            out.bullet("wrote " + w)
        if res["reloaded"]:
            out.note("Reloaded: " + ", ".join(res["reloaded"]))
        return 0
    return None


# -- layouts ------------------------------------------------------------------

def cmd_layout(ctx: Context, args) -> int:
    out = Output()
    sub = args.layout_cmd or "list"
    if sub == "list":
        items = layouts.listing()
        if args.json:
            return _json(items)
        out.heading("Window layouts")
        for it in items:
            out.bullet("%-14s %s  [%s]" % (it["name"], it["summary"], ", ".join(s["role"] for s in it["slots"])))
        return 0
    if sub == "preview":
        res = layouts.plan(ctx, args.name, args.monitor)
    elif sub == "apply":
        res = layouts.apply(ctx, args.name, args.monitor, launch=not args.no_launch)
    elif sub == "undo":
        res = layouts.undo(ctx)
    elif sub == "save":
        res = layouts.save_current(ctx, args.name, args.label or "")
    else:
        return 2
    if args.json:
        _json(res)
        return 0 if res.get("ok") else 1
    if not res.get("ok") and res.get("error"):
        out.status("fail", res["error"])
        return 1
    if sub == "preview":
        out.heading("%s on %s (workspace %s)" % (res["label"], res["monitor"], res["workspace"]))
        for s in res["slots"]:
            what = ("skip — " + s["skip"]) if s["skip"] else ("move " + (s["window"]["class"] or "?")) if s["window"] else ("launch " + s["launch"][0])
            out.bullet("%-9s %4d,%-4d %4dx%-4d  %s" % (s["role"], s["x"], s["y"], s["w"], s["h"], what))
    elif sub == "apply":
        out.status("pass" if res["ok"] else "warn", "Placed: %s" % (", ".join(res["placed"]) or "nothing"))
        for s in res["skipped"]:
            out.status("warn", s)
        for e in res["errors"]:
            out.status("fail", e)
        out.note("Undo with: aether layout undo")
    elif sub == "undo":
        out.status("pass", "Restored %d window(s)." % res["restored"])
    else:
        out.status("pass", "Saved layout '%s' (%d slot(s))." % (res["name"], res["slots"]))
    return 0 if res.get("ok") else 1


# -- system status ------------------------------------------------------------

def cmd_updates(ctx: Context, args) -> int:
    data = sysinfo.updates(ctx)
    if args.json:
        return _json(data)
    out = Output()
    if not data["available"]:
        out.status("warn", data["reason"])
        return 1
    out.heading("Fedora updates")
    out.kv("Available", data["count"])
    out.kv("Reboot required", {True: "yes", False: "no", None: "unknown"}[data["rebootRequired"]])
    for p in data["packages"][:40]:
        out.bullet("%-40s %-28s %s" % (p["name"], p["version"], p["repo"]))
    if data["count"]:
        out.note("Install with: " + " ".join(data["command"]))
    return 0


def cmd_security(ctx: Context, args) -> int:
    data = sysinfo.security(ctx)
    if args.json:
        return _json(data)
    out = Output()
    out.heading("Security & privacy")
    for it in data["items"]:
        out.status(it["level"] if it["level"] in ("pass", "warn", "fail") else "info", "%-22s %s%s" % (it["label"], it["value"], ("  — " + it["detail"]) if it["detail"] else ""))
    return 0


def cmd_services(ctx: Context, args) -> int:
    sub = args.svc_cmd or "list"
    out = Output()
    if sub == "list":
        data = sysinfo.services(ctx)
        if args.json:
            return _json(data)
        if not data["available"]:
            out.status("warn", data["reason"])
            return 1
        for u in data["units"]:
            if u["aether"] or u["active"] in ("active", "failed"):
                out.status("fail" if u["active"] == "failed" else "pass", "%-44s %s/%s" % (u["unit"], u["active"], u["sub"]))
        return 0
    if sub == "log":
        res = sysinfo.service_log(ctx, args.unit, args.lines)
        if args.json:
            return _json(res)
        sys.stdout.write(res["log"] if res["ok"] else (res["error"] or "") + "\n")
        return 0 if res["ok"] else 1
    res = sysinfo.service_action(ctx, sub, args.unit)
    if args.json:
        _json(res)
        return 0 if res["ok"] else 1
    out.status("pass" if res["ok"] else "fail", "%s %s%s" % (sub, args.unit, "" if res["ok"] else ": " + str(res["error"])))
    return 0 if res["ok"] else 1


# -- automation ---------------------------------------------------------------

def cmd_automation(ctx: Context, args) -> int:
    out = Output()
    sub = args.auto_cmd or "list"
    data, err = config_mod.load()
    current = ((data or {}).get("automation") or {}).get("rules", [])
    if sub == "list":
        good, problems = automation.validate_rules(current)
        if args.json:
            return _json({"rules": good, "problems": problems, "conflicts": automation.find_conflicts(good)})
        for r in good:
            out.bullet("%-12s %s  %s → %s%s" % (r["id"], "on " if r["enabled"] else "off", r["trigger"]["type"], ", ".join(a["type"] for a in r["actions"]),
                                               ("  (%s)" % r["name"]) if r["name"] else ""))
        for c in automation.find_conflicts(good):
            out.status("warn", c)
        if not good:
            out.note("No rules. Create them in Settings → Automation.")
        return 0
    if sub == "validate":
        if args.file:
            try:
                with open(args.file, "r", encoding="utf-8") as fh:
                    raw = json.load(fh)
            except (OSError, ValueError) as exc:
                out.status("fail", str(exc))
                return 1
            current = raw.get("rules", raw) if isinstance(raw, dict) else raw
        good, problems = automation.validate_rules(current)
        conflicts = automation.find_conflicts(good)
        if args.json:
            _json({"ok": not problems, "valid": len(good), "problems": problems, "conflicts": conflicts})
            return 1 if problems else 0
        for p in problems:
            out.status("fail", p)
        for c in conflicts:
            out.status("warn", c)
        out.status("pass" if not problems else "warn", "%d valid rule(s)" % len(good))
        return 1 if problems else 0
    if sub == "export":
        good, _p = automation.validate_rules(current)
        with open(args.file, "w", encoding="utf-8", newline="\n") as fh:
            json.dump({"aetherAutomation": 1, "rules": good}, fh, indent=2)
            fh.write("\n")
        out.status("pass", "Exported %d rule(s) to %s" % (len(good), args.file))
        return 0
    if sub == "import":
        try:
            if os.path.getsize(args.file) > 256 * 1024:
                raise ValueError("file is too large to be a rules file")
            with open(args.file, "r", encoding="utf-8") as fh:
                raw = json.load(fh)
        except (OSError, ValueError) as exc:
            out.status("fail", str(exc))
            return 1
        incoming = raw.get("rules", []) if isinstance(raw, dict) else raw
        good, problems = automation.validate_rules(incoming)
        if problems:
            for p in problems:
                out.status("fail", p)
            out.status("fail", "Nothing imported: every rule in the file must be valid.")
            return 1
        # Imported rules arrive disabled: the user turns on what they've read.
        for r in good:
            r["enabled"] = False
        have = {r.get("id") for r in current if isinstance(r, dict)}
        merged = list(current) + [r for r in good if r["id"] not in have]
        ok, errs = config_mod.set_keys({"automation": {"rules": merged}})
        if not ok:
            for e in errs:
                out.status("fail", e)
            return 1
        out.status("pass", "Imported %d rule(s), all disabled. Review and enable them in Settings → Automation." % (len(merged) - len(current)))
        return 0
    return 2


# -- idle / recovery ----------------------------------------------------------

def cmd_idle(ctx: Context, args) -> int:
    out = Output()
    data, _err = config_mod.load()
    lock = dict(config_mod.defaults()["lock"])
    clean, _p = config_mod.validate({"lock": (data or {}).get("lock", {})})
    lock.update(clean.get("lock", {}))
    pw = dict(config_mod.defaults()["power"])
    pclean, _p = config_mod.validate({"power": (data or {}).get("power", {})})
    pw.update(pclean.get("power", {}))
    text = hyprconf.generate_idle_conf(lock["idleLockMinutes"], lock["idleDisplayOffMinutes"], lock["idleSuspendMinutes"], pw["dimAfterMinutes"])
    if args.dry_run or (args.idle_cmd or "apply") == "show":
        sys.stdout.write(text)
        return 0
    path = hyprconf.idle_conf_path()
    hyprconf.write_fragment(path, text)
    restarted = False
    if ctx.is_live and ctx.which("systemctl"):
        restarted = ctx.run(["systemctl", "--user", "try-restart", "aether-idle.service"], timeout=10).ok
    if args.json:
        return _json({"path": path, "restarted": restarted, "hypridle": ctx.which("hypridle") is not None})
    out.status("pass", "Wrote %s" % path)
    if not ctx.which("hypridle"):
        out.status("warn", "hypridle is not installed: idle locking is inactive (sudo dnf install hypridle).")
    return 0


def cmd_recover(ctx: Context, args) -> int:
    """One command for 'my desktop is broken'. Every step is reversible."""
    out = Output()
    out.heading("AetherOS recovery")
    steps: List[str] = []
    flag = safe_mode_flag()
    os.makedirs(os.path.dirname(flag), exist_ok=True)
    with open(flag, "w", encoding="utf-8") as fh:
        fh.write("enabled by `aether recover` %s\n" % time.strftime("%Y-%m-%d %H:%M:%S"))
    steps.append("Safe mode enabled (effects, video wallpaper and automation off).")

    try:
        from . import widgets as widgets_mod
        w = widgets_mod.disable_third_party()
        if w["removed"]:
            steps.append("Third-party widgets disabled (%d removed from the desktop)." % w["removed"])
    except (OSError, ValueError) as exc:
        steps.append("Couldn't change widget settings: %s" % exc)

    created = hyprconf.ensure_defaults()
    if created:
        steps.append("Recreated missing Hyprland fragment(s): %s" % ", ".join(os.path.basename(c) for c in created))

    data, err = config_mod.load()
    lkg = snapshots.resolve(snapshots.LKG)
    if data is None:
        steps.append("config.json is unreadable: %s" % err)
        if lkg and confirm("Restore the last-known-good configuration?", args.yes):
            res = snapshots.restore(lkg)
            steps.append("Last-known-good configuration restored." if res["ok"] else "Restore failed: %s" % "; ".join(res["problems"]))
        else:
            path = config_mod.config_file()
            keep = "%s.broken-%s" % (path, time.strftime("%Y%m%d-%H%M%S"))
            os.replace(path, keep)
            steps.append("Moved the unreadable file to %s; defaults apply." % keep)
    else:
        _clean, problems = config_mod.validate(data)
        if problems:
            steps.append("config.json has %d invalid value(s); the shell ignores them (aether config validate)." % len(problems))
        if lkg and args.restore and confirm("Restore the last-known-good configuration?", args.yes):
            res = snapshots.restore(lkg)
            steps.append("Last-known-good configuration restored." if res["ok"] else "Restore failed: %s" % "; ".join(res["problems"]))

    if ctx.is_live and ctx.which("systemctl"):
        ctx.run(["systemctl", "--user", "reset-failed", "aether-shell.service"], timeout=10)
        if ctx.env.get("WAYLAND_DISPLAY") and ctx.run(["systemctl", "--user", "restart", "aether-shell.service"], timeout=20).ok:
            steps.append("Shell restarted.")
    get_logger().info("recover: %s", " | ".join(steps))
    for s in steps:
        out.bullet(s)
    out.write()
    out.write("  Still broken?")
    out.write("    Hyprland won't start:   Hyprland -c ~/.config/hypr/recovery.conf   (from a TTY: Ctrl+Alt+F3)")
    out.write("    Undo the installation:  ./install.sh --rollback")
    out.write("    Full report:            aether diagnostics")
    out.write("  When things work again:   aether safe-mode off && aether shell-reload")
    return 0


# -- parser -------------------------------------------------------------------

def register(sub, add, theme_sub) -> None:
    add("capabilities", "what visual quality this machine is comfortable with (never wakes a sleeping GPU)")

    sp = add("safe-mode", "start the shell with every optional effect disabled")
    sm = sp.add_subparsers(dest="safe_cmd", metavar="[on|off|status]")
    sm.add_parser("on")
    sm.add_parser("off")
    sm.add_parser("status").add_argument("--json", action="store_true")

    sp = add("recover", "fix a broken desktop: safe mode, repair fragments, optional last-known-good restore")
    sp.add_argument("--restore", action="store_true", help="also offer to restore the last-known-good configuration")
    sp.add_argument("--yes", action="store_true")

    sp = add("config", "shell settings file: validate | migrate | reset | export | import | get | set")
    cs = sp.add_subparsers(dest="config_cmd", metavar="<subcommand>")
    cs.add_parser("validate", help="check config.json against the schema").add_argument("--json", action="store_true")
    x = cs.add_parser("migrate", help="upgrade an older config.json")
    x.add_argument("--dry-run", action="store_true")
    x = cs.add_parser("reset", help="back up and reset all settings")
    x.add_argument("--yes", action="store_true")
    cs.add_parser("export", help="write a validated copy").add_argument("file")
    x = cs.add_parser("import", help="replace settings from a file (validated; nothing in it is executed)")
    x.add_argument("file")
    x.add_argument("--force", action="store_true", help="import the valid part of a file with problems")
    x.add_argument("--yes", action="store_true")
    cs.add_parser("get", help="print one setting").add_argument("key")
    x = cs.add_parser("set", help="change one setting (validated)")
    x.add_argument("key")
    x.add_argument("value")

    sp = add("snapshot", "configuration snapshots: create | list | verify | preview | restore | mark-good")
    ss = sp.add_subparsers(dest="snap_cmd", metavar="<subcommand>")
    x = ss.add_parser("create", help="snapshot the current settings")
    x.add_argument("--label", default="manual")
    x.add_argument("--only", help="comma-separated components: " + ", ".join(snapshots.COMPONENTS))
    x.add_argument("--json", action="store_true")
    ss.add_parser("list").add_argument("--json", action="store_true")
    ss.add_parser("mark-good", help="record the current settings as last-known-good").add_argument("--json", action="store_true")
    for name in ("verify", "preview", "restore"):
        x = ss.add_parser(name)
        x.add_argument("name", help="snapshot name, path, 'latest' or 'last-known-good'")
        x.add_argument("--json", action="store_true")
        if name != "verify":
            x.add_argument("--only", help="restore only these components")
        if name == "restore":
            x.add_argument("--yes", action="store_true")

    sp = add("profile", "desktop profiles: list | show | apply | save | import | export")
    ps = sp.add_subparsers(dest="profile_cmd", metavar="<subcommand>")
    ps.add_parser("list").add_argument("--json", action="store_true")
    ps.add_parser("show").add_argument("name")
    x = ps.add_parser("apply")
    x.add_argument("name")
    x.add_argument("--dry-run", action="store_true")
    x.add_argument("--no-hyprland", action="store_true", help="don't change the compositor profile")
    x.add_argument("--json", action="store_true")
    x = ps.add_parser("save", help="save the current look as a profile")
    x.add_argument("name")
    x.add_argument("--label")
    x.add_argument("--json", action="store_true")
    x = ps.add_parser("import")
    x.add_argument("file")
    x.add_argument("name")
    x.add_argument("--json", action="store_true")
    x = ps.add_parser("export")
    x.add_argument("name")
    x.add_argument("file")
    x.add_argument("--json", action="store_true")

    theme_sub.add_parser("palettes", help="list colour palettes").add_argument("--json", action="store_true")
    theme_sub.add_parser("terminals", help="list detected terminals").add_argument("--json", action="store_true")
    x = theme_sub.add_parser("palette", help="select a palette and theme terminals/Hyprland to match")
    x.add_argument("id", choices=palettes.ids())
    x.add_argument("--json", action="store_true")
    for name, what in (("icons", "icon theme"), ("cursor", "cursor theme")):
        x = theme_sub.add_parser(name, help="list installed %ss, or --set one" % what)
        x.add_argument("--set", metavar="THEME")
        x.add_argument("--json", action="store_true")
        if name == "cursor":
            x.add_argument("--size", type=int, default=24)
    x = theme_sub.add_parser("apply", help="re-write terminal/Hyprland theme files for the current palette")
    x.add_argument("--mode", choices=("dark", "light"))
    x.add_argument("--json", action="store_true")

    sp = add("layout", "window layouts: list | preview | apply | undo | save")
    ls = sp.add_subparsers(dest="layout_cmd", metavar="<subcommand>")
    ls.add_parser("list").add_argument("--json", action="store_true")
    for name in ("preview", "apply"):
        x = ls.add_parser(name)
        x.add_argument("name")
        x.add_argument("--monitor")
        x.add_argument("--json", action="store_true")
        if name == "apply":
            x.add_argument("--no-launch", action="store_true", help="only arrange windows that are already open")
    ls.add_parser("undo").add_argument("--json", action="store_true")
    x = ls.add_parser("save", help="save the focused workspace's arrangement")
    x.add_argument("name")
    x.add_argument("--label")
    x.add_argument("--json", action="store_true")

    add("updates", "list available Fedora updates (installs nothing)")
    add("security", "SELinux, firewall, Secure Boot and disk-encryption status (read-only)")
    sp = add("services", "systemd user services: list | start | stop | restart | log")
    vs = sp.add_subparsers(dest="svc_cmd", metavar="<subcommand>")
    vs.add_parser("list").add_argument("--json", action="store_true")
    for name in ("start", "stop", "restart", "log"):
        x = vs.add_parser(name)
        x.add_argument("unit")
        x.add_argument("--json", action="store_true")
        if name == "log":
            x.add_argument("--lines", type=int, default=40)

    sp = add("automation", "automation rules: list | validate | import | export")
    au = sp.add_subparsers(dest="auto_cmd", metavar="<subcommand>")
    au.add_parser("list").add_argument("--json", action="store_true")
    x = au.add_parser("validate")
    x.add_argument("file", nargs="?")
    x.add_argument("--json", action="store_true")
    au.add_parser("import").add_argument("file")
    au.add_parser("export").add_argument("file")

    sp = add("idle", "idle locking: write hypridle settings from the lock-screen configuration")
    sp.add_argument("--dry-run", action="store_true")
    im = sp.add_subparsers(dest="idle_cmd", metavar="[apply|show]")
    im.add_parser("apply")
    im.add_parser("show")


HANDLERS = {
    "capabilities": cmd_capabilities, "safe-mode": cmd_safe_mode, "recover": cmd_recover, "config": cmd_config,
    "snapshot": cmd_snapshot, "profile": cmd_profile, "layout": cmd_layout, "updates": cmd_updates,
    "security": cmd_security, "services": cmd_services, "automation": cmd_automation, "idle": cmd_idle,
}

DEFAULTS = {"safe_cmd": None, "config_cmd": None, "snap_cmd": None, "profile_cmd": None, "layout_cmd": None,
            "svc_cmd": None, "auto_cmd": None, "idle_cmd": None, "dry_run": False, "yes": False, "only": None,
            "monitor": None, "label": None, "restore": False, "force": False, "no_launch": False, "no_hyprland": False}
