"""AetherOS keyboard-shortcut viewer (GTK 3) — Super+H in the classic interface.

Reads the Hyprland files through aether.bindings (the shared keybinds plus the
active interface's), so it always shows the keys that are really configured.
Shortcuts with a "#: description" are shown, grouped by section; type to
filter, Escape closes.
"""

from __future__ import annotations

import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gtk  # noqa: E402

from aether import bindings  # noqa: E402
from aether import classic_colors as cc  # noqa: E402

CSS = """
* { font-family: "Inter", "Cantarell", "Noto Sans", sans-serif; }
window { background-color: alpha(%(background)s, 0.97); color: %(text)s; }
.head { padding: 22px 28px 6px 28px; }
.title { font-size: 26px; font-weight: 800; letter-spacing: -0.5px; }
.sub { color: %(muted)s; font-size: 12px; }
entry { background-image: none; background-color: alpha(%(text)s, 0.06); color: %(text)s; border: 1px solid alpha(%(text)s, 0.08);
        border-radius: 12px; min-height: 36px; caret-color: %(accent)s; }
entry:focus { border-color: alpha(%(accent)s, 0.55); box-shadow: 0 0 0 2px alpha(%(accent)s, 0.18); }
.cat { background-color: alpha(%(surface)s, 0.85); border: 1px solid alpha(%(text)s, 0.07); border-radius: 18px; padding: 12px 14px; }
.cat-title { font-weight: 800; font-size: 13px; color: %(accent)s; margin-bottom: 6px; }
.kb-row { padding: 3px 0; }
.desc { font-size: 12px; color: %(subtext)s; }
.cap { font-family: "JetBrainsMono Nerd Font", monospace; font-size: 11px; font-weight: 700; color: %(text)s;
       background-color: alpha(%(text)s, 0.08); border: 1px solid alpha(%(text)s, 0.14); border-bottom-width: 2px;
       border-radius: 7px; padding: 1px 7px; min-width: 14px; }
.cap.mod { color: %(accent)s; }
.plus { color: %(muted)s; font-size: 10px; }
scrollbar slider { background-color: alpha(%(text)s, 0.18); border-radius: 99px; min-width: 6px; }
"""

KEY_NAMES = {"Return": "Enter", "grave": "`", "comma": ",", "period": ".", "slash": "/", "space": "Space",
             "Escape": "Esc", "Print": "PrtSc", "mouse:272": "LMB", "mouse:273": "RMB", "mouse_down": "Wheel↓",
             "mouse_up": "Wheel↑", "left": "←", "right": "→", "up": "↑", "down": "↓", "Delete": "Del", "Tab": "Tab"}


def keycaps(combo: str) -> Gtk.Box:
    box = Gtk.Box(spacing=3, valign=Gtk.Align.CENTER)
    parts = combo.split(" + ")
    for i, p in enumerate(parts):
        if p.startswith("XF86"):
            p = p[4:]
        cap = Gtk.Label(label=KEY_NAMES.get(p, p))
        cap.get_style_context().add_class("cap")
        if i < len(parts) - 1:
            cap.get_style_context().add_class("mod")
        box.pack_start(cap, False, False, 0)
        if i < len(parts) - 1:
            plus = Gtk.Label(label="+")
            plus.get_style_context().add_class("plus")
            box.pack_start(plus, False, False, 0)
    return box


class Keys(Gtk.Window):
    def __init__(self) -> None:
        super().__init__(title="Keyboard shortcuts")
        self.set_wmclass("aether-keys", "AetherOS Keys")
        self.set_default_size(1180, 760)
        pal = cc.resolve_palette(cc.read_state())[0]
        prov = Gtk.CssProvider()
        prov.load_from_data((CSS % pal).encode())
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), prov, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.connect("key-press-event", lambda _w, e: e.keyval == Gdk.KEY_Escape and self.close())

        binds, _ = bindings.parse(bindings.sources())
        cats: dict[str, list] = {}
        for b in binds:
            if b.desc:
                cats.setdefault(b.category, []).append(b)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        head = Gtk.Box(spacing=16)
        head.get_style_context().add_class("head")
        tv = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        t = Gtk.Label(label="Keyboard shortcuts", xalign=0)
        t.get_style_context().add_class("title")
        s = Gtk.Label(label="%d shortcuts · %s interface · Esc to close · edit them in ~/.config/hypr"
                      % (sum(len(v) for v in cats.values()), bindings.active_interface()), xalign=0)
        s.get_style_context().add_class("sub")
        tv.pack_start(t, False, False, 0)
        tv.pack_start(s, False, False, 0)
        head.pack_start(tv, True, True, 0)
        self.search = Gtk.SearchEntry(placeholder_text="Filter — key, action or category", width_chars=36, valign=Gtk.Align.CENTER)
        head.pack_end(self.search, False, False, 0)
        outer.pack_start(head, False, False, 0)

        self.flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, min_children_per_line=2, max_children_per_line=3,
                                column_spacing=14, row_spacing=14, margin=24, homogeneous=False, valign=Gtk.Align.START)
        self.rows: list[tuple[Gtk.Widget, str, Gtk.Widget]] = []
        for cat, items in cats.items():
            card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            card.get_style_context().add_class("cat")
            ct = Gtk.Label(label=cat, xalign=0)
            ct.get_style_context().add_class("cat-title")
            card.pack_start(ct, False, False, 0)
            for b in items:
                r = Gtk.Box(spacing=12)
                r.get_style_context().add_class("kb-row")
                d = Gtk.Label(label=b.desc, xalign=0, ellipsize=3)
                d.get_style_context().add_class("desc")
                r.pack_start(d, True, True, 0)
                r.pack_end(keycaps(b.combo), False, False, 0)
                card.pack_start(r, False, False, 0)
                self.rows.append((r, (b.combo + " " + b.desc + " " + cat).lower(), card))
            card.set_size_request(360, -1)
            self.flow.add(card)
        sw = Gtk.ScrolledWindow()
        sw.add(self.flow)
        outer.pack_start(sw, True, True, 0)
        self.add(outer)
        self.search.connect("search-changed", self.filter)

    def filter(self, _w) -> None:
        q = self.search.get_text().lower()
        shown: dict[int, bool] = {}
        for row, words, card in self.rows:
            vis = q in words
            row.set_visible(vis)
            shown[id(card)] = shown.get(id(card), False) or vis
        for child in self.flow.get_children():
            child.set_visible(shown.get(id(child.get_child()), True))


def main(argv: list[str] | None = None) -> int:
    if (argv or sys.argv[1:])[:1] in (["-h"], ["--help"]):
        print(__doc__.strip())
        return 0
    w = Keys()
    w.connect("destroy", Gtk.main_quit)
    w.show_all()
    w.search.grab_focus()
    Gtk.main()
    return 0
