"""AetherOS Settings — a GTK 3 window for the classic interface.

Every control calls the same command-line helpers the menus and keys use
(aether-look, aether-colors, aether-waybar, aether-dock, aether-lock,
aether-wall, aether-bindings, aether-interface, aether performance), so there
is one source of truth: ~/.config/aether-shell/classic/state.conf and the
files those helpers own. Pages read the current state when they are built;
every action reports what the helper actually returned.

Run: aether-settings [PAGE]   (pages: looks appearance display controls bar island
dock lock wallpaper keys system)
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import threading
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk  # noqa: E402

from aether import classic_colors as cc  # noqa: E402
from aether import dock as dockmod  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
BIN = REPO / "scripts" / "bin"

PAGES = [
    ("looks", "󰔉", "Looks", "Bar, launcher, colours, spacing and lock screen in one step"),
    ("appearance", "󰏘", "Appearance", "Dark or light, where colours come from, visual effects"),
    ("display", "󰍹", "Display & zoom", "Screen scale and the magnifier"),
    ("controls", "󰒓", "Control Centre", "Choose and order the controls of the panel (Super+A)"),
    ("bar", "󰕮", "Bar", "Waybar layout and style"),
    ("island", "󰍡", "Island", "The centre pill of the home look"),
    ("dock", "󰀻", "Dock", "Pinned apps and icon size"),
    ("lock", "󰌾", "Lock screen", "Design of the Hyprlock screen"),
    ("wallpaper", "󰸉", "Wallpaper", "Gallery, random, slideshow"),
    ("keys", "󰌌", "Keyboard shortcuts", "Every binding, searchable, with a conflict check"),
    ("system", "󰒓", "System", "Interface, health check and versions"),
]


# Each page has its own tile colour (a palette role), like modern settings apps.
# Fixed, distinct category colours (independent of the palette) so every page
# is recognisable at a glance.
PAGE_TINT = {"controls": "#4a7cf0", "looks": "#7c6cf2", "appearance": "#e86aa6", "display": "#14a3a0", "bar": "#3b8eea", "island": "#3a3d46", "dock": "#2fb36d",
             "lock": "#e5534b", "wallpaper": "#e8962e", "keys": "#8a7a5c", "system": "#5aa9c9"}


def run(*args: str, timeout: int = 120) -> tuple[int, str]:
    """Run a helper (never through a shell); return (exit code, combined output)."""
    cmd = list(args)
    if (BIN / cmd[0]).is_file():
        cmd[0] = str(BIN / cmd[0])
        cmd.insert(0, "bash")
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=False)
        return p.returncode, (p.stdout + p.stderr).strip()
    except (OSError, subprocess.TimeoutExpired) as e:
        return 1, str(e)


def state() -> dict:
    return cc.read_state()


def set_state(key: str, value: str) -> None:
    st = cc.read_state()
    st[key] = value
    cc.write_state(st)


CSS = """
/* Modern, libadwaita-style look: a flat header bar, bold group titles over
   rounded "boxed list" cards, hairline separators between rows, round
   steppers and switches. */
* { font-family: "Inter", "Cantarell", "Noto Sans", sans-serif; }
window, .main { background-color: %(glass_background)s; color: %(text)s; }
decoration { border-radius: 14px; box-shadow: 0 4px 18px alpha(black, 0.45), 0 0 0 1px alpha(%(text)s, 0.08); }

/* header bar */
headerbar { background-image: none; background-color: alpha(%(surface)s, 0.96); border: none;
            border-bottom: 1px solid alpha(%(text)s, 0.07); box-shadow: none; min-height: 46px; padding: 0 8px; }
headerbar .title { font-size: 14px; font-weight: 700; color: %(text)s; }
headerbar .subtitle { font-size: 11px; color: %(muted)s; }
headerbar button { min-height: 28px; min-width: 28px; padding: 0 8px; border-radius: 8px; }
headerbar button.titlebutton { min-width: 26px; min-height: 26px; padding: 0; margin: 10px 4px; border-radius: 99px;
                               background-color: alpha(%(text)s, 0.10); }
headerbar button.titlebutton:hover { background-color: alpha(%(text)s, 0.18); }
.head-tab { font-weight: 700; }

/* sidebar */
.sidebar { background-color: alpha(%(surface)s, 0.78); border-right: 1px solid alpha(%(text)s, 0.07); }
.profile { margin: 14px 12px 8px 12px; padding: 10px; border-radius: 12px; background-color: alpha(%(text)s, 0.05); }
.profile-name { font-size: 14px; font-weight: 700; }
.profile-sub { font-size: 11px; color: %(muted)s; }
.side-search { margin: 4px 12px 10px 12px; border-radius: 8px; min-height: 32px; }
entry { caret-color: %(accent)s; }
entry:focus { border-color: alpha(%(accent)s, 0.6); box-shadow: 0 0 0 2px alpha(%(accent)s, 0.22); }
entry image { color: %(muted)s; }
.sidebar list, .sidebar row { background-color: transparent; }
.sidebar row { padding: 5px 8px; border-radius: 8px; margin: 1px 8px; }
.sidebar row:hover { background-color: alpha(%(text)s, 0.06); }
.sidebar row:selected { background-color: alpha(%(text)s, 0.11); }
.sidebar row:selected .nav-label { color: %(text)s; font-weight: 700; }
.nav-label { font-size: 13px; color: %(subtext)s; }
.tile { font-family: "JetBrainsMono Nerd Font"; font-size: 13px; min-width: 26px; min-height: 26px;
        border-radius: 7px; color: %(background)s; }
.tile.big { font-size: 20px; min-width: 44px; min-height: 44px; border-radius: 12px; }
.side-foot { font-size: 11px; color: %(muted)s; margin: 10px 16px 14px 16px; }

/* page */
.title { font-size: 22px; font-weight: 800; letter-spacing: -0.3px; }
.subtitle { color: %(subtext)s; font-size: 13px; }
.section { font-size: 15px; font-weight: 700; color: %(text)s; margin-top: 6px; }

/* group: title + description above a boxed list of rows */
.card { background-color: transparent; border: none; padding: 0; margin-bottom: 6px; }
.card-head { padding: 0 2px 10px 2px; }
.card-title { font-weight: 700; font-size: 15px; }
.card-sub { color: %(subtext)s; font-size: 13px; }
.card > .setting-row { background-color: alpha(%(text)s, 0.055); padding: 10px 14px; min-height: 34px;
                       border-top: 1px solid alpha(black, 0.28); }
.card > .setting-row:nth-child(2) { border-top: none; border-radius: 12px 12px 0 0; }
.card > .setting-row:last-child { border-radius: 0 0 12px 12px; }
.card > .setting-row:nth-child(2):last-child { border-radius: 12px; }
.setting-row { padding: 10px 14px; }
.row-label { font-size: 14px; }
.muted { color: %(muted)s; font-size: 12px; }
.current { color: %(accent)s; font-weight: 800; font-size: 11px; background-color: alpha(%(accent)s, 0.14);
           border-radius: 99px; padding: 2px 10px; }

/* look gallery keeps self-contained cards */
.card.look-card { background-color: alpha(%(text)s, 0.055); border-radius: 12px; }
.look-card .card-head { padding: 12px 16px 2px 16px; }
.look-strip { min-height: 46px; border-radius: 12px 12px 0 0; }
.look-body { padding: 4px 16px 14px 16px; }

/* controls */
button, combobox button, entry {
    background-image: none; background-color: alpha(%(text)s, 0.08); color: %(text)s;
    border: none; border-radius: 8px; box-shadow: none; text-shadow: none;
    min-height: 30px; padding: 2px 12px; -gtk-icon-shadow: none;
}
entry { border: 1px solid transparent; }
button:hover, combobox button:hover { background-color: alpha(%(text)s, 0.14); }
button:active, combobox button:checked { background-color: alpha(%(text)s, 0.20); }
button.suggested-action { background-color: %(accent)s; color: %(on_accent)s; font-weight: 700; }
button.suggested-action:hover { background-color: %(accent2)s; }
button.suggested-action label { color: %(on_accent)s; }
button.pill { border-radius: 99px; }
button label, combobox button label, combobox cellview { color: %(text)s; }

/* spin button: number with round − / + buttons, as in libadwaita rows */
spinbutton { background: none; border: none; box-shadow: none; padding: 0; }
spinbutton entry { background: none; border: none; box-shadow: none; min-width: 32px; padding: 0 6px; font-weight: 600; }
spinbutton button { min-width: 28px; min-height: 28px; padding: 0; margin: 2px 0 2px 6px; border-radius: 99px;
                    background-color: alpha(%(text)s, 0.10); border: none; }
spinbutton button:hover { background-color: alpha(%(text)s, 0.18); }
spinbutton button:disabled { opacity: 0.4; }

menu, .popup, menuitem { background-color: %(surface)s; color: %(text)s; }
menu { border-radius: 10px; padding: 4px; }
menuitem { border-radius: 6px; padding: 6px 10px; }
menuitem:hover { background-color: alpha(%(text)s, 0.10); color: %(text)s; }
treeview.view { background-color: transparent; color: %(text)s; padding: 4px 6px; }
treeview.view:selected { background-color: alpha(%(accent)s, 0.25); color: %(text)s; }
treeview header button { background-color: transparent; color: %(muted)s; border: none; font-weight: 700; }
scale trough { background-color: alpha(%(text)s, 0.14); border: none; min-height: 4px; border-radius: 99px; }
scale highlight { background-color: %(accent)s; border-radius: 99px; }
scale slider { background-color: white; border: none; min-width: 18px; min-height: 18px; border-radius: 99px;
               box-shadow: 0 1px 3px alpha(black, 0.4); }
switch { background-image: none; background-color: alpha(%(text)s, 0.20); border: none; border-radius: 99px;
         min-width: 46px; min-height: 26px; }
switch:checked { background-color: %(accent)s; }
switch slider { background-image: none; background-color: white; border: none; border-radius: 99px;
                min-width: 22px; min-height: 22px; margin: 2px; box-shadow: 0 1px 3px alpha(black, 0.35); }
scrollbar { background-color: transparent; border: none; }
scrollbar slider { background-color: alpha(%(text)s, 0.18); border-radius: 99px; min-width: 6px; border: none; }
.mono { font-family: "JetBrainsMono Nerd Font", monospace; font-size: 11px; color: %(subtext)s; }
.dot { border-radius: 6px; min-width: 14px; min-height: 14px; }

/* toast */
.toast { background-color: alpha(%(surface2)s, 0.97); border: 1px solid alpha(%(text)s, 0.1); border-radius: 99px;
         padding: 8px 18px; margin: 14px; box-shadow: 0 8px 24px alpha(black, 0.4); }
.toast.ok { border-color: %(ok)s; } .toast.err { border-color: %(urgent)s; }
.toast-ok { color: %(ok)s; } .toast-err { color: %(urgent)s; }
"""


class Settings(Gtk.Window):
    def __init__(self, first: str = "looks") -> None:
        super().__init__(title="AetherOS Settings")
        self.set_default_size(1100, 720)
        self.set_wmclass("aether-settings", "AetherOS Settings")
        screen = self.get_screen()
        if screen.get_rgba_visual() and os.environ.get("WAYLAND_DISPLAY"):
            self.set_visual(screen.get_rgba_visual())   # let Hyprland's blur show through
        self.pal = cc.template_values(cc.resolve_palette(state())[0], state())
        prov = Gtk.CssProvider()
        prov.load_from_data((CSS % self.pal).encode())
        # Above USER priority so ~/.config/gtk-3.0/gtk.css can't flatten this window's look.
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), prov, Gtk.STYLE_PROVIDER_PRIORITY_USER + 1)

        # Flat header bar with the page name and a round close button.
        self.header = Gtk.HeaderBar(show_close_button=True, title="AetherOS Settings")
        self.header.set_decoration_layout(":close")
        self.set_titlebar(self.header)

        body = Gtk.Box()
        overlay = Gtk.Overlay()
        overlay.add(body)
        self.add(overlay)

        # ── sidebar: profile, search, navigation with colour tiles ──────
        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        side.get_style_context().add_class("sidebar")
        side.set_size_request(270, -1)
        st = state()
        prof = Gtk.Box(spacing=12)
        prof.get_style_context().add_class("profile")
        prof.pack_start(self.tile("󱓞", "accent", big=True), False, False, 0)
        pv = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER)
        n = Gtk.Label(label=os.environ.get("USER", "AetherOS"), xalign=0)
        n.get_style_context().add_class("profile-name")
        sub = Gtk.Label(label="Look: %s · %s mode" % (st.get("look", "default"), st.get("mode", "dark")), xalign=0)
        sub.get_style_context().add_class("profile-sub")
        pv.pack_start(n, False, False, 0)
        pv.pack_start(sub, False, False, 0)
        prof.pack_start(pv, True, True, 0)
        side.pack_start(prof, False, False, 0)
        search = Gtk.SearchEntry(placeholder_text="Search settings")
        search.get_style_context().add_class("side-search")
        side.pack_start(search, False, False, 0)
        self.nav = Gtk.ListBox()
        self.nav.get_style_context().add_class("sidebar")
        for key, glyph, name, desc in PAGES:
            row = Gtk.ListBoxRow()
            row.key = key
            row.words = (name + " " + desc).lower()
            hb = Gtk.Box(spacing=12)
            hb.pack_start(self.tile(glyph, PAGE_TINT[key]), False, False, 0)
            lab = Gtk.Label(label=name, xalign=0)
            lab.get_style_context().add_class("nav-label")
            hb.pack_start(lab, True, True, 0)
            row.add(hb)
            self.nav.add(row)
        self.nav.set_filter_func(lambda r: search.get_text().lower() in r.words)
        search.connect("search-changed", lambda _w: self.nav.invalidate_filter())
        self.nav.connect("row-selected", self.on_nav)
        side.pack_start(self.nav, True, True, 0)
        foot = Gtk.Label(label="Changes apply immediately · no root needed", xalign=0)
        foot.get_style_context().add_class("side-foot")
        side.pack_end(foot, False, False, 0)
        body.pack_start(side, False, False, 0)

        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.SLIDE_UP_DOWN, transition_duration=220)
        self.stack.get_style_context().add_class("main")
        body.pack_start(self.stack, True, True, 0)

        # ── toast for real results ──────────────────────────────────────
        self.toast = Gtk.Revealer(transition_type=Gtk.RevealerTransitionType.SLIDE_UP, transition_duration=200,
                                  halign=Gtk.Align.CENTER, valign=Gtk.Align.END)
        self.status = Gtk.Label(label="")
        tb = Gtk.Box()
        tb.get_style_context().add_class("toast")
        tb.pack_start(self.status, False, False, 0)
        self.toast_box = tb
        self.toast.add(tb)
        overlay.add_overlay(self.toast)
        self._toast_id = 0
        self.built: set[str] = set()
        for i, (key, *_r) in enumerate(PAGES):
            if key == first:
                self.nav.select_row(self.nav.get_row_at_index(i))
                break

    def tile(self, glyph: str, role: str, big: bool = False) -> Gtk.Label:
        t = Gtk.Label(label=glyph)
        t.get_style_context().add_class("tile")
        if big:
            t.get_style_context().add_class("big")
        col = role if role.startswith("#") else self.pal.get(role, self.pal["accent"])
        t.override_background_color(Gtk.StateFlags.NORMAL, self.rgba(col))
        t.override_color(Gtk.StateFlags.NORMAL, self.rgba("#ffffff" if role.startswith("#") else self.pal["on_accent"]))
        return t

    # ── plumbing ──────────────────────────────────────────────────────
    def on_nav(self, _lb, row) -> None:
        if row is None:
            return
        key = row.key
        if key not in self.built:
            self.stack.add_named(self.page(key), key)
            self.built.add(key)
            self.stack.show_all()
        self.stack.set_visible_child_name(key)

    def rebuild(self, key: str) -> None:
        child = self.stack.get_child_by_name(key)
        if child:
            self.stack.remove(child)
        self.built.discard(key)
        self.stack.add_named(self.page(key), key)
        self.built.add(key)
        self.stack.show_all()
        self.stack.set_visible_child_name(key)

    def act(self, label: str, *cmd: str, refresh: str | None = None) -> None:
        """Run a helper off the UI thread and report its real result."""
        self.say("… " + label, None)

        def work() -> None:
            rc, out = run(*cmd)
            last = (out.splitlines() or [""])[-1][:160]
            GLib.idle_add(self.say, ("✓ " if rc == 0 else "✗ ") + label + (" — " + last if last else ""), rc == 0)
            if refresh:
                GLib.idle_add(self.rebuild, refresh)
        threading.Thread(target=work, daemon=True).start()

    def say(self, text: str, ok: bool | None) -> bool:
        self.status.set_text(text)
        for w, cls in ((self.toast_box, ("ok", "err")), (self.status, ("toast-ok", "toast-err"))):
            ctx = w.get_style_context()
            for c in cls:
                ctx.remove_class(c)
            if ok is not None:
                ctx.add_class(cls[0] if ok else cls[1])
        self.toast.set_reveal_child(True)
        self._toast_id += 1
        tid = self._toast_id
        if ok is not None:
            GLib.timeout_add(4500, lambda: (tid == self._toast_id and self.toast.set_reveal_child(False)) and False)
        return False

    def frame(self, key: str) -> tuple[Gtk.ScrolledWindow, Gtk.Box]:
        _, glyph, name, desc = next(p for p in PAGES if p[0] == key)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18, margin_top=24, margin_bottom=70,
                      margin_start=40, margin_end=40)
        head = Gtk.Box(spacing=16)
        head.pack_start(self.tile(glyph, PAGE_TINT[key], big=True), False, False, 0)
        tv = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER)
        t = Gtk.Label(label=name, xalign=0)
        t.get_style_context().add_class("title")
        d = Gtk.Label(label=desc, xalign=0)
        d.get_style_context().add_class("subtitle")
        tv.pack_start(t, False, False, 0)
        tv.pack_start(d, False, False, 0)
        head.pack_start(tv, True, True, 0)
        box.pack_start(head, False, False, 4)
        sw = Gtk.ScrolledWindow()
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        sw.add(box)
        return sw, box

    def card(self, title: str, subtitle: str = "") -> tuple[Gtk.Box, Gtk.Box]:
        c = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        c.get_style_context().add_class("card")
        hv = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        hv.get_style_context().add_class("card-head")
        head = Gtk.Box(spacing=10)
        tl = Gtk.Label(label=title, xalign=0)
        tl.get_style_context().add_class("card-title")
        head.pack_start(tl, True, True, 0)
        hv.pack_start(head, False, False, 0)
        if subtitle:
            s_ = Gtk.Label(label=subtitle, xalign=0, wrap=True)
            s_.get_style_context().add_class("card-sub")
            hv.pack_start(s_, False, False, 2)
        c.pack_start(hv, False, False, 0)
        return c, head

    def row(self, parent: Gtk.Box, label: str, widget: Gtk.Widget, hint: str = "") -> None:
        hb = Gtk.Box(spacing=12)
        hb.get_style_context().add_class("setting-row")
        v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER)
        lab = Gtk.Label(label=label, xalign=0)
        lab.get_style_context().add_class("row-label")
        v.pack_start(lab, False, False, 0)
        if hint:
            h = Gtk.Label(label=hint, xalign=0, wrap=True)
            h.get_style_context().add_class("muted")
            v.pack_start(h, False, False, 0)
        hb.pack_start(v, True, True, 0)
        widget.set_valign(Gtk.Align.CENTER)
        hb.pack_start(widget, False, False, 0)
        parent.pack_start(hb, False, False, 0)

    def padded(self, widget: Gtk.Widget) -> Gtk.Box:
        """Wrap free content placed in a card so it lines up with its rows."""
        b = Gtk.Box()
        b.get_style_context().add_class("setting-row")
        b.pack_start(widget, True, True, 0)
        return b

    def combo(self, items: list[str], current: str, on_change) -> Gtk.ComboBoxText:
        cb = Gtk.ComboBoxText()
        for it in items:
            cb.append(it, it)
        if current in items:
            cb.set_active_id(current)
        cb.connect("changed", lambda w: w.get_active_id() and on_change(w.get_active_id()))
        return cb

    def switch(self, active: bool, on_change) -> Gtk.Switch:
        sw = Gtk.Switch(active=active, valign=Gtk.Align.CENTER)
        sw.connect("notify::active", lambda w, _p: on_change(w.get_active()))
        return sw

    def button(self, label: str, cb, suggested: bool = False) -> Gtk.Button:
        b = Gtk.Button(label=label)
        if suggested:
            b.get_style_context().add_class("suggested-action")
        b.connect("clicked", lambda _b: cb())
        return b

    # ── pages ─────────────────────────────────────────────────────────
    def page(self, key: str) -> Gtk.Widget:
        return getattr(self, "page_" + key)()

    def page_looks(self) -> Gtk.Widget:
        sw, box = self.frame("looks")
        cur = state().get("look", "")
        sec = Gtk.Label(label="Choose a look", xalign=0)
        sec.get_style_context().add_class("section")
        box.pack_start(sec, False, False, 0)
        flow = Gtk.FlowBox(max_children_per_line=3, min_children_per_line=2, selection_mode=Gtk.SelectionMode.NONE,
                           column_spacing=16, row_spacing=16, homogeneous=True)
        for line in (REPO / "config" / "aether-looks.tsv").read_text(encoding="utf-8").splitlines():
            if not line.strip() or line.startswith("#"):
                continue
            f = line.split("\t")
            name, palette, lock, desc = f[0], f[4], f[9], f[10]
            title, _, rest = desc.partition(" — ")
            pal = cc.preset_palette(palette) if palette in cc.PRESETS else self.pal
            c = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            c.get_style_context().add_class("card")
            c.get_style_context().add_class("look-card")
            # Colour strip: the look's own palette (or yours, for wallpaper-based looks).
            strip = Gtk.Box(spacing=0)
            strip.get_style_context().add_class("look-strip")
            for role in ("background", "surface2", "accent", "accent2", "urgent"):
                e = Gtk.EventBox()
                e.set_size_request(-1, 46)
                e.override_background_color(Gtk.StateFlags.NORMAL, self.rgba(pal[role]))
                strip.pack_start(e, True, True, 0)
            c.pack_start(strip, False, False, 0)
            head = Gtk.Box(spacing=8)
            head.get_style_context().add_class("card-head")
            tl = Gtk.Label(label=title, xalign=0)
            tl.get_style_context().add_class("card-title")
            head.pack_start(tl, True, True, 0)
            if name == cur:
                lab = Gtk.Label(label="In use")
                lab.get_style_context().add_class("current")
                head.pack_end(lab, False, False, 0)
            c.pack_start(head, False, False, 0)
            body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
            body.get_style_context().add_class("look-body")
            d = Gtk.Label(label=rest, xalign=0, wrap=True, max_width_chars=34)
            d.get_style_context().add_class("muted")
            body.pack_start(d, False, False, 0)
            meta = Gtk.Label(label="󰕮 %s   󰏘 %s   󰌾 %s" % (f[1], palette, lock), xalign=0)
            meta.get_style_context().add_class("mono")
            body.pack_start(meta, False, False, 0)
            btn = self.button("Re-apply" if name == cur else "Apply",
                              lambda n=name: self.act("Look " + n, "aether-look", "apply", n, refresh="looks"),
                              suggested=name != cur)
            btn.set_halign(Gtk.Align.START)
            body.pack_end(btn, False, False, 0)
            c.pack_start(body, True, True, 0)
            flow.add(c)
        box.pack_start(flow, False, False, 0)
        return sw

    def page_appearance(self) -> Gtk.Widget:
        sw, box = self.frame("appearance")
        st = state()
        c, _ = self.card("Colours", "One palette themes the bar, launcher, notifications, lock screen, terminal and borders.")
        self.row(c, "Dark mode", self.switch(st.get("mode", "dark") == "dark",
                 lambda on: self.act("Mode", "aether-colors", "mode", "dark" if on else "light", refresh="appearance")))
        sources = ["image", "wallust"] + ["preset:" + p for p in sorted(cc.PRESETS)]
        cur = st.get("source", "image") if st.get("source") != "preset" else "preset:" + st.get("preset", "")
        self.row(c, "Colours come from", self.combo(sources, cur, lambda v: self.act(
            "Palette " + v, "aether-colors", "source", *(["preset", v[7:]] if v.startswith("preset:") else [v]), refresh="appearance")),
            "image = from your wallpaper; wallust needs `cargo install wallust`")
        sw_box = Gtk.Box(spacing=6)
        for k in ("background", "surface2", "accent", "accent2", "urgent", "ok", "warn", "text"):
            e = Gtk.EventBox()
            e.get_style_context().add_class("dot")
            e.set_size_request(22, 22)
            e.override_background_color(Gtk.StateFlags.NORMAL, self.rgba(self.pal[k]))
            e.set_tooltip_text("%s %s" % (k, self.pal[k]))
            sw_box.pack_start(e, False, False, 0)
        self.row(c, "Current palette", sw_box)
        box.pack_start(c, False, False, 0)
        cg, _ = self.card("Frosted glass", "Blur behind panels, menus and windows. Browsers, video and games stay opaque.")
        self.row(cg, "Glass", self.combo(["off", "subtle", "acrylic", "deep"], st.get("glass", "acrylic"),
                 lambda v: self.act("Glass " + v, "aether-glass", v)), "acrylic is the default; deep is strongest")
        box.pack_start(cg, False, False, 0)
        c2, _ = self.card("Visual effects", "Hyprland blur, shadows and animations (aether performance hyprland).")
        cur_prof = "balanced"
        rc, js = run("aether", "performance", "status", "--json", timeout=20)
        if rc == 0:
            try:
                import json
                cur_prof = json.loads(js).get("hyprlandProfile", "balanced").split()[0]
            except ValueError:
                pass
        self.row(c2, "Profile", self.combo(["quality", "balanced", "low-latency", "battery"], cur_prof,
                 lambda v: self.act("Visual profile " + v, "aether", "performance", "hyprland", v)),
                 "battery and low-latency switch effects off")
        box.pack_start(c2, False, False, 0)
        return sw

    def page_display(self) -> Gtk.Widget:
        from aether import displays
        from aether.util import default_context
        sw, box = self.frame("display")
        mons = [m for m in (displays.monitors(default_context()) or []) if not m["disabled"]]
        c, _ = self.card("Display scale", "Makes everything on a screen bigger or smaller. A new scale has to be kept "
                         "within 15 seconds, otherwise it switches back by itself.")
        if not mons:
            self.row(c, "Displays", Gtk.Label(label="Hyprland is not running"))
        for m in mons:
            # Only scales that divide the resolution evenly (Hyprland rejects the rest).
            opts = [x for x in displays.SCALES
                    if abs(m["width"] / x - round(m["width"] / x)) < 0.01 and abs(m["height"] / x - round(m["height"] / x)) < 0.01]
            cur = min(opts, key=lambda x: abs(x - m["scale"]))
            cb = Gtk.ComboBoxText()
            for x in opts:
                cb.append("%g" % x, "%d%%" % round(x * 100))
            cb.set_active_id("%g" % cur)
            cb.connect("changed", lambda w, m=m: w.get_active_id() and float(w.get_active_id()) != m["scale"]
                       and self.apply_scale(m, float(w.get_active_id())))
            name = "Built-in display" if m["name"].startswith(("eDP", "LVDS")) else m["description"] or m["name"]
            self.row(c, name, cb, "%s · %d×%d at %.0f Hz · looks like %d×%d" % (
                m["name"], m["width"], m["height"], m["refresh"], round(m["width"] / cur), round(m["height"] / cur)))
        box.pack_start(c, False, False, 0)

        cz, _ = self.card("Screen zoom", "Magnifies the whole screen around the pointer, for reading small text "
                          "or presenting. Keys: Super+Ctrl+= zoom in · Super+Ctrl+− zoom out · Super+Ctrl+0 reset.")
        _, cur_zoom = run("aether-zoom", "get", timeout=5)
        try:
            zv = float(cur_zoom.splitlines()[-1])
        except (ValueError, IndexError):
            zv = 1.0
        spin = Gtk.SpinButton.new_with_range(1.0, 4.0, 0.25)
        spin.set_digits(2)
        spin.set_value(zv)
        spin.connect("value-changed", lambda w: run("aether-zoom", "set", "%.2f" % w.get_value(), timeout=5))
        self.row(cz, "Zoom level", spin, "1.00 = normal size")
        presets = Gtk.Box(spacing=6)
        for label, v in (("Off", 1.0), ("150%", 1.5), ("200%", 2.0), ("300%", 3.0)):
            presets.pack_start(self.button(label, lambda v=v: spin.set_value(v)), False, False, 0)
        self.row(cz, "Quick zoom", presets)
        box.pack_start(cz, False, False, 0)
        return sw

    def apply_scale(self, mon: dict, scale: float) -> None:
        """Apply a monitor scale, then ask to keep it; it reverts after 15 s unless kept."""
        from aether import displays
        from aether.util import default_context
        ctx = default_context()
        # Keep the current mode and position; only the scale changes.
        mode = min((x for x in mon["modes"] if x.startswith("%dx%d@" % (mon["width"], mon["height"]))),
                   key=lambda x: abs(float(displays.MODE_RE.match(x).group(3)) - mon["refresh"]), default="preferred")
        res = displays.apply(ctx, mon["name"], mode, "%dx%d" % (mon["x"], mon["y"]), scale)
        if not res.get("ok"):
            self.say("✗ " + "; ".join(res.get("problems", ["could not change the scale"])), False)
            GLib.idle_add(self.rebuild, "display")
            return
        secs = [res.get("confirmWithin", 15)]
        dlg = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.QUESTION,
                                text="Keep this display scale?")
        dlg.add_buttons("Revert", Gtk.ResponseType.CANCEL, "Keep", Gtk.ResponseType.OK)
        dlg.get_widget_for_response(Gtk.ResponseType.OK).get_style_context().add_class("suggested-action")

        def tick() -> bool:
            secs[0] -= 1
            if secs[0] <= 0:
                dlg.response(Gtk.ResponseType.CANCEL)
                return False
            dlg.format_secondary_text("%d%% — switching back in %d s." % (round(scale * 100), secs[0]))
            return True
        dlg.format_secondary_text("%d%% — switching back in %d s." % (round(scale * 100), secs[0]))
        tid = GLib.timeout_add_seconds(1, tick)
        keep = dlg.run() == Gtk.ResponseType.OK
        if secs[0] > 0:
            GLib.source_remove(tid)
        dlg.destroy()
        if keep and displays.confirm():
            self.say("✓ Display scale %d%%" % round(scale * 100), True)
        else:
            displays.revert(ctx)
            self.say("↺ Display scale reverted", True)
        GLib.idle_add(self.rebuild, "display")

    @staticmethod
    def rgba(hexcol: str) -> Gdk.RGBA:
        c = Gdk.RGBA()
        c.parse(hexcol)
        return c

    def page_controls(self) -> Gtk.Widget:
        from aether import controls as ctl
        from aether import control_center as ccp
        sw, box = self.frame("controls")
        ids = ctl.load_layout()
        cols = Gtk.Box(spacing=18)
        # Gallery: every control by category, with Add / Remove / move.
        gal = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        search = Gtk.SearchEntry(placeholder_text="Search controls")
        gal.pack_start(search, False, False, 0)
        rows = []
        cats: dict[str, list] = {}
        for c in ctl.CONTROLS.values():
            cats.setdefault(c.category, []).append(c)
        for cat, items in cats.items():
            card, _ = self.card(cat)
            for c in items:
                hb = Gtk.Box(spacing=10)
                hb.get_style_context().add_class("setting-row")
                g = Gtk.Label(label=c.glyph)
                g.get_style_context().add_class("mono")
                hb.pack_start(g, False, False, 0)
                v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
                v.pack_start(Gtk.Label(label=c.name, xalign=0), False, False, 0)
                sub = Gtk.Label(label=("%s tile" % c.size) + ("" if c.available() else " · needs " + ", ".join(c.needs)),
                                xalign=0, wrap=True, max_width_chars=26)
                sub.get_style_context().add_class("muted")
                v.pack_start(sub, False, False, 0)
                hb.pack_start(v, True, True, 0)
                if c.cid in ids:
                    for lab, fn in (("↑", lambda c=c: ctl.move(c.cid, -1)), ("↓", lambda c=c: ctl.move(c.cid, 1)),
                                    ("Remove", lambda c=c: ctl.remove(c.cid))):
                        hb.pack_start(self.button(lab, lambda fn=fn, n=c.name: self.edit_controls(fn, n)), False, False, 0)
                else:
                    hb.pack_start(self.button("+ Add", lambda c=c: self.edit_controls(lambda: ctl.add(c.cid), c.name), True),
                                  False, False, 0)
                card.pack_start(hb, False, False, 0)
                rows.append((hb, (c.name + " " + cat).lower()))
            gal.pack_start(card, False, False, 0)
        search.connect("search-changed", lambda _w: [r.set_visible(search.get_text().lower() in t) for r, t in rows])
        foot = Gtk.Box(spacing=8)
        foot.pack_start(self.button("Reset to default", lambda: self.edit_controls(ctl.reset, "Default layout")), False, False, 0)
        foot.pack_start(self.button("Open Control Centre", lambda: self.act("Control Centre", "aether-control"), True), False, False, 0)
        gal.pack_start(foot, False, False, 0)
        cols.pack_start(gal, True, True, 0)
        # Live preview: the real panel, built from the same layout.
        pv = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        lab = Gtk.Label(label="Preview", xalign=0)
        lab.get_style_context().add_class("section")
        pv.pack_start(lab, False, False, 0)
        ccp.load_css(ccp.glass_alpha())
        panel = ccp.Panel(ids, interactive=False, cell=70)
        panel.refresh()
        pv.pack_start(panel, False, False, 0)
        cols.pack_start(pv, False, False, 0)
        box.pack_start(cols, False, False, 0)
        return sw

    def edit_controls(self, fn, label: str) -> None:
        try:
            fn()
            self.say("✓ Control Centre: " + label, True)
        except OSError as e:
            self.say("✗ " + str(e), False)
        self.rebuild("controls")

    def page_bar(self) -> Gtk.Widget:
        sw, box = self.frame("bar")
        st = state()
        _, layouts = run("aether-waybar", "layouts")
        _, styles = run("aether-waybar", "styles")
        c, _ = self.card("Waybar", "Layouts choose modules and positions; styles choose the look. A look sets both.")
        self.row(c, "Layout", self.combo(layouts.split(), st.get("waybar_layout", "default"),
                 lambda v: self.act("Layout " + v, "aether-waybar", "layout", v)))
        self.row(c, "Style", self.combo(styles.split(), st.get("waybar_style", "pills"),
                 lambda v: self.act("Style " + v, "aether-waybar", "style", v)))
        hb = Gtk.Box(spacing=8)
        hb.pack_start(self.button("Restart Waybar", lambda: self.act("Restart", "aether-waybar", "restart")), False, False, 0)
        hb.pack_start(self.button("Hide / show", lambda: self.act("Toggle", "aether-waybar", "toggle")), False, False, 0)
        c.pack_start(self.padded(hb), False, False, 0)
        box.pack_start(c, False, False, 0)
        return sw

    def page_island(self) -> Gtk.Widget:
        sw, box = self.frame("island")
        st = state()
        cal = "khal" if shutil.which("khal") else "calcurse" if shutil.which("calcurse") else None
        c, _ = self.card("Behaviour", "Idle it shows the time; while music plays it opens into a card; volume and "
                         "brightness keys show a level bar for two seconds. Used by the home look.")

        def setter(k, v):
            set_state(k, v)
            subprocess.run(["pkill", "-RTMIN+12", "-x", "waybar"], check=False)
            self.say("✓ %s = %s" % (k, v), True)
        def island_on(on):
            # Off: no island, and Waybar's date and time move back to the centre
            # (scripts/island-clock.sh follows this key).
            setter("island", "on" if on else "off")
            run(os.path.expanduser("~/.config/waybar/scripts/dynamic-island.sh"), "start" if on else "stop")
        self.row(c, "Dynamic Island", self.switch(st.get("island", "on") != "off", island_on),
                 "on: the island takes the centre and the date and time sit on the right · off: date and time in the centre")
        self.row(c, "Only show while something is happening", self.switch(st.get("island_mode", "auto") != "always",
                 lambda on: (setter("island_mode", "auto" if on else "always"), run("aether-island", "sync"))),
                 "on: appears for music and volume/brightness, then gets out of your way · off: always shows the time")
        self.row(c, "Show volume and brightness", self.switch(st.get("island_osd", "on") == "on",
                 lambda on: setter("island_osd", "on" if on else "off")), "otherwise SwayNC shows them")
        self.row(c, "Upcoming events beside the music", self.switch(st.get("island_events", "auto") != "off",
                 lambda on: setter("island_events", "auto" if on else "off")),
                 "from %s" % cal if cal else "no calendar found (install khal or calcurse) — the date is shown instead")
        self.row(c, "24-hour clock", self.switch(st.get("island_clock", "24") == "24",
                 lambda on: setter("island_clock", "24" if on else "12")))
        box.pack_start(c, False, False, 0)
        if st.get("look") != "home":
            c2, _ = self.card("Not active", "The island belongs to the home look.")
            b = self.button("Use the home look", lambda: self.act("Look home", "aether-look", "apply", "home", refresh="island"), True)
            b.set_halign(Gtk.Align.START)
            c2.pack_start(self.padded(b), False, False, 0)
            box.pack_start(c2, False, False, 0)
        return sw

    def page_dock(self) -> Gtk.Widget:
        sw, box = self.frame("dock")
        st = dockmod.load_state()
        c, _ = self.card("Pinned apps", "Real icons from your icon theme; a click runs gtk-launch. The grid button opens Launchpad.")
        for app in st["pins"]:
            df = dockmod.desktop_file(app)
            entry = dockmod.read_entry(df) if df else {}
            hb = Gtk.Box(spacing=10)
            hb.get_style_context().add_class("setting-row")
            icon = dockmod.find_icon(entry.get("Icon", "")) if entry else None
            img = Gtk.Image()
            if icon:
                try:
                    img.set_from_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_size(icon, 32, 32))
                except GLib.Error:
                    pass
            hb.pack_start(img, False, False, 0)
            hb.pack_start(Gtk.Label(label="%s  (%s)" % (entry.get("Name", app), app) if df else "%s — not installed" % app,
                                    xalign=0), True, True, 0)
            for lab, args in (("←", ("move", app, "left")), ("→", ("move", app, "right")), ("Remove", ("remove", app))):
                hb.pack_start(self.button(lab, lambda a=args: self.act("Dock " + " ".join(a), "aether-dock", *a, refresh="dock")),
                              False, False, 0)
            c.pack_start(hb, False, False, 0)
        add = Gtk.Box(spacing=8)
        apps = dockmod.installed_apps()
        cb = Gtk.ComboBoxText()
        for app_id, name in apps:
            if app_id not in st["pins"]:
                cb.append(app_id, "%s  (%s)" % (name, app_id))
        add.pack_start(cb, True, True, 0)
        add.pack_start(self.button("Pin", lambda: cb.get_active_id() and self.act(
            "Pin " + cb.get_active_id(), "aether-dock", "add", cb.get_active_id(), refresh="dock"), True), False, False, 0)
        c.pack_start(self.padded(add), False, False, 0)
        box.pack_start(c, False, False, 0)
        c2, _ = self.card("Size")
        scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 24, 96, 4)
        scale.set_value(st["size"])
        scale.set_size_request(260, -1)
        scale.connect("button-release-event", lambda w, _e: self.act("Icon size", "aether-dock", "size", str(int(w.get_value()))))
        self.row(c2, "Icon size (px)", scale)
        box.pack_start(c2, False, False, 0)
        return sw

    def page_lock(self) -> Gtk.Widget:
        sw, box = self.frame("lock")
        st = state()
        _, out = run("aether-lock", "designs")
        designs = [ln.split(None, 1) for ln in out.splitlines() if ln.strip()]
        c, _ = self.card("Design", "Unlocking always uses Hyprlock's PAM password check, whatever the design.")
        for name, desc in ((d[0], d[1] if len(d) > 1 else "") for d in designs):
            hb = Gtk.Box(spacing=10)
            hb.get_style_context().add_class("setting-row")
            lab = Gtk.Label(label=("● " if name == st.get("lock_design", "signature") else "   ") + name, xalign=0)
            if name == st.get("lock_design", "signature"):
                lab.get_style_context().add_class("current")
            lab.set_size_request(120, -1)
            hb.pack_start(lab, False, False, 0)
            d = Gtk.Label(label=desc, xalign=0, wrap=True)
            d.get_style_context().add_class("muted")
            hb.pack_start(d, True, True, 0)
            hb.pack_start(self.button("Use", lambda n=name: self.act("Lock design " + n, "aether-lock", "design", n, refresh="lock")),
                          False, False, 0)
            c.pack_start(hb, False, False, 0)
        b = self.button("Lock now to look at it", lambda: self.act("Lock", "aether-lock", "try"), True)
        b.set_halign(Gtk.Align.START)
        c.pack_start(self.padded(b), False, False, 0)
        box.pack_start(c, False, False, 0)
        return sw

    def page_wallpaper(self) -> Gtk.Widget:
        sw, box = self.frame("wallpaper")
        st = state()
        c, _ = self.card("Current wallpaper", os.path.basename(st.get("wallpaper", "")) or "none yet")
        rc, thumb = run("aether-wall", "thumb")
        if rc == 0 and thumb and os.path.isfile(thumb.splitlines()[-1]):
            try:
                img = Gtk.Image.new_from_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_size(thumb.splitlines()[-1], 480, 300))
                img.set_halign(Gtk.Align.START)
                c.pack_start(self.padded(img), False, False, 0)
            except GLib.Error:
                pass
        hb = Gtk.Box(spacing=8)
        hb.pack_start(self.button("Open gallery", lambda: self.act("Gallery", "aether-wall", "select"), True), False, False, 0)
        hb.pack_start(self.button("Random", lambda: self.act("Random wallpaper", "aether-wall", "random", refresh="wallpaper")), False, False, 0)
        hb.pack_start(self.button("Next", lambda: self.act("Next wallpaper", "aether-wall", "next", refresh="wallpaper")), False, False, 0)
        c.pack_start(self.padded(hb), False, False, 0)
        box.pack_start(c, False, False, 0)
        c2, _ = self.card("Slideshow")
        _, status = run("aether-wall", "slideshow", "status")
        spin = Gtk.SpinButton.new_with_range(1, 240, 1)
        spin.set_value(int(st.get("slideshow_minutes", "15") or 15))
        self.row(c2, "Change every (minutes)", spin)
        self.row(c2, "Slideshow on", self.switch(status.startswith("running"), lambda on: (
            set_state("slideshow_minutes", str(int(spin.get_value()))),
            self.act("Slideshow", "aether-wall", "slideshow", *(["start", str(int(spin.get_value()))] if on else ["stop"])))))
        box.pack_start(c2, False, False, 0)
        return sw

    def page_keys(self) -> Gtk.Widget:
        sw, box = self.frame("keys")
        _, out = run("aether-bindings", "list")
        search = Gtk.SearchEntry(placeholder_text="Search keys, actions or categories…")
        box.pack_start(search, False, False, 0)
        store = Gtk.ListStore(str, str, str)
        cat = ""
        for line in out.splitlines():
            if not line.strip():
                continue
            if not line.startswith("  "):
                cat = line.strip()
                continue
            parts = line.strip().split("  ", 1)
            store.append([parts[0].strip(), (parts[1] if len(parts) > 1 else "").strip(), cat])
        filt = store.filter_new()
        filt.set_visible_func(lambda m, it, _d: search.get_text().lower() in " ".join(m[it]).lower())
        search.connect("search-changed", lambda _w: filt.refilter())
        tv = Gtk.TreeView(model=filt)
        for i, title in enumerate(("Keys", "Action", "Category")):
            col = Gtk.TreeViewColumn(title, Gtk.CellRendererText(), text=i)
            col.set_resizable(True)
            tv.append_column(col)
        tv.set_size_request(-1, 380)
        frame = Gtk.ScrolledWindow()
        frame.set_min_content_height(360)
        frame.add(tv)
        kc, _ = self.card("All shortcuts", "Read from the Hyprland files themselves, so the list is always current.")
        kc.pack_start(self.padded(frame), True, True, 0)
        box.pack_start(kc, True, True, 0)
        res = Gtk.Label(xalign=0, wrap=True)
        res.get_style_context().add_class("mono")

        def check() -> None:
            rc, o = run("aether-bindings", "check")
            res.set_text(o)
            self.say(("✓ " if rc == 0 else "✗ ") + (o.splitlines() or [""])[-1], rc == 0)
        cb_ = self.button("Check for conflicts and missing programs", check, True)
        cb_.set_halign(Gtk.Align.START)
        box.pack_start(cb_, False, False, 0)
        box.pack_start(res, False, False, 0)
        return sw

    def page_system(self) -> Gtk.Widget:
        sw, box = self.frame("system")
        c, _ = self.card("Interface", "classic: Waybar, Rofi, SwayNC, dock and island. aether: the Quickshell shell.")
        _, cur = run("aether-interface", "status")
        self.row(c, "Active interface", self.combo(["classic", "aether"], cur.strip(),
                 lambda v: self.act("Interface " + v, "aether-interface", "set", v)))
        box.pack_start(c, False, False, 0)
        ct, _ = self.card("Terminal", "The shell a new terminal opens (Super+Return). "
                          "Super+Alt+Return opens any of them once. Your login shell is not changed.")
        _, sh = run("aether-terminal", "--get-shell")
        self.row(ct, "Default shell", self.combo(["zsh", "bash", "tmux", "meridian"], sh.strip() or "zsh",
                 lambda v: self.act("Default shell " + v, "aether-terminal", "--set-shell", v)))
        box.pack_start(ct, False, False, 0)
        c2, _ = self.card("Health check", "Programs, fonts and generated files the classic interface needs.")
        out = Gtk.Label(xalign=0, wrap=True, selectable=True)
        out.get_style_context().add_class("mono")

        def doctor() -> None:
            rc, o = run("aether-interface", "doctor")
            import re
            out.set_text(re.sub(r"\x1b\[[0-9;]*m", "", o))
            self.say("✓ No blocking problems" if rc == 0 else "✗ Some required parts are missing — see the list", rc == 0)
        b = self.button("Run health check", doctor, True)
        b.set_halign(Gtk.Align.START)
        c2.pack_start(self.padded(b), False, False, 0)
        c2.pack_start(self.padded(out), False, False, 0)
        box.pack_start(c2, False, False, 0)
        c3, _ = self.card("About")
        uname = os.uname()
        osr = ""
        try:
            osr = dict(ln.split("=", 1) for ln in Path("/etc/os-release").read_text().splitlines() if "=" in ln).get(
                "PRETTY_NAME", "").strip('"')
        except OSError:
            pass
        hypr = run("Hyprland", "--version", timeout=5)[1].splitlines()[:1] if shutil.which("Hyprland") else ["not installed"]
        ver = (REPO / "VERSION").read_text().strip() if (REPO / "VERSION").exists() else "dev"
        for k, v in (("AetherOS", ver), ("System", osr or "unknown"), ("Kernel", uname.release),
                     ("Hyprland", (hypr or ["unknown"])[0]), ("Session", os.environ.get("XDG_SESSION_TYPE", "unknown"))):
            self.row(c3, k, Gtk.Label(label=v, selectable=True))
        box.pack_start(c3, False, False, 0)
        return sw


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    first = args[0] if args and args[0] in [p[0] for p in PAGES] else "looks"
    if args and args[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0
    win = Settings(first)
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    GLib.idle_add(win.nav.grab_focus)
    Gtk.main()
    return 0
