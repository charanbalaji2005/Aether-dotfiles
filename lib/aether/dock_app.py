"""AetherOS dock — a macOS-style dock for the classic interface (looks "home" and "desk").

A layer-shell surface along the bottom edge (namespace "aether-dock") drawn
with cairo:

* pinned apps from ~/.config/aether-shell/classic/dock.json (aether-dock add/remove/move);
* a dot under every app that has a window, brighter for the focused one;
* apps that are running but not pinned appear after a divider, so the dock
  grows and shrinks as windows open and close;
* magnification under the pointer and the app's name above it;
* auto-hide: "auto" hides it until the pointer touches the bottom edge,
  "smart" hides it only while a window overlaps it, "off" keeps it shown and
  reserves its space (aether-dock autohide auto|smart|off);
* SIGUSR1 makes it rise for a moment (aether-lock does this after unlocking);
* click: bring the app's most recent window forward, switching to its workspace
  (again: cycle its windows); launch it with a bounce only if it has no window;
  middle-click: new window; right-click: windows, New Window, Keep in Dock, Quit.

Window state comes from Hyprland's IPC sockets (no polling of hyprctl);
dock.json is watched, so aether-dock changes apply at once.
"""

from __future__ import annotations

import configparser
import math
import os
import signal
import socket
import subprocess
import sys
import time

import cairo
import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, Pango, PangoCairo  # noqa: E402

from aether import classic_colors as cc  # noqa: E402
from aether import dock as dockcfg  # noqa: E402

try:
    gi.require_version("GtkLayerShell", "0.1")
    from gi.repository import GtkLayerShell  # noqa: E402
except (ValueError, ImportError):
    GtkLayerShell = None

IGNORE_CLASSES = {"aether-dropterm", "aether-settings", ""}
HYPR_EVENTS = (b"openwindow", b"closewindow", b"activewindowv2", b"movewindowv2", b"workspacev2",
               b"focusedmonv2", b"changefloatingmode", b"fullscreen", b"windowtitlev2")
MARGIN = 8          # gap between the dock and the screen edge
PAD_V = 9           # space above the icons inside the dock
PAD_BOTTOM = 13     # space under the icons (the running dots live here)
EDGE = 2            # height of the reveal strip while hidden


# ── Hyprland IPC ─────────────────────────────────────────────────────────
# Shared with aether-dock (Lua-aware dispatch for Hyprland 0.57+).
hypr, hypr_json, hypr_path = dockcfg.hypr, dockcfg.hypr_json, dockcfg.hypr_path


# ── apps ─────────────────────────────────────────────────────────────────
class AppIndex:
    """Desktop entries, and which one a window class belongs to."""

    def __init__(self) -> None:
        self.entries: dict[str, dict] = {}
        keys: dict[str, str] = {}
        weak: dict[str, str] = {}
        for d in dockcfg.data_dirs():
            appdir = d / "applications"
            if not appdir.is_dir():
                continue
            for f in sorted(appdir.glob("*.desktop")):
                if f.stem in self.entries:
                    continue
                e = self.read(f)
                if not e:
                    continue
                self.entries[f.stem] = e
                for k in (f.stem.lower(), f.stem.split(".")[-1].lower()):
                    keys.setdefault(k, f.stem)
                if e["wmclass"]:
                    keys.setdefault(e["wmclass"].lower(), f.stem)
                if e["exec"]:
                    weak.setdefault(e["exec"].lower(), f.stem)
        for k, v in weak.items():
            keys.setdefault(k, v)
        self.keys = keys

    @staticmethod
    def read(path) -> dict | None:
        cp = configparser.ConfigParser(interpolation=None, strict=False)
        cp.optionxform = str
        try:
            cp.read(path, encoding="utf-8")
            e = cp["Desktop Entry"]
        except (configparser.Error, KeyError, UnicodeDecodeError):
            return None
        if e.get("Type", "Application") != "Application":
            return None
        exe = (e.get("Exec", "").split() or [""])[0]
        if exe in ("env", "/usr/bin/env", "flatpak"):
            exe = ""
        return {"name": e.get("Name", path.stem), "icon": e.get("Icon", ""),
                "wmclass": e.get("StartupWMClass", ""), "exec": os.path.basename(exe),
                "hidden": e.get("NoDisplay", "false").lower() == "true"}

    def match(self, cls: str) -> str | None:
        low = cls.lower()
        return self.keys.get(low) or self.keys.get(low.split(".")[-1])


class Item:
    def __init__(self, key: str, kind: str, name: str = "", icon: str = "", app_id: str | None = None,
                 pinned: bool = False) -> None:
        self.key, self.kind, self.name, self.icon, self.app_id, self.pinned = key, kind, name, icon, app_id, pinned
        self.windows: list[dict] = []
        self.presence = 1.0
        self.target = 1.0
        self.bounce_until = 0.0
        self.bounce_start = 0.0
        # Set while drawing: hit box and current scale.
        self.x0 = self.x1 = 0.0
        self.scale = 1.0


# ── the dock ─────────────────────────────────────────────────────────────
class Dock(Gtk.Window):
    def __init__(self) -> None:
        super().__init__(title="Dock")
        self.set_wmclass("aether-dock", "AetherOS Dock")
        screen = self.get_screen()
        if screen.get_rgba_visual():
            self.set_visual(screen.get_rgba_visual())
        self.set_app_paintable(True)
        self.set_decorated(False)
        self.layer = bool(GtkLayerShell and GtkLayerShell.is_supported())
        if self.layer:
            GtkLayerShell.init_for_window(self)
            GtkLayerShell.set_namespace(self, "aether-dock")
            GtkLayerShell.set_layer(self, GtkLayerShell.Layer.TOP)
            for edge in (GtkLayerShell.Edge.BOTTOM, GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT):
                GtkLayerShell.set_anchor(self, edge, True)
            GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.NONE)

        self.index = AppIndex()
        self.theme = Gtk.IconTheme.get_default()
        self.pix: dict[tuple[str, int], GdkPixbuf.Pixbuf | None] = {}
        self.items: list[Item] = []
        self.running_order: list[str] = []
        self.active_addr = ""
        self.hover_x: float | None = None
        self.hover_amt = 0.0
        self.pointer_in = False
        self.menu_open = False
        self.hide = 0.0             # 0 shown … 1 hidden
        self.want_shown = True
        self.overlapped = False
        self.region_key = None
        self.ticking = False
        self.hide_timer = 0
        self.refresh_pending = 0
        self.startup_until = time.monotonic() + 1.5

        self.load_config()
        self.area = Gtk.DrawingArea()
        self.area.add_events(Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.BUTTON_PRESS_MASK
                             | Gdk.EventMask.BUTTON_RELEASE_MASK | Gdk.EventMask.ENTER_NOTIFY_MASK
                             | Gdk.EventMask.LEAVE_NOTIFY_MASK)
        self.area.connect("draw", self.on_draw)
        self.area.connect("motion-notify-event", self.on_motion)
        self.area.connect("enter-notify-event", self.on_enter)
        self.area.connect("leave-notify-event", self.on_leave)
        self.area.connect("button-release-event", self.on_click)
        self.add(self.area)
        self.connect("size-allocate", lambda *_a: self.update_region())

        mon = Gio.File.new_for_path(str(dockcfg.state_path())).monitor_file(Gio.FileMonitorFlags.NONE, None)
        mon.connect("changed", lambda *_a: GLib.timeout_add(120, self.reload_config))
        self._monitor = mon
        self.connect_events()
        self.refresh()
        GLib.timeout_add(700, self.periodic)
        GLib.timeout_add(1600, lambda: (self.update_visibility(), False)[1])
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGUSR1, self.peek)
        self.start_tick()

    # ── configuration ───────────────────────────────────────────────────
    def load_config(self) -> None:
        st = dockcfg.load_state()
        self.pins = list(st["pins"])
        self.size = max(24, min(96, int(st.get("size", 44))))
        try:
            self.magnify = max(1.0, min(2.0, float(st.get("magnify", 1.5))))
        except (TypeError, ValueError):
            self.magnify = 1.5
        mode = st.get("autohide", "auto")
        self.mode = mode if mode in ("auto", "smart", "off") else "auto"
        pal = dict(cc.resolve_palette(cc.read_state())[0])
        self.bg_rgb = self.rgb(pal.get("background", "#101010"))
        self.accent = self.rgb(pal.get("accent", "#8ab4f8"))
        self.bg_h = self.size + PAD_V + PAD_BOTTOM
        self.headroom = (self.magnify - 1) * self.size + 40
        self.set_size_request(-1, int(self.bg_h + MARGIN + self.headroom))
        if self.layer:
            GtkLayerShell.set_exclusive_zone(self, self.bg_h + MARGIN if self.mode == "off" else 0)
        self.pix.clear()

    def reload_config(self) -> bool:
        self.load_config()
        self.refresh()
        self.update_visibility()
        return False

    @staticmethod
    def rgb(hexcol: str) -> tuple[float, float, float]:
        h = hexcol.lstrip("#")
        try:
            return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
        except ValueError:
            return (0.1, 0.1, 0.1)

    # ── Hyprland events ─────────────────────────────────────────────────
    def connect_events(self) -> bool:
        try:
            self.ev = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.ev.connect(hypr_path(".socket2.sock"))
            self.ev.setblocking(False)
        except OSError:
            GLib.timeout_add_seconds(3, self.connect_events)
            return False
        self.ev_buf = b""
        GLib.io_add_watch(self.ev.fileno(), GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, self.on_event)
        return False

    def on_event(self, _fd, cond) -> bool:
        try:
            data = self.ev.recv(65536)
        except BlockingIOError:
            return True
        except OSError:
            data = b""
        if not data or cond & (GLib.IO_HUP | GLib.IO_ERR):
            self.ev.close()
            GLib.timeout_add_seconds(3, self.connect_events)
            return False
        self.ev_buf += data
        *lines, self.ev_buf = self.ev_buf.split(b"\n")
        if any(line.split(b">>", 1)[0] in HYPR_EVENTS for line in lines):
            self.schedule_refresh()
        return True

    def schedule_refresh(self) -> None:
        if not self.refresh_pending:
            self.refresh_pending = GLib.timeout_add(40, self._refresh_cb)

    def _refresh_cb(self) -> bool:
        self.refresh_pending = 0
        self.refresh()
        return False

    def periodic(self) -> bool:
        # Windows can move or resize without an event; only "smart" cares.
        if self.mode == "smart":
            self.check_overlap()
        return True

    # ── model ───────────────────────────────────────────────────────────
    def entry_item(self, app_id: str, pinned: bool) -> Item:
        e = self.index.entries.get(app_id) or {"name": app_id, "icon": app_id}
        return Item(app_id, "app", e["name"], e["icon"] or app_id, app_id, pinned)

    def refresh(self) -> None:
        clients = hypr_json("clients") or []
        active = hypr_json("activewindow") or {}
        self.active_addr = active.get("address", "") if isinstance(active, dict) else ""
        pin_keys = {}
        for p in self.pins:
            e = self.index.entries.get(p, {})
            for k in (p.lower(), p.split(".")[-1].lower(), (e.get("wmclass") or "").lower()):
                if k:
                    pin_keys.setdefault(k, p)
        groups: dict[str, list[dict]] = {}
        loose: dict[str, tuple[str, str]] = {}
        for c in clients:
            cls = c.get("class") or c.get("initialClass") or ""
            if cls in IGNORE_CLASSES or not c.get("mapped", True):
                continue
            low = cls.lower()
            key = pin_keys.get(low) or pin_keys.get(low.split(".")[-1]) or self.index.match(cls)
            if not key:
                key = "class:" + cls
                loose[key] = (cls, cls)
            groups.setdefault(key, []).append(c)
        for ws in groups.values():
            ws.sort(key=lambda c: c.get("focusHistoryID", 99))

        old = {it.key: it for it in self.items}
        items = []
        for p in self.pins:
            if p not in self.index.entries and not dockcfg.desktop_file(p):
                continue
            it = old.get(p) if old.get(p) and old[p].pinned else self.entry_item(p, True)
            it.pinned, it.target = True, 1.0
            it.windows = groups.get(p, [])
            items.append(it)
        running = [k for k in groups if k not in self.pins]
        for k in running:
            if k not in self.running_order:
                self.running_order.append(k)
        extra = []
        for k in list(self.running_order):
            it = old.get(k)
            if it is None or it.pinned:
                if k not in groups:
                    self.running_order.remove(k)
                    continue
                if k.startswith("class:"):
                    cls = loose[k][0]
                    it = Item(k, "app", cls, cls.lower(), None, False)
                else:
                    it = self.entry_item(k, False)
                it.presence = 0.0
            it.pinned = False
            it.windows = groups.get(k, [])
            it.target = 1.0 if it.windows else 0.0
            if not it.windows and it.presence <= 0.01:
                self.running_order.remove(k)
                continue
            extra.append(it)
        if extra:
            sep = old.get("@sep1") or Item("@sep1", "sep")
            sep.target = 1.0 if any(i.target for i in extra) else 0.0
            items.append(sep)
            items += extra
        items.append(old.get("@sep2") or Item("@sep2", "sep"))
        items.append(old.get("@launchpad") or Item("@launchpad", "launchpad", "Launchpad"))
        for it in items:
            if it.windows and it.bounce_until:
                it.bounce_until = 0.0          # the app is up: stop bouncing
        self.items = items
        if self.mode == "smart":
            self.check_overlap()
        self.start_tick()

    # ── visibility ──────────────────────────────────────────────────────
    def peek(self) -> bool:
        """SIGUSR1 (aether-lock after unlocking): rise for two seconds, then follow auto-hide."""
        self.startup_until = time.monotonic() + 2.0
        self.update_visibility()
        GLib.timeout_add(2100, lambda: (self.update_visibility(), False)[1])
        self.start_tick()
        return True

    def check_overlap(self) -> None:
        mons = hypr_json("monitors") or []
        mon = next((m for m in mons if m.get("focused")), mons[0] if mons else None)
        if not mon:
            return
        scale = mon.get("scale", 1) or 1
        mw, mh = mon["width"] / scale, mon["height"] / scale
        base_w = self.layout_width(hovering=False)
        x0 = mon["x"] + (mw - base_w) / 2
        y0 = mon["y"] + mh - MARGIN - self.bg_h
        ws = mon.get("activeWorkspace", {}).get("id")
        hit = False
        for c in hypr_json("clients") or []:
            if c.get("workspace", {}).get("id") != ws and not c.get("pinned") or c.get("hidden"):
                continue
            if c.get("fullscreen"):
                hit = True
                break
            (cx, cy), (cw, ch) = c.get("at", (0, 0)), c.get("size", (0, 0))
            if cx < x0 + base_w and cx + cw > x0 and cy < mh + mon["y"] and cy + ch > y0:
                hit = True
                break
        if hit != self.overlapped:
            self.overlapped = hit
            self.update_visibility()

    def update_visibility(self) -> None:
        if self.mode == "off" or self.pointer_in or self.menu_open or time.monotonic() < self.startup_until:
            want = True
        elif self.mode == "smart":
            want = not self.overlapped
        else:
            want = False
        if want != self.want_shown:
            self.want_shown = want
            self.start_tick()

    # ── geometry ────────────────────────────────────────────────────────
    def base_width(self, it: Item) -> float:
        return (14.0 if it.kind == "sep" else float(self.size)) * it.presence

    def gap(self) -> float:
        return round(self.size * 0.2)

    def layout_width(self, hovering: bool = True) -> float:
        ws = [self.base_width(i) * (i.scale if hovering else 1.0) for i in self.items]
        return sum(ws) + self.gap() * max(0, len(ws) - 1) + 2 * self.pad_h()

    def pad_h(self) -> float:
        return round(self.size * 0.24)

    def compute(self, width: float) -> tuple[float, float]:
        """Scale and place every item; return (dock left, dock width)."""
        gap = self.gap()
        base = [self.base_width(i) for i in self.items]
        total = sum(base) + gap * max(0, len(base) - 1)
        x = (width - total) / 2
        reach = self.size * 2.8
        for it, w in zip(self.items, base):
            c = x + w / 2
            f = 1.0
            if self.hover_x is not None and it.kind != "sep" and self.magnify > 1:
                d = abs(self.hover_x - c)
                if d < reach:
                    f = 1 + (self.magnify - 1) * self.hover_amt * (math.cos(math.pi * d / reach) + 1) / 2
            it.scale = f
            x += w + gap
        actual = [self.base_width(i) * i.scale for i in self.items]
        total = sum(actual) + gap * max(0, len(actual) - 1)
        x = (width - total) / 2
        for it, w in zip(self.items, actual):
            it.x0, it.x1 = x - gap / 2, x + w + gap / 2
            x += w + gap
        pad = self.pad_h()
        return (width - total) / 2 - pad, total + 2 * pad

    def dock_top(self, height: float) -> float:
        return height - MARGIN - self.bg_h + self.hide * (self.bg_h + MARGIN + 4)

    def update_region(self) -> None:
        w, h = self.area.get_allocated_width(), self.area.get_allocated_height()
        if w <= 1:
            return
        if self.hide >= 0.999:
            key = (0, h - EDGE, w, EDGE)
        else:
            left, dw = self.compute(w)
            top = self.dock_top(h)
            if self.pointer_in:
                top -= (self.magnify - 1) * self.size + 6
            # While sliding out the slab passes the bottom edge: keep at least the reveal strip.
            top = int(max(0, min(top, h - EDGE)))
            key = (int(max(0, left)), top, max(1, int(dw) + 1), h - top)
        if key != self.region_key:
            self.region_key = key
            self.input_shape_combine_region(cairo.Region(cairo.RectangleInt(*key)))

    # ── animation ───────────────────────────────────────────────────────
    def start_tick(self) -> None:
        if not self.ticking:
            self.ticking = True
            GLib.timeout_add(16, self.tick)

    def tick(self) -> bool:
        moving = False

        def approach(cur: float, target: float, speed: float) -> float:
            nonlocal moving
            if abs(cur - target) < 0.01:
                return target
            moving = True
            return cur + (target - cur) * speed

        self.hover_amt = approach(self.hover_amt, 1.0 if self.pointer_in else 0.0, 0.25)
        self.hide = approach(self.hide, 0.0 if self.want_shown else 1.0, 0.22)
        for it in self.items:
            it.presence = approach(it.presence, it.target, 0.22)
        now = time.monotonic()
        if any(it.bounce_until > now for it in self.items):
            moving = True
        drop = [it for it in self.items if it.target == 0 and it.presence == 0 and it.kind == "app"]
        if drop:
            for it in drop:
                if it.key in self.running_order:
                    self.running_order.remove(it.key)
            self.items = [it for it in self.items if it not in drop]
        if not self.pointer_in and self.hover_amt == 0:
            self.hover_x = None
        if time.monotonic() >= self.startup_until and self.startup_until:
            self.startup_until = 0
            self.update_visibility()
        self.update_region()
        self.area.queue_draw()
        if not moving:
            self.ticking = False
        return moving

    # ── drawing ─────────────────────────────────────────────────────────
    def icon(self, it: Item, px: int):
        k = (it.icon, px)
        if k in self.pix:
            return self.pix[k]
        pb = None
        flags = Gtk.IconLookupFlags.FORCE_SIZE
        try:
            if it.icon.startswith("/"):
                pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(it.icon, px, px, True)
            elif it.icon:
                for name in (it.icon, it.icon.lower()):
                    if self.theme.has_icon(name):
                        pb = self.theme.load_icon(name, px, flags)
                        break
                if pb is None:
                    path = dockcfg.find_icon(it.icon) or dockcfg.find_icon(it.icon.lower())
                    if path:
                        pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, px, px, True)
        except GLib.Error:
            pb = None
        if pb is None:
            try:
                pb = self.theme.load_icon("application-x-executable", px, flags)
            except GLib.Error:
                pb = None
        self.pix[k] = pb
        return pb

    @staticmethod
    def rounded(cr, x, y, w, h, r) -> None:
        r = min(r, h / 2, w / 2)
        cr.new_sub_path()
        cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
        cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
        cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
        cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
        cr.close_path()

    def on_draw(self, _w, cr) -> bool:
        width, height = self.area.get_allocated_width(), self.area.get_allocated_height()
        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.set_source_rgba(0, 0, 0, 0)
        cr.paint()
        cr.set_operator(cairo.OPERATOR_OVER)
        if self.hide >= 0.999:
            return False
        left, dw = self.compute(width)
        top = self.dock_top(height)
        alpha = 1 - self.hide * 0.6

        # Glass slab
        self.rounded(cr, left, top, dw, self.bg_h, 18)
        r, g, b = self.bg_rgb
        cr.set_source_rgba(r, g, b, 0.50 * alpha)
        cr.fill_preserve()
        cr.set_source_rgba(1, 1, 1, 0.13 * alpha)
        cr.set_line_width(1)
        cr.stroke()

        icon_bottom = top + self.bg_h - PAD_BOTTOM
        now = time.monotonic()
        hovered = None
        for it in self.items:
            w = self.base_width(it) * it.scale
            x = it.x0 + self.gap() / 2
            if it.kind == "sep":
                if it.presence > 0.05:
                    cr.set_source_rgba(1, 1, 1, 0.22 * alpha * it.presence)
                    cr.rectangle(x + w / 2 - 0.5, top + 10, 1, self.bg_h - 20)
                    cr.fill()
                continue
            if w < 1:
                continue
            lift = 0.0
            if it.bounce_until > now:
                t = now - it.bounce_start
                lift = abs(math.sin(t * math.pi * 1.6)) * self.size * 0.45
            y = icon_bottom - w - lift
            if it.kind == "launchpad":
                self.rounded(cr, x, y, w, w, w * 0.24)
                cr.set_source_rgba(1, 1, 1, 0.14 * alpha)
                cr.fill()
                self.glyph(cr, "󰀻", x + w / 2, y + w / 2, w * 0.5, alpha)
            else:
                pb = self.icon(it, int(self.size * self.magnify))
                if pb is not None:
                    cr.save()
                    cr.translate(x, y)
                    cr.scale(w / pb.get_width(), w / pb.get_height())
                    Gdk.cairo_set_source_pixbuf(cr, pb, 0, 0)
                    cr.get_source().set_filter(cairo.FILTER_GOOD)
                    cr.paint_with_alpha(alpha * min(1.0, it.presence * 1.4))
                    cr.restore()
            if it.windows:
                focused = any(c.get("address") == self.active_addr for c in it.windows)
                cr.set_source_rgba(*(self.accent if focused else (1, 1, 1)), 0.95 * alpha)
                cr.arc(x + w / 2, top + self.bg_h - 6, 2.4 if focused else 2.0, 0, 2 * math.pi)
                cr.fill()
            if self.pointer_in and self.hover_x is not None and it.x0 <= self.hover_x < it.x1:
                hovered = (it, x + w / 2, y)
        if hovered and not self.menu_open and self.hover_amt > 0.5:
            self.label(cr, hovered[0].name, hovered[1], hovered[2] - 10)
        return False

    @staticmethod
    def glyph(cr, text: str, cx: float, cy: float, px: float, alpha: float) -> None:
        layout = PangoCairo.create_layout(cr)
        layout.set_font_description(Pango.FontDescription("JetBrainsMono Nerd Font %d" % max(8, int(px * 0.75))))
        layout.set_text(text, -1)
        tw, th = layout.get_pixel_size()
        cr.set_source_rgba(1, 1, 1, 0.92 * alpha)
        cr.move_to(cx - tw / 2, cy - th / 2)
        PangoCairo.show_layout(cr, layout)

    def label(self, cr, text: str, cx: float, bottom: float) -> None:
        layout = PangoCairo.create_layout(cr)
        layout.set_font_description(Pango.FontDescription("Inter, Cantarell, sans-serif Semi-Bold 10"))
        layout.set_text(text, -1)
        tw, th = layout.get_pixel_size()
        w, h = tw + 20, th + 10
        x = max(4.0, min(self.area.get_allocated_width() - w - 4, cx - w / 2))
        y = bottom - h
        self.rounded(cr, x, y, w, h, 8)
        r, g, b = self.bg_rgb
        cr.set_source_rgba(r, g, b, 0.88)
        cr.fill_preserve()
        cr.set_source_rgba(1, 1, 1, 0.12)
        cr.set_line_width(1)
        cr.stroke()
        cr.set_source_rgba(1, 1, 1, 0.95)
        cr.move_to(x + 10, y + 5)
        PangoCairo.show_layout(cr, layout)

    # ── pointer ─────────────────────────────────────────────────────────
    def on_enter(self, _w, e) -> bool:
        if self.hide_timer:
            GLib.source_remove(self.hide_timer)
            self.hide_timer = 0
        self.pointer_in = True
        self.hover_x = e.x
        self.update_visibility()
        self.start_tick()
        return False

    def on_motion(self, _w, e) -> bool:
        self.pointer_in = True
        self.hover_x = e.x
        self.start_tick()
        return False

    def on_leave(self, _w, e) -> bool:
        if e.detail == Gdk.NotifyType.INFERIOR or self.menu_open:
            return False
        self.pointer_in = False
        self.start_tick()
        if self.hide_timer:
            GLib.source_remove(self.hide_timer)
        self.hide_timer = GLib.timeout_add(350, self._leave_done)
        return False

    def _leave_done(self) -> bool:
        self.hide_timer = 0
        self.update_visibility()
        return False

    def item_at(self, x: float) -> Item | None:
        return next((it for it in self.items if it.kind != "sep" and it.x0 <= x < it.x1 and it.presence > 0.5), None)

    # ── actions ─────────────────────────────────────────────────────────
    def on_click(self, _w, e) -> bool:
        if self.hide > 0.5:
            return False
        it = self.item_at(e.x)
        if it is None:
            return False
        if it.kind == "launchpad":
            if e.button == 3:
                self.spawn(["aether-dock", "menu"])
            else:
                self.spawn(["aether-menu", "launchpad"])
            return True
        if e.button == 1:
            self.activate(it)
        elif e.button == 2 and it.app_id:
            self.launch(it, new_instance=True)
        elif e.button == 3:
            self.menu(it, e)
        return True

    @staticmethod
    def spawn(argv: list[str]) -> None:
        try:
            subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
        except OSError:
            pass

    def launch(self, it: Item, new_instance: bool = False) -> None:
        if not it.app_id:
            return
        if not new_instance and it.bounce_until > time.monotonic():
            return          # still starting: a second click must not open a duplicate
        self.spawn(["gtk-launch", it.app_id])
        it.bounce_start = time.monotonic()
        it.bounce_until = it.bounce_start + 4.0
        self.start_tick()

    def focus(self, c: dict) -> None:
        # Switches to the window's workspace (or shows its special one) and gives it keyboard focus.
        dockcfg.focus_window(c["address"])
        self.schedule_refresh()

    def activate(self, it: Item) -> None:
        if not it.windows:
            self.launch(it)
            return
        addrs = [c["address"] for c in it.windows]
        if self.active_addr in addrs:
            if len(addrs) > 1:
                # Cycle in a stable order so repeated clicks visit every window.
                ordered = sorted(it.windows, key=lambda c: c["address"])
                i = [c["address"] for c in ordered].index(self.active_addr)
                self.focus(ordered[(i + 1) % len(ordered)])
            return
        self.focus(it.windows[0])

    def set_pinned(self, it: Item, pin: bool) -> None:
        if not it.app_id:
            return
        st = dockcfg.load_state()
        if pin and it.app_id not in st["pins"]:
            st["pins"].append(it.app_id)
        elif not pin and it.app_id in st["pins"]:
            st["pins"].remove(it.app_id)
        dockcfg.save_state(st)
        dockcfg.generate(st)        # keep the Waybar dock modules in step
        if not pin and it.windows:
            self.running_order.append(it.app_id)

    def menu(self, it: Item, e) -> None:
        m = Gtk.Menu()

        def add(text: str, cb=None, sensitive: bool = True) -> None:
            mi = Gtk.MenuItem(label=text)
            mi.set_sensitive(sensitive)
            if cb:
                mi.connect("activate", lambda *_a: cb())
            m.append(mi)

        add(it.name, sensitive=False)
        if len(it.windows) > 1:
            m.append(Gtk.SeparatorMenuItem())
            for c in it.windows:
                title = (c.get("title") or it.name)[:60]
                add(title, lambda c=c: self.focus(c))
        m.append(Gtk.SeparatorMenuItem())
        if it.app_id:
            add("New Window", lambda: self.launch(it, new_instance=True))
            keep = Gtk.CheckMenuItem(label="Keep in Dock")
            keep.set_active(it.pinned)
            keep.connect("toggled", lambda w: self.set_pinned(it, w.get_active()))
            m.append(keep)
        if it.windows:
            add("Quit" if len(it.windows) == 1 else "Quit %d Windows" % len(it.windows),
                lambda: [dockcfg.close_window(c["address"]) for c in it.windows])
        m.append(Gtk.SeparatorMenuItem())
        add("Dock Settings…", lambda: self.spawn(["aether-dock", "menu"]))
        m.show_all()

        def closed(*_a) -> None:
            self.menu_open = False
            self.pointer_in = False
            self.start_tick()
            self.hide_timer = GLib.timeout_add(350, self._leave_done)
        m.connect("deactivate", closed)
        self.menu_open = True
        self._menu = m
        m.popup_at_pointer(e)


def main(argv: list[str] | None = None) -> int:
    if (argv if argv is not None else sys.argv[1:])[:1] in (["-h"], ["--help"]):
        print(__doc__.strip())
        return 0
    w = Dock()
    w.connect("destroy", Gtk.main_quit)
    w.show_all()
    Gtk.main()
    return 0
