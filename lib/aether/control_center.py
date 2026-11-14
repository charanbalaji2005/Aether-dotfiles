"""AetherOS Control Centre panel (classic interface) — Super+A or the bar's 󰒓 button.

A frosted-glass panel in the top-right corner with the controls chosen in
Settings → Control Centre. On Hyprland it is a layer-shell surface (namespace
"aether-control") so the compositor blurs what is behind it; without
gtk-layer-shell it falls back to a floating window. States are read from the
system when the panel opens and every two seconds while it is visible.
Escape or clicking elsewhere closes it.
"""

from __future__ import annotations

import datetime
import os
import sys
import threading

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

from aether import classic_colors as cc  # noqa: E402
from aether import controls as ctl  # noqa: E402

try:
    gi.require_version("GtkLayerShell", "0.1")
    from gi.repository import GtkLayerShell  # noqa: E402
except (ValueError, ImportError):
    GtkLayerShell = None

CSS = """
* { font-family: "Inter", "SF Pro Display", "Cantarell", "Noto Sans", sans-serif; }
.cc-window, .cc-window > * { background-color: transparent; }
/* The panel itself is almost clear: the blurred desktop is the background. */
.cc-root { background-color: alpha(%(background)s, %(glass)s); border: 1px solid alpha(white, 0.10);
           border-radius: 34px; padding: 18px; }
.cc-top { font-family: "JetBrainsMono Nerd Font", "Inter", sans-serif; font-size: 12px; font-weight: 700; color: white; }
.cc-date { font-size: 12px; color: alpha(white, 0.65); font-weight: 600; }
.cc-time { font-size: 30px; font-weight: 300; color: alpha(white, 0.92); }
.cc-iconbtn { font-family: "JetBrainsMono Nerd Font"; font-size: 20px; font-weight: 300; color: white; background-image: none; padding: 4px 6px;
              background-color: transparent; border: none; box-shadow: none; text-shadow: none;
              min-width: 32px; min-height: 32px; border-radius: 99px; padding: 0; }
.cc-iconbtn label { color: white; }
button.cc-iconbtn, button.cc-iconbtn:backdrop, button.cc-iconbtn:disabled, button.cc-iconbtn:active,
button.cc-ctrl, button.cc-ctrl:backdrop, button.cc-ctrl:disabled, button.cc-ctrl:active {
    background-image: none; background-color: transparent; border-color: transparent; box-shadow: none; }
button.cc-iconbtn:hover, button.cc-ctrl:hover { background-color: alpha(white, 0.16); }
button.cc-ctrl:disabled label { color: alpha(white, 0.35); }
.cc-iconbtn:hover { background-color: alpha(white, 0.14); }
/* Modules: frosted white, very round, like a phone control centre. */
.cc-tile { background-color: alpha(white, 0.13); border: 1px solid alpha(white, 0.10); border-radius: 30px; padding: 12px; }
.cc-tile:hover { background-color: alpha(white, 0.18); }
.cc-tile.round { border-radius: 99px; padding: 0; }
.cc-tile.pill { border-radius: 99px; padding: 8px 14px 8px 8px; }
.cc-tile.disabled { opacity: 0.42; }
.cc-orb { font-family: "JetBrainsMono Nerd Font"; font-size: 19px; min-width: 46px; min-height: 46px; border-radius: 99px;
          background-color: alpha(white, 0.16); color: white; }
.cc-orb.mini { font-size: 16px; min-width: 40px; min-height: 40px; }
.cc-tile.round .cc-orb { background-color: transparent; font-size: 22px; min-width: 70px; min-height: 70px; }
.cc-name { font-size: 13px; font-weight: 700; color: white; }
.cc-sub { font-size: 11px; color: alpha(white, 0.65); }
.cc-small { font-size: 10px; color: alpha(white, 0.7); }
.cc-media { font-weight: 800; font-size: 13px; color: white; }
.cc-art { border-radius: 12px; }
.cc-ctrl { font-family: "JetBrainsMono Nerd Font"; font-size: 20px; background-image: none; background-color: transparent;
           border: none; box-shadow: none; text-shadow: none; color: white; min-width: 36px; min-height: 36px;
           border-radius: 99px; padding: 0; }
.cc-ctrl label { color: white; }
.cc-ctrl:hover { background-color: alpha(white, 0.16); }
/* Tall sliders: the fill rises from the bottom, icon at the foot. */
scale.cc-vslider { padding: 0; margin: 0; }
scale.cc-vslider trough, scale.cc-vslider trough:backdrop, scale.cc-vslider trough:disabled {
    background-image: none; background-color: alpha(white, 0.16); min-width: 76px; border-radius: 30px; border: none;
    box-shadow: none; margin: 0; }
scale.cc-vslider trough highlight, scale.cc-vslider trough highlight:disabled, scale.cc-vslider trough highlight:backdrop {
    background-image: none; background-color: alpha(white, 0.92); border: none; border-radius: 30px; min-width: 76px; }
scale.cc-vslider trough slider, scale.cc-vslider trough slider:hover, scale.cc-vslider trough slider:disabled,
scale.cc-vslider trough slider:backdrop {
    min-width: 0; min-height: 0; background-image: none; background-color: transparent; border: none;
    box-shadow: none; margin: 0; padding: 0; opacity: 0; }
.cc-tile.bare { background-color: transparent; border: none; padding: 0; }
.cc-vicon { font-family: "JetBrainsMono Nerd Font"; font-size: 20px; color: %(background)s; }
.cc-vicon.low { color: white; }
.cc-msg { font-size: 11px; color: alpha(white, 0.75); }
"""

COLS = 4
CELL = 76


class VFill(Gtk.DrawingArea):
    """A phone-style tall slider: a rounded bar that fills from the bottom.

    Drawn with cairo so no toolkit theme can add knobs or borders. Click or
    drag to set; `on_set(value)` runs when the button is released."""

    def __init__(self, on_set, enabled: bool = True) -> None:
        super().__init__()
        self.value = 0.0
        self.on_set = on_set
        self.enabled = enabled
        self.set_vexpand(True)
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
                        | Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.SCROLL_MASK)
        self.dragging = False
        self.connect("draw", self.on_draw)
        self.connect("button-press-event", self.on_press)
        self.connect("motion-notify-event", self.on_motion)
        self.connect("button-release-event", self.on_release)
        self.connect("scroll-event", self.on_scroll)

    def set_value(self, v: float) -> None:
        if not self.dragging:
            self.value = max(0.0, min(100.0, v))
            self.queue_draw()

    def _from_y(self, y: float) -> float:
        h = max(1, self.get_allocated_height())
        return max(0.0, min(100.0, 100.0 * (1 - y / h)))

    def on_press(self, _w, e) -> bool:
        if self.enabled:
            self.dragging = True
            self.value = self._from_y(e.y)
            self.queue_draw()
        return True

    def on_motion(self, _w, e) -> bool:
        if self.dragging:
            self.value = self._from_y(e.y)
            self.queue_draw()
        return True

    def on_release(self, _w, _e) -> bool:
        if self.dragging:
            self.dragging = False
            self.on_set(self.value)
        return True

    def on_scroll(self, _w, e) -> bool:
        if self.enabled and e.direction in (Gdk.ScrollDirection.UP, Gdk.ScrollDirection.DOWN):
            self.value = max(0.0, min(100.0, self.value + (5 if e.direction == Gdk.ScrollDirection.UP else -5)))
            self.queue_draw()
            self.on_set(self.value)
        return True

    def on_draw(self, _w, cr) -> bool:
        import math
        w, h = self.get_allocated_width(), self.get_allocated_height()
        r = min(30.0, w / 2)

        def rounded(x, y, ww, hh, rr):
            cr.new_sub_path()
            cr.arc(x + ww - rr, y + rr, rr, -math.pi / 2, 0)
            cr.arc(x + ww - rr, y + hh - rr, rr, 0, math.pi / 2)
            cr.arc(x + rr, y + hh - rr, rr, math.pi / 2, math.pi)
            cr.arc(x + rr, y + rr, rr, math.pi, 3 * math.pi / 2)
            cr.close_path()
        rounded(0, 0, w, h, r)
        cr.set_source_rgba(1, 1, 1, 0.16)
        cr.fill_preserve()
        cr.clip()
        fill = h * self.value / 100.0
        cr.rectangle(0, h - fill, w, fill)
        cr.set_source_rgba(1, 1, 1, 0.92 if self.enabled else 0.35)
        cr.fill()
        return False



def load_css(glass: float = 0.72) -> None:
    pal = dict(cc.resolve_palette(cc.read_state())[0])
    pal["glass"] = "%.2f" % glass
    # One class per "on" colour, e.g. .cc-orb.tint-0a84ff (Wi-Fi blue).
    tints = "".join(".cc-orb.tint-%s, .cc-tile.round .cc-orb.tint-%s { background-color: %s; color: white; }\n"
                    % (t.lstrip("#"), t.lstrip("#"), t)
                    for t in sorted({c.tint for c in ctl.CONTROLS.values()}))
    prov = Gtk.CssProvider()
    prov.load_from_data((CSS % pal + tints).encode())
    Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), prov, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)


def glass_alpha() -> float:
    lvl = cc.read_state().get("glass", "acrylic")
    # The panel is mostly see-through (the compositor blurs behind it); this is its tint.
    return {"off": 0.92, "subtle": 0.55, "acrylic": 0.38, "deep": 0.24}.get(lvl, 0.38)


class Panel(Gtk.Box):
    """The grid of controls. Also used, non-interactively, as the editor preview."""

    def __init__(self, ids: list[str] | None = None, interactive: bool = True, on_message=None, cell: int = CELL) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.get_style_context().add_class("cc-root")
        self.interactive = interactive
        self.on_message = on_message or (lambda _t: None)
        self.ids = ids if ids is not None else ctl.load_layout()
        self.cell = cell
        self.widgets: dict[str, dict] = {}
        self.build()

    def build(self) -> None:
        for ch in self.get_children():
            self.remove(ch)
        now = datetime.datetime.now()
        # Top row: edit (+) on the left, real status and power on the right.
        top = Gtk.Box(spacing=6)
        plus = self.flat("+", "cc-iconbtn", lambda: (ctl.spawn("aether-settings", "controls"), self.get_toplevel().close()),
                         "Edit Controls", self.interactive)
        top.pack_start(plus, False, False, 0)
        self.status = Gtk.Label(label="", xalign=1)
        self.status.get_style_context().add_class("cc-top")
        top.pack_start(self.status, True, True, 0)
        pw = self.flat("󰐥", "cc-iconbtn", lambda: (ctl.spawn("aether-powermenu"), self.get_toplevel().close()),
                       "Power menu", self.interactive)
        top.pack_end(pw, False, False, 0)
        self.pack_start(top, False, False, 0)
        hv = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        d = Gtk.Label(label=now.strftime("%a %d %b"), xalign=0.5)
        d.get_style_context().add_class("cc-date")
        self.time = Gtk.Label(label=now.strftime("%H:%M"), xalign=0.5)
        self.time.get_style_context().add_class("cc-time")
        hv.pack_start(self.time, False, False, 0)
        hv.pack_start(d, False, False, 0)
        self.pack_start(hv, False, False, 4)

        grid = Gtk.Grid(column_spacing=12, row_spacing=12, column_homogeneous=True, row_homogeneous=True,
                        halign=Gtk.Align.CENTER)
        occupied: set[tuple[int, int]] = set()
        for cid in self.ids:
            c = ctl.CONTROLS[cid]
            w, h = {"small": (1, 1), "wide": (2, 1), "tall": (1, 2), "big": (2, 2)}[c.size]
            pos = self.free_slot(occupied, w, h)
            for dx in range(w):
                for dy in range(h):
                    occupied.add((pos[0] + dx, pos[1] + dy))
            tile = self.tile(c)
            if not (c.size == "small" and c.kind in ("toggle", "button")):
                tile.set_size_request(self.cell * w + 12 * (w - 1), self.cell * h + 12 * (h - 1))
            grid.attach(tile, pos[0], pos[1], w, h)
        self.pack_start(grid, False, False, 0)
        self.msg = Gtk.Label(label="", xalign=0)
        self.msg.get_style_context().add_class("cc-msg")
        self.pack_start(self.msg, False, False, 0)
        self.show_all()

    @staticmethod
    def free_slot(occ: set, w: int, h: int) -> tuple[int, int]:
        row = 0
        while True:
            for col in range(0, COLS - w + 1):
                if all((col + dx, row + dy) not in occ for dx in range(w) for dy in range(h)):
                    return col, row
            row += 1

    def flat(self, glyph: str, cls: str, cb, tooltip: str = "", enabled: bool = True) -> Gtk.EventBox:
        """A themeless button: an event box around a glyph (toolkit themes can't add chrome)."""
        ev = Gtk.EventBox()
        lab = Gtk.Label(label=glyph)
        lab.get_style_context().add_class(cls)
        if not enabled:
            lab.set_opacity(0.35)
        ev.add(lab)
        if tooltip:
            ev.set_tooltip_text(tooltip)
        if enabled:
            ev.connect("button-release-event", lambda *_a: cb())
        ev.label = lab
        return ev

    def orb(self, glyph: str, mini: bool = False) -> Gtk.Label:
        o = Gtk.Label(label=glyph, valign=Gtk.Align.CENTER, halign=Gtk.Align.CENTER)
        o.get_style_context().add_class("cc-orb")
        if mini:
            o.get_style_context().add_class("mini")
        return o

    def clickable(self, widget: Gtk.Widget, c: ctl.Control) -> Gtk.EventBox:
        ev = Gtk.EventBox()
        ev.add(widget)
        if self.interactive and c.available():
            ev.connect("button-release-event", lambda _w, _e, c=c: self.run(c))
        ev.set_tooltip_text(c.name if c.available() else "%s — needs %s" % (c.name, ", ".join(c.needs)))
        return ev

    def tile(self, c: ctl.Control) -> Gtk.Widget:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.get_style_context().add_class("cc-tile")
        parts: dict = {"box": box, "control": c}
        if c.kind != "cluster" and not c.available():
            box.get_style_context().add_class("disabled")
        if c.kind == "cluster":
            # One card holding four round toggles (airplane, power, Wi-Fi, Bluetooth).
            g = Gtk.Grid(row_spacing=10, column_spacing=10, row_homogeneous=True, column_homogeneous=True,
                         halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER, vexpand=True)
            parts["members"] = {}
            for i, mid in enumerate(c.members):
                m = ctl.CONTROLS[mid]
                o = self.orb(m.glyph)
                o.set_size_request(54, 54)
                ev = self.clickable(o, m)
                if not m.available():
                    o.set_opacity(0.4)
                g.attach(ev, i % 2, i // 2, 1, 1)
                parts["members"][mid] = o
            box.pack_start(g, True, True, 0)
            self.widgets[c.cid] = parts
            for mid in c.members:   # members also refresh their own state
                self.widgets[mid] = {"box": None, "control": ctl.CONTROLS[mid], "orb": parts["members"][mid]}
            return box
        if c.kind == "slider":
            ov = Gtk.Overlay()
            vf = VFill(lambda v, c=c: self.run(c, v), enabled=self.interactive and c.available())
            vf.set_size_request(self.cell, self.cell * 2 + 12)
            ov.add(vf)
            icon = Gtk.Label(label=c.glyph, valign=Gtk.Align.END, halign=Gtk.Align.CENTER, margin_bottom=14)
            icon.get_style_context().add_class("cc-vicon")
            ov.add_overlay(icon)
            ov.set_overlay_pass_through(icon, True)
            box.get_style_context().add_class("bare")
            box.pack_start(ov, True, True, 0)
            parts.update(scale=vf, vicon=icon)
            box.set_tooltip_text(c.name)
            self.widgets[c.cid] = parts
            return box
        if c.kind == "media":
            top = Gtk.Box(spacing=10)
            parts["art"] = Gtk.Image()
            parts["art"].get_style_context().add_class("cc-art")
            parts["orb"] = self.orb(c.glyph, mini=True)
            top.pack_start(parts["orb"], False, False, 0)
            top.pack_start(parts["art"], False, False, 0)
            box.pack_start(top, False, False, 0)
            parts["title"] = Gtk.Label(label="", xalign=0, ellipsize=3, max_width_chars=12, width_chars=12)
            parts["title"].get_style_context().add_class("cc-media")
            parts["sub"] = Gtk.Label(label="", xalign=0, ellipsize=3, max_width_chars=14, width_chars=14)
            parts["sub"].get_style_context().add_class("cc-sub")
            box.pack_start(parts["title"], False, False, 0)
            box.pack_start(parts["sub"], False, False, 0)
            row = Gtk.Box(spacing=4, halign=Gtk.Align.CENTER)
            for g, what in (("󰒮", "previous"), ("󰐊", "play-pause"), ("󰒭", "next")):
                b = self.flat(g, "cc-ctrl", lambda w=what, c=c: self.run(c, w), "", self.interactive and c.available())
                if what == "play-pause":
                    parts["play"] = b.label
                row.pack_start(b, False, False, 0)
            box.pack_end(row, False, False, 0)
            self.widgets[c.cid] = parts
            return box
        if c.size == "wide":   # a pill: orb + name + state, like "Focus"
            box.get_style_context().add_class("pill")
            hb = Gtk.Box(spacing=10, valign=Gtk.Align.CENTER, vexpand=True)
            parts["orb"] = self.orb(c.glyph, mini=True)
            hb.pack_start(parts["orb"], False, False, 0)
            tv = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER)
            n = Gtk.Label(label=c.name, xalign=0)
            n.get_style_context().add_class("cc-name")
            parts["sub"] = Gtk.Label(label="", xalign=0, ellipsize=3, max_width_chars=14)
            parts["sub"].get_style_context().add_class("cc-sub")
            tv.pack_start(n, False, False, 0)
            tv.pack_start(parts["sub"], False, False, 0)
            hb.pack_start(tv, True, True, 0)
            box.pack_start(hb, True, True, 0)
        else:                  # a round button: a true circle centred in its cell
            box.get_style_context().add_class("round")
            box.set_size_request(self.cell, self.cell)
            box.set_halign(Gtk.Align.CENTER)
            box.set_valign(Gtk.Align.CENTER)
            parts["orb"] = self.orb(c.glyph)
            parts["orb"].set_vexpand(True)
            box.pack_start(parts["orb"], True, True, 0)
        self.widgets[c.cid] = parts
        return self.clickable(box, c)

    # ── state ─────────────────────────────────────────────────────────
    def refresh(self) -> bool:
        def work() -> None:
            states = {cid: (p["control"].state() if p["control"].available() else {"disabled": True, "label": "Not installed"})
                      for cid, p in self.widgets.items() if p["control"].kind != "cluster"}
            GLib.idle_add(self.apply_states, states)
        threading.Thread(target=work, daemon=True).start()
        self.time.set_text(datetime.datetime.now().strftime("%H:%M"))
        return True

    def apply_states(self, states: dict) -> bool:
        for cid, st in states.items():
            p = self.widgets.get(cid)
            if not p or p["control"].kind == "cluster":
                continue
            c = p["control"]
            if p.get("box") is not None:
                ctx = p["box"].get_style_context()
                (ctx.add_class if st.get("disabled") else ctx.remove_class)("disabled")
            orb = p.get("orb")
            if orb is not None and c.kind == "toggle":
                # On: the control's own colour, like a phone control centre.
                octx = orb.get_style_context()
                cls = "tint-" + c.tint.lstrip("#")
                (octx.add_class if st.get("on") else octx.remove_class)(cls)
            if "scale" in p and "value" in st:
                p["scale"].set_value(st["value"])
                p["vicon"].get_style_context().remove_class("low") if st["value"] > 18 else \
                    p["vicon"].get_style_context().add_class("low")
                p["scale"].set_tooltip_text("%s: %s" % (c.name, st.get("label") or ("Muted" if st.get("muted") else "%d%%" % st["value"])))
            elif "title" in p:
                p["title"].set_text(st.get("title") or st.get("label") or "Nothing playing")
                p["sub"].set_text(st.get("artist", ""))
                if "play" in p:
                    p["play"].set_label("󰏤" if st.get("playing") else "󰐊")
                self._set_art(p, st.get("art", ""))
            elif "sub" in p:
                p["sub"].set_text(st.get("label", ""))
        if hasattr(self, "status"):
            self.status.set_text(self._status_line(states))
        return False

    @staticmethod
    def _rgba(hexcol):
        if not hexcol:
            return None
        r = Gdk.RGBA()
        r.parse(hexcol)
        return r

    def _set_art(self, p: dict, url: str) -> None:
        path = url[7:] if url.startswith("file://") else ""
        if path:
            from urllib.parse import unquote
            path = unquote(path)
        if path and os.path.isfile(path):
            try:
                from gi.repository import GdkPixbuf
                p["art"].set_from_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_scale(path, 48, 48, True))
                p["art"].show()
                p["orb"].hide()
                return
            except GLib.Error:
                pass
        p["art"].hide()
        p["orb"].show()

    @staticmethod
    def _status_line(states: dict) -> str:
        parts = []
        w = states.get("wifi", {})
        if not w.get("disabled"):
            parts.append("󰖩" if w.get("on") else "󰖪")
        for b in sorted(os.listdir("/sys/class/power_supply")) if os.path.isdir("/sys/class/power_supply") else []:
            cap = os.path.join("/sys/class/power_supply", b, "capacity")
            if b.startswith("BAT") and os.path.isfile(cap):
                parts.append("%s%%" % open(cap).read().strip())
                break
        return "   ".join(parts)

    def run(self, c: ctl.Control, *args) -> None:
        def work() -> None:
            rc, out = c.act(*args)
            GLib.idle_add(self.msg.set_text, "" if rc == 0 else "%s: %s" % (c.name, (out.splitlines() or ["failed"])[-1][:80]))
            GLib.timeout_add(350, self.refresh)
        threading.Thread(target=work, daemon=True).start()


class Window(Gtk.Window):
    def __init__(self) -> None:
        super().__init__(title="Control Centre")
        self.set_wmclass("aether-control", "AetherOS Control Centre")
        self.get_style_context().add_class("cc-window")
        screen = self.get_screen()
        if screen.get_rgba_visual():
            self.set_visual(screen.get_rgba_visual())
        self.set_app_paintable(True)
        self.set_decorated(False)
        if GtkLayerShell and GtkLayerShell.is_supported():
            GtkLayerShell.init_for_window(self)
            GtkLayerShell.set_namespace(self, "aether-control")
            GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
            GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
            GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.RIGHT, True)
            GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, 46)
            GtkLayerShell.set_margin(self, GtkLayerShell.Edge.RIGHT, 12)
            GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.ON_DEMAND)
        load_css(glass_alpha())
        self.panel = Panel()
        self.add(self.panel)
        self.connect("key-press-event", lambda _w, e: e.keyval == Gdk.KEY_Escape and self.close())
        self.connect("focus-out-event", lambda *_a: GLib.timeout_add(150, self.close_if_unfocused))
        self.panel.refresh()
        GLib.timeout_add_seconds(2, self.panel.refresh)

    def close_if_unfocused(self) -> bool:
        if not self.is_active():
            self.close()
        return False


def main(argv: list[str] | None = None) -> int:
    if (argv or sys.argv[1:])[:1] in (["-h"], ["--help"]):
        print(__doc__.strip())
        return 0
    w = Window()
    w.connect("destroy", Gtk.main_quit)
    w.show_all()
    Gtk.main()
    return 0
