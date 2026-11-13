"""AetherOS date & time panel (classic interface) — click the bar's clock or weather.

A frosted panel under the clock with everything about "now": a live clock
with seconds, the full date, week and day of the year, the time zone, the
weather in detail (hourly and three-day forecast, sunrise and sunset), a month
calendar that counts the days to the date you pick, world clocks and uptime.
On Hyprland it is a layer-shell surface (namespace "aether-calendar") so the
compositor blurs what is behind it. Escape or clicking elsewhere closes it.

World clocks come from the state key world_clocks (comma-separated IANA zone
names); the weather from aether-weather's cache.
"""

from __future__ import annotations

import datetime
import json
import os
import subprocess
import sys
import threading
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

from aether import classic_colors as cc  # noqa: E402

try:
    gi.require_version("GtkLayerShell", "0.1")
    from gi.repository import GtkLayerShell  # noqa: E402
except (ValueError, ImportError):
    GtkLayerShell = None

WEATHER_CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "aether", "weather.json")
DEFAULT_CLOCKS = "UTC,Europe/London,America/New_York,Asia/Tokyo"

# wttr.in weather codes → Nerd Font glyph (same table as aether-weather).
ICONS = [((113,), "󰖙"), ((116,), "󰖕"), ((119, 122), "󰖐"), ((143, 248, 260), "󰖑"),
         ((176, 263, 266, 293, 296, 353), "󰖗"), ((299, 302, 305, 308, 356, 359), "󰖖"),
         ((179, 182, 185, 227, 230, 323, 326, 329, 332, 335, 338, 368, 371, 374, 377), "󰖘"),
         ((200, 386, 389, 392, 395), "󰖓")]

CSS = """
* { font-family: "Inter", "SF Pro Display", "Cantarell", "Noto Sans", sans-serif; }
.dt-window, .dt-window > * { background-color: transparent; }
.dt-root { background-color: alpha(%(background)s, %(glass)s); border: 1px solid alpha(white, 0.10);
           border-radius: 30px; padding: 18px; }
.dt-card { background-color: alpha(white, 0.08); border: 1px solid alpha(white, 0.08); border-radius: 22px; padding: 14px 16px; }
.dt-time { font-size: 52px; font-weight: 300; color: white; }
.dt-sec { font-size: 22px; font-weight: 300; color: alpha(white, 0.55); }
.dt-date { font-size: 16px; font-weight: 700; color: white; }
.dt-chip { font-size: 11px; font-weight: 700; color: alpha(white, 0.85); background-color: alpha(white, 0.10);
           border-radius: 99px; padding: 3px 10px; }
.dt-chip.accent { background-color: alpha(%(accent)s, 0.85); color: %(on_accent)s; }
.dt-head { font-size: 11px; font-weight: 800; color: alpha(white, 0.55); letter-spacing: 1px; }
.dt-icon { font-family: "JetBrainsMono Nerd Font"; color: %(accent)s; }
.dt-icon.big { font-size: 46px; }
.dt-icon.small { font-size: 18px; }
.dt-temp { font-size: 40px; font-weight: 300; color: white; }
.dt-desc { font-size: 14px; font-weight: 700; color: white; }
.dt-sub { font-size: 12px; color: alpha(white, 0.65); }
.dt-stat-v { font-size: 13px; font-weight: 700; color: white; }
.dt-stat-k { font-size: 10px; color: alpha(white, 0.55); }
.dt-slot { background-color: alpha(white, 0.06); border-radius: 14px; padding: 8px 4px; }
.dt-slot-t { font-size: 10px; color: alpha(white, 0.6); }
.dt-slot-v { font-size: 13px; font-weight: 700; color: white; }
.dt-wc-city { font-size: 13px; font-weight: 700; color: white; }
.dt-wc-off { font-size: 11px; color: alpha(white, 0.55); }
.dt-wc-time { font-size: 18px; font-weight: 300; color: white; }
.dt-month { font-size: 15px; font-weight: 800; color: white; }
.dt-nav { font-family: "JetBrainsMono Nerd Font"; font-size: 14px; color: white; background-image: none;
          background-color: transparent; border: none; box-shadow: none; text-shadow: none;
          min-width: 28px; min-height: 28px; border-radius: 99px; padding: 0 6px; }
.dt-nav label { color: white; }
button.dt-nav, button.dt-nav:backdrop, button.dt-nav:active, button.dt-nav:focus {
    background-image: none; background-color: alpha(white, 0.06); border-color: transparent; box-shadow: none; outline: none; }
button.dt-nav:hover { background-color: alpha(white, 0.16); }
button.dt-nav.today { font-family: "Inter", sans-serif; font-size: 11px; font-weight: 800; padding: 0 10px; }
calendar { background-color: transparent; color: white; border: none; padding: 2px; font-size: 13px; }
calendar.header { background-color: transparent; border: none; }
calendar.button { color: white; }
calendar:indeterminate { color: alpha(white, 0.28); }
calendar:selected { background-color: %(accent)s; color: %(on_accent)s; border-radius: 99px; font-weight: 800; }
calendar.highlight { color: alpha(white, 0.55); font-weight: 800; font-size: 10px; }
.dt-picked { font-size: 12px; color: alpha(white, 0.75); }
"""


def weather_icon(code: int) -> str:
    return next((i for codes, i in ICONS if code in codes), "󰖐")


def label(text: str, cls: str = "", xalign: float = 0.0, markup: bool = False) -> Gtk.Label:
    lb = Gtk.Label()
    (lb.set_markup if markup else lb.set_text)(text)
    lb.set_xalign(xalign)
    for c in cls.split():
        lb.get_style_context().add_class(c)
    return lb


def card(spacing: int = 8) -> Gtk.Box:
    b = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=spacing)
    b.get_style_context().add_class("dt-card")
    return b


def utc_offset(dt: datetime.datetime) -> str:
    off = dt.utcoffset() or datetime.timedelta(0)
    mins = int(off.total_seconds() // 60)
    sign = "+" if mins >= 0 else "−"
    return "UTC%s%02d:%02d" % (sign, abs(mins) // 60, abs(mins) % 60)


def uptime() -> str:
    try:
        secs = int(float(open("/proc/uptime").read().split()[0]))
    except (OSError, ValueError, IndexError):
        return "?"
    d, rem = divmod(secs, 86400)
    h, m = rem // 3600, rem % 3600 // 60
    return ("%dd %dh %dm" % (d, h, m)) if d else ("%dh %dm" % (h, m))


def load_css(glass: float) -> None:
    pal = dict(cc.resolve_palette(cc.read_state())[0])
    pal["glass"] = "%.2f" % glass
    prov = Gtk.CssProvider()
    prov.load_from_data((CSS % pal).encode())
    Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), prov, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)


def glass_alpha() -> float:
    lvl = cc.read_state().get("glass", "acrylic")
    return {"off": 0.92, "subtle": 0.62, "acrylic": 0.48, "deep": 0.34}.get(lvl, 0.48)


class Panel(Gtk.Box):
    def __init__(self) -> None:
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
        self.get_style_context().add_class("dt-root")
        self.state = cc.read_state()
        self.units = self.state.get("weather_units", "metric")
        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        left.set_size_request(350, -1)
        right.set_size_request(320, -1)
        self.pack_start(left, False, False, 0)
        self.pack_start(right, False, False, 0)

        left.pack_start(self.build_now(), False, False, 0)
        self.weather_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        left.pack_start(self.weather_box, False, False, 0)
        right.pack_start(self.build_calendar(), False, False, 0)
        right.pack_start(self.build_world(), False, False, 0)

        self.fill_weather()
        self.refresh_weather()
        self.tick()
        GLib.timeout_add(1000, self.tick)

    # ── now ──────────────────────────────────────────────────────────────
    def build_now(self) -> Gtk.Box:
        box = card(6)
        row = Gtk.Box(spacing=4)
        self.time_lb = label("", "dt-time")
        self.sec_lb = label("", "dt-sec")
        self.sec_lb.set_valign(Gtk.Align.END)
        self.sec_lb.set_margin_bottom(10)
        row.pack_start(self.time_lb, False, False, 0)
        row.pack_start(self.sec_lb, False, False, 0)
        box.pack_start(row, False, False, 0)
        self.date_lb = label("", "dt-date")
        box.pack_start(self.date_lb, False, False, 0)
        self.chips = Gtk.FlowBox()
        self.chips.set_selection_mode(Gtk.SelectionMode.NONE)
        self.chips.set_max_children_per_line(4)
        self.chips.set_column_spacing(6)
        self.chips.set_row_spacing(6)
        self.chips.set_margin_top(6)
        box.pack_start(self.chips, False, False, 0)
        self.chip_day = None
        return box

    def tick(self) -> bool:
        now = datetime.datetime.now().astimezone()
        self.time_lb.set_text(now.strftime("%H:%M"))
        self.sec_lb.set_text(now.strftime(":%S"))
        self.date_lb.set_text(now.strftime("%A, %-d %B %Y"))
        if self.chip_day != (now.date(), now.minute):
            self.chip_day = (now.date(), now.minute)
            for c in self.chips.get_children():
                self.chips.remove(c)
            year_days = 366 if now.year % 4 == 0 and (now.year % 100 or now.year % 400 == 0) else 365
            for text, accent in (("Week %d" % now.isocalendar()[1], True),
                                 ("Day %d of %d" % (now.timetuple().tm_yday, year_days), False),
                                 ("%s · %s" % (now.strftime("%Z"), utc_offset(now)), False),
                                 ("Up %s" % uptime(), False)):
                self.chips.add(label(text, "dt-chip accent" if accent else "dt-chip", 0.5))
            self.chips.show_all()
            self.fill_world(now)
        return True

    # ── weather ──────────────────────────────────────────────────────────
    def refresh_weather(self) -> None:
        """Ask aether-weather to refresh its cache if it is stale, then redraw."""
        try:
            fresh = (datetime.datetime.now().timestamp() - os.stat(WEATHER_CACHE).st_mtime) < 1800
        except OSError:
            fresh = False
        if fresh:
            return

        def work() -> None:
            subprocess.run(["aether-weather"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20, check=False)
            GLib.idle_add(self.fill_weather)
        threading.Thread(target=work, daemon=True).start()

    def t(self, d: dict, c: str, f: str) -> str:
        return (d[f] + "°F") if self.units == "us" else (d[c] + "°C")

    def fill_weather(self) -> bool:
        for c in self.weather_box.get_children():
            self.weather_box.remove(c)
        box = card(10)
        self.weather_box.pack_start(box, False, False, 0)
        try:
            d = json.load(open(WEATHER_CACHE))
            cur = d["current_condition"][0]
        except (OSError, ValueError, KeyError, IndexError):
            box.pack_start(label("WEATHER", "dt-head"), False, False, 0)
            off = self.state.get("weather", "off") == "off" and not self.state.get("weather_location")
            box.pack_start(label("Weather is off — turn it on in Settings → Bar, or: aether-weather --force" if off
                                 else "No weather yet (offline?)", "dt-sub"), False, False, 0)
            box.show_all()
            return False
        area = d.get("nearest_area", [{}])[0]
        place = ", ".join(x[0]["value"] for x in (area.get("areaName"), area.get("region")) if x)
        today = d.get("weather", [{}])[0]
        astro = (today.get("astronomy") or [{}])[0]

        box.pack_start(label("WEATHER · %s" % place.upper(), "dt-head"), False, False, 0)
        top = Gtk.Box(spacing=12)
        top.pack_start(label(weather_icon(int(cur.get("weatherCode", 113))), "dt-icon big"), False, False, 0)
        top.pack_start(label(self.t(cur, "temp_C", "temp_F"), "dt-temp"), False, False, 0)
        desc = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        desc.set_valign(Gtk.Align.CENTER)
        desc.pack_start(label(cur["weatherDesc"][0]["value"].strip(), "dt-desc"), False, False, 0)
        desc.pack_start(label("Feels like %s" % self.t(cur, "FeelsLikeC", "FeelsLikeF"), "dt-sub"), False, False, 0)
        if today:
            desc.pack_start(label("H %s  L %s" % (self.t(today, "maxtempC", "maxtempF"), self.t(today, "mintempC", "mintempF")),
                                  "dt-sub"), False, False, 0)
        top.pack_start(desc, False, False, 0)
        box.pack_start(top, False, False, 0)

        wind = ("%s mph" % cur["windspeedMiles"]) if self.units == "us" else ("%s km/h" % cur["windspeedKmph"])
        vis = ("%s mi" % cur["visibilityMiles"]) if self.units == "us" else ("%s km" % cur["visibility"])
        rain = max((int(h.get("chanceofrain", 0)) for h in today.get("hourly", [])), default=0)
        stats = Gtk.Grid(column_spacing=18, row_spacing=8, column_homogeneous=True)
        for i, (k, v) in enumerate((("Humidity", "%s%%" % cur["humidity"]), ("Wind", "%s %s" % (wind, cur["winddir16Point"])),
                                    ("UV index", cur.get("uvIndex", "?")), ("Pressure", "%s hPa" % cur["pressure"]),
                                    ("Visibility", vis), ("Rain today", "%d%%" % rain),
                                    ("Sunrise", astro.get("sunrise", "?")), ("Sunset", astro.get("sunset", "?")),
                                    ("Moon", astro.get("moon_phase", "?")))):
            cell = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
            cell.pack_start(label(v, "dt-stat-v"), False, False, 0)
            cell.pack_start(label(k, "dt-stat-k"), False, False, 0)
            stats.attach(cell, i % 3, i // 3, 1, 1)
        box.pack_start(stats, False, False, 0)

        # Next hours (wttr.in gives 3-hour steps) and the next days.
        now = datetime.datetime.now()
        slots = []
        for day_i, day in enumerate(d.get("weather", [])[:2]):
            base = datetime.datetime.strptime(day["date"], "%Y-%m-%d")
            for h in day.get("hourly", []):
                at = base + datetime.timedelta(hours=int(h["time"]) // 100)
                if at >= now - datetime.timedelta(hours=1):
                    slots.append((at, h))
        hours = Gtk.Box(spacing=6, homogeneous=True)
        for at, h in slots[:5]:
            hours.pack_start(self.slot(at.strftime("%H:%M"), weather_icon(int(h.get("weatherCode", 113))),
                                       self.t(h, "tempC", "tempF")), True, True, 0)
        if slots:
            box.pack_start(label("NEXT HOURS", "dt-head"), False, False, 0)
            box.pack_start(hours, False, False, 0)
        days = Gtk.Box(spacing=6, homogeneous=True)
        for day in d.get("weather", [])[:3]:
            date = datetime.datetime.strptime(day["date"], "%Y-%m-%d").date()
            name = "Today" if date == now.date() else date.strftime("%a %-d")
            noon = next((h for h in day.get("hourly", []) if h.get("time") == "1200"), (day.get("hourly") or [{}])[0])
            days.pack_start(self.slot(name, weather_icon(int(noon.get("weatherCode", 113))),
                                      "%s / %s" % (self.t(day, "maxtempC", "maxtempF").rstrip("CF°") + "°",
                                                   self.t(day, "mintempC", "mintempF").rstrip("CF°") + "°")), True, True, 0)
        box.pack_start(label("FORECAST", "dt-head"), False, False, 0)
        box.pack_start(days, False, False, 0)
        box.show_all()
        return False

    @staticmethod
    def slot(top: str, icon: str, value: str) -> Gtk.Box:
        b = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        b.get_style_context().add_class("dt-slot")
        b.pack_start(label(top, "dt-slot-t", 0.5), False, False, 0)
        b.pack_start(label(icon, "dt-icon small", 0.5), False, False, 0)
        b.pack_start(label(value, "dt-slot-v", 0.5), False, False, 0)
        return b

    # ── calendar ─────────────────────────────────────────────────────────
    def build_calendar(self) -> Gtk.Box:
        box = card(6)
        head = Gtk.Box(spacing=4)
        self.month_lb = label("", "dt-month")
        head.pack_start(self.month_lb, True, True, 0)
        for text, cls, cb in (("󰅁", "", lambda *_: self.shift(-1)), ("Today", "today", lambda *_: self.go_today()),
                              ("󰅂", "", lambda *_: self.shift(1))):
            b = Gtk.Button(label=text)
            b.get_style_context().add_class("dt-nav")
            if cls:
                b.get_style_context().add_class(cls)
            b.connect("clicked", cb)
            head.pack_start(b, False, False, 0)
        box.pack_start(head, False, False, 0)
        self.cal = Gtk.Calendar()
        self.cal.set_display_options(Gtk.CalendarDisplayOptions.SHOW_DAY_NAMES | Gtk.CalendarDisplayOptions.SHOW_WEEK_NUMBERS)
        self.cal.connect("month-changed", lambda *_: self.on_month())
        self.cal.connect("day-selected", lambda *_: self.on_pick())
        box.pack_start(self.cal, False, False, 0)
        self.picked = label("", "dt-picked")
        box.pack_start(self.picked, False, False, 0)
        self.on_month()
        self.on_pick()
        return box

    def shift(self, months: int) -> None:
        y, m, _d = self.cal.get_date()
        m += months
        y, m = y + (m < 0) * -1 + (m > 11), m % 12
        self.cal.select_month(m, y)

    def go_today(self) -> None:
        t = datetime.date.today()
        self.cal.select_month(t.month - 1, t.year)
        self.cal.select_day(t.day)

    def on_month(self) -> None:
        y, m, _d = self.cal.get_date()
        self.month_lb.set_text(datetime.date(y, m + 1, 1).strftime("%B %Y"))
        self.cal.clear_marks()
        t = datetime.date.today()
        if (y, m + 1) == (t.year, t.month):
            self.cal.mark_day(t.day)

    def on_pick(self) -> None:
        y, m, d = self.cal.get_date()
        if not d:
            self.picked.set_text("")
            return
        picked = datetime.date(y, m + 1, d)
        diff = (picked - datetime.date.today()).days
        rel = {0: "today", 1: "tomorrow", -1: "yesterday"}.get(diff) or (
            "in %d days" % diff if diff > 0 else "%d days ago" % -diff)
        self.picked.set_text("%s · %s · week %d" % (picked.strftime("%a %-d %b %Y"), rel, picked.isocalendar()[1]))

    # ── world clocks ─────────────────────────────────────────────────────
    def build_world(self) -> Gtk.Box:
        box = card(8)
        box.pack_start(label("WORLD CLOCK", "dt-head"), False, False, 0)
        self.world = Gtk.Grid(column_spacing=12, row_spacing=8)
        box.pack_start(self.world, False, False, 0)
        self.zones = []
        for name in (self.state.get("world_clocks") or DEFAULT_CLOCKS).split(","):
            try:
                self.zones.append((name.strip(), ZoneInfo(name.strip())))
            except (ZoneInfoNotFoundError, ValueError):
                continue
        return box

    def fill_world(self, now: datetime.datetime) -> None:
        for c in self.world.get_children():
            self.world.remove(c)
        local_off = now.utcoffset() or datetime.timedelta(0)
        for row, (name, tz) in enumerate(self.zones):
            there = now.astimezone(tz)
            hours = ((there.utcoffset() or datetime.timedelta(0)) - local_off).total_seconds() / 3600
            day = (there.date() - now.date()).days
            rel = ("%+g h" % hours if hours else "same time") + {1: ", tomorrow", -1: ", yesterday"}.get(day, "")
            city = name.split("/")[-1].replace("_", " ")
            names = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            names.pack_start(label(city, "dt-wc-city"), False, False, 0)
            names.pack_start(label(rel, "dt-wc-off"), False, False, 0)
            names.set_hexpand(True)
            self.world.attach(names, 0, row, 1, 1)
            t = label(there.strftime("%H:%M"), "dt-wc-time", 1.0)
            t.set_valign(Gtk.Align.CENTER)
            self.world.attach(t, 1, row, 1, 1)
        self.world.show_all()


class Window(Gtk.Window):
    def __init__(self, bottom: bool = False) -> None:
        super().__init__(title="Date & Time")
        self.set_wmclass("aether-calendar", "AetherOS Date & Time")
        self.get_style_context().add_class("dt-window")
        screen = self.get_screen()
        if screen.get_rgba_visual():
            self.set_visual(screen.get_rgba_visual())
        self.set_app_paintable(True)
        self.set_decorated(False)
        if GtkLayerShell and GtkLayerShell.is_supported():
            edge = GtkLayerShell.Edge.BOTTOM if bottom else GtkLayerShell.Edge.TOP
            GtkLayerShell.init_for_window(self)
            GtkLayerShell.set_namespace(self, "aether-calendar")
            GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
            GtkLayerShell.set_anchor(self, edge, True)  # one edge only: centred along it
            GtkLayerShell.set_margin(self, edge, 50)
            GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.ON_DEMAND)
        load_css(glass_alpha())
        self.add(Panel())
        self.connect("key-press-event", lambda _w, e: e.keyval == Gdk.KEY_Escape and self.close())
        self.connect("focus-out-event", lambda *_a: GLib.timeout_add(150, self.close_if_unfocused))

    def close_if_unfocused(self) -> bool:
        if not self.is_active():
            self.close()
        return False


def mark_closed() -> None:
    """Note when the panel closed: clicking the clock while it is open first
    closes it (focus moves to the bar), and aether-calendar must not then
    reopen it for that same click."""
    try:
        open(os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "aether-calendar.closed"), "w").close()
    except OSError:
        pass


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    if args[:1] in (["-h"], ["--help"]):
        print(__doc__.strip())
        return 0
    w = Window(bottom="--bottom" in args)
    w.connect("destroy", lambda *_a: (mark_closed(), Gtk.main_quit()))
    w.show_all()
    Gtk.main()
    return 0
