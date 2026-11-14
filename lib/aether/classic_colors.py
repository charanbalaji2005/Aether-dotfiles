"""AetherOS classic-interface colour engine.

One palette drives every component of the classic interface (Waybar, Rofi,
SwayNC, Wlogout, Hyprlock, Hyprland borders, kitty). The palette comes from,
in order of preference:

  1. wallust      (``source=wallust``) — wallust renders config/wallust/templates/aether.json
  2. ImageMagick  (``source=image``)   — a histogram of the wallpaper, mapped here
  3. a preset     (``source=preset``)  — one of PRESETS below

If the preferred source fails, the next one is used and the reason is
reported; a preset always works, so the desktop always gets valid colours.

Standard library only. Command-line entry point: ``main()`` (scripts/bin/aether-colors).
"""

from __future__ import annotations

import colorsys
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# ── presets (original AetherOS palettes) ─────────────────────────────────
# Each preset lists background, foreground and the six accent hues in the
# terminal order red, green, yellow, blue, magenta, cyan. Everything else
# (surfaces, bright variants, borders) is derived.
PRESETS: dict[str, dict] = {
    "graphite": {"mode": "dark", "background": "#101218", "foreground": "#e4e7f0",
                 "hues": ["#f2777a", "#8fd18a", "#ebc47a", "#7f9cf5", "#b48cf2", "#6fd0d8"]},
    "abyss": {"mode": "dark", "background": "#0a0f1a", "foreground": "#d8e2f2",
              "hues": ["#ff6b8b", "#5fe0a8", "#f5c46b", "#4fa3ff", "#9d7bff", "#3fd6e6"]},
    "ember": {"mode": "dark", "background": "#16100e", "foreground": "#f2e4dc",
              "hues": ["#ff6a4d", "#a8c97f", "#ffb454", "#7aa6da", "#e08bb0", "#78c4b4"]},
    "moss": {"mode": "dark", "background": "#0f1410", "foreground": "#e1eadc",
             "hues": ["#e57373", "#9ccc65", "#e6c96a", "#6fa8dc", "#c38fd9", "#66c2a5"]},
    "lagoon": {"mode": "dark", "background": "#0e1716", "foreground": "#dcefea",
               "hues": ["#ef6f6c", "#3fbfa0", "#e8c46a", "#2bb3a3", "#c48fd6", "#5fd4c4"], "accent": "#35b5a4"},
    "slate": {"mode": "dark", "background": "#16181d", "foreground": "#e6e8ee",
              "hues": ["#e57b7b", "#8fc79a", "#e3c27a", "#9aa8c7", "#b79ad6", "#8fc4cf"], "accent": "#aab4cc"},
    "synth": {"mode": "dark", "background": "#151426", "foreground": "#e8e6f5",
              "hues": ["#ff6f91", "#5ee6b0", "#ffc75f", "#7d8cff", "#c77dff", "#4dd6ff"], "accent": "#8b93ff"},
    "dusk": {"mode": "dark", "background": "#151223", "foreground": "#f1e9f5",
             "hues": ["#ff7a9c", "#8fd6a8", "#ffc38a", "#9a8cff", "#e48ad8", "#7fd3e6"], "accent": "#e48ad8"},
    "neon": {"mode": "dark", "background": "#0b0d14", "foreground": "#e6f6ff",
             "hues": ["#ff3d7f", "#39ffb0", "#ffd84a", "#3d8bff", "#ff4df0", "#21e6ff"], "accent": "#21e6ff"},
    "emerald": {"mode": "dark", "background": "#0c1515", "foreground": "#e0f2ee",
                "hues": ["#f07167", "#2ec4a0", "#e9c46a", "#36b3c9", "#c77dff", "#4fd1c5"], "accent": "#2ec4a0"},
    "mono": {"mode": "dark", "background": "#0c0c0c", "foreground": "#e8e8e8",
             "hues": ["#d06a6a", "#9fbf9f", "#cfc39a", "#bdbdbd", "#b9a9c9", "#a9c4c4"], "accent": "#e2e2e2"},
    "dawn": {"mode": "light", "background": "#f6f3ee", "foreground": "#2b2a33",
             "hues": ["#c0392b", "#3d8b37", "#a8741a", "#2f6fd0", "#8a4fc7", "#1f8a8a"]},
    "paper": {"mode": "light", "background": "#fbfbfc", "foreground": "#1d2129",
              "hues": ["#d1495b", "#2e8b57", "#b7791f", "#3667d6", "#7b4fd1", "#16879c"]},
}
DEFAULT_PRESET = {"dark": "graphite", "light": "dawn"}
SOURCES = ("wallust", "image", "preset")
MODES = ("dark", "light")
STYLE_NAMES_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,40}$")

HEX_RE = re.compile(r"#([0-9a-fA-F]{6})\b")
VAR_RE = re.compile(r"\{\{\s*([a-z_][a-z0-9_]*)(?:\.(hex|rgb|rgba\(([0-9.]+)\)|hypr\(([0-9a-f]{2})\)))?\s*\}\}")


# ── colour maths ─────────────────────────────────────────────────────────
def hex_to_rgb(h: str) -> tuple[int, int, int]:
    h = h.strip().lstrip("#")
    if not re.fullmatch(r"[0-9a-fA-F]{6}", h):
        raise ValueError("not a #rrggbb colour: %r" % h)
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def rgb_to_hex(rgb) -> str:
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(c))) for c in rgb)


def luminance(h: str) -> float:
    def ch(c: int) -> float:
        c = c / 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = hex_to_rgb(h)
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def contrast(a: str, b: str) -> float:
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def mix(a: str, b: str, t: float) -> str:
    ra, rb = hex_to_rgb(a), hex_to_rgb(b)
    return rgb_to_hex([ra[i] + (rb[i] - ra[i]) * t for i in range(3)])


def hls(h: str) -> tuple[float, float, float]:
    r, g, b = (c / 255 for c in hex_to_rgb(h))
    return colorsys.rgb_to_hls(r, g, b)


def from_hls(hh: float, ll: float, ss: float) -> str:
    r, g, b = colorsys.hls_to_rgb(hh % 1.0, max(0.0, min(1.0, ll)), max(0.0, min(1.0, ss)))
    return rgb_to_hex((r * 255, g * 255, b * 255))


def ensure_contrast(color: str, bg: str, minimum: float) -> str:
    """Move ``color``'s lightness away from ``bg`` until the contrast is met."""
    hh, ll, ss = hls(color)
    lighter = luminance(bg) < 0.4
    step = 0.03 if lighter else -0.03
    out = color
    for _ in range(40):
        if contrast(out, bg) >= minimum:
            return out
        ll += step
        out = from_hls(hh, ll, ss)
    return out


# ── palette construction ────────────────────────────────────────────────
def build_palette(background: str, foreground: str, hues: list[str], mode: str, accent: str | None = None) -> dict:
    """Return the full role palette from a background, foreground and six hues."""
    if mode not in MODES:
        raise ValueError("mode must be dark or light")
    if len(hues) != 6:
        raise ValueError("six hues are needed (red, green, yellow, blue, magenta, cyan)")
    bg, fg = background.lower(), foreground.lower()
    if contrast(fg, bg) < 7:
        fg = ensure_contrast(fg, bg, 7)
    base = [ensure_contrast(h.lower(), bg, 3.2) for h in hues]
    if mode == "dark":
        bright = [from_hls(hls(h)[0], min(hls(h)[1] + 0.08, 0.85), hls(h)[2]) for h in base]
    else:
        bright = [from_hls(hls(h)[0], max(hls(h)[1] - 0.08, 0.2), hls(h)[2]) for h in base]
    p = {
        "background": bg,
        "foreground": fg,
        "cursor": base[3],
        "color0": mix(bg, fg, 0.10),
        "color7": mix(fg, bg, 0.15),
        "color8": mix(bg, fg, 0.38),
        "color15": fg,
    }
    for i in range(6):
        p["color%d" % (i + 1)] = base[i]
        p["color%d" % (i + 9)] = bright[i]
    if accent:
        p["accent_hint"] = ensure_contrast(accent.lower(), bg, 3.2)
    return derive_roles(p, mode)


def derive_roles(p: dict, mode: str) -> dict:
    """Add the semantic roles every template uses."""
    bg, fg = p["background"], p["foreground"]
    accents = [p["color%d" % i] for i in (4, 5, 6, 2, 3, 1)]
    # The most saturated hue that reads well on the background leads.
    ranked = sorted(accents, key=lambda c: (contrast(c, bg) >= 3, hls(c)[2]), reverse=True)
    accent = p.pop("accent_hint", None) or ranked[0]

    def hue_gap(c: str) -> float:
        d = abs(hls(c)[0] - hls(accent)[0])
        return min(d, 1 - d)
    # The second accent must be a visibly different hue, or gradients look flat.
    distinct = [c for c in ranked if c != accent and hue_gap(c) > 0.08]
    accent2 = distinct[0] if distinct else next((c for c in ranked if c != accent), ranked[1])
    p.update({
        "mode": mode,
        "surface": mix(bg, fg, 0.06),
        "surface2": mix(bg, fg, 0.11),
        "surface3": mix(bg, fg, 0.17),
        "border": mix(bg, fg, 0.22),
        "text": fg,
        "subtext": mix(fg, bg, 0.30),
        "muted": mix(fg, bg, 0.50),
        "accent": accent,
        "accent2": accent2,
        "on_accent": bg if contrast(bg, accent) >= contrast(fg, accent) else fg,
        "urgent": p["color1"],
        "ok": p["color2"],
        "warn": p["color3"],
        "info": p["color6"],
    })
    return p


def preset_palette(name: str) -> dict:
    if name not in PRESETS:
        raise KeyError("unknown preset %r (known: %s)" % (name, ", ".join(sorted(PRESETS))))
    pr = PRESETS[name]
    return build_palette(pr["background"], pr["foreground"], pr["hues"], pr["mode"], pr.get("accent"))


def palette_from_histogram(text: str, mode: str) -> dict:
    """Build a palette from ImageMagick ``histogram:info:-`` output."""
    colors: list[tuple[int, str]] = []
    for line in text.splitlines():
        m = re.match(r"\s*(\d+):.*?(#[0-9A-Fa-f]{6})", line)
        if m:
            colors.append((int(m.group(1)), "#" + m.group(2)[1:7].lower()))
    if len(colors) < 3:
        raise ValueError("too few colours in the image histogram")
    by_lum = sorted(colors, key=lambda c: luminance(c[1]))
    dark, light = by_lum[0][1], by_lum[-1][1]
    if mode == "dark":
        bg = from_hls(hls(dark)[0], min(hls(dark)[1], 0.08), min(hls(dark)[2], 0.35))
        fg = from_hls(hls(light)[0], max(hls(light)[1], 0.88), min(hls(light)[2], 0.25))
    else:
        bg = from_hls(hls(light)[0], max(hls(light)[1], 0.95), min(hls(light)[2], 0.25))
        fg = from_hls(hls(dark)[0], min(hls(dark)[1], 0.16), min(hls(dark)[2], 0.30))
    # Vivid, frequent colours become the accents; slots are filled by hue
    # so "red" stays reddish where the image allows it.
    vivid = sorted((c for c in colors if hls(c[1])[2] > 0.18),
                   key=lambda c: hls(c[1])[2] * (c[0] ** 0.5), reverse=True)
    slots = [0.0, 1 / 3, 1 / 6, 2 / 3, 5 / 6, 1 / 2]  # red green yellow blue magenta cyan
    hues: list[str] = []
    lightness = 0.68 if mode == "dark" else 0.40
    for target in slots:
        best = None
        for _, c in vivid:
            d = min(abs(hls(c)[0] - target), 1 - abs(hls(c)[0] - target))
            if d < 0.09 and (best is None or d < best[0]):
                best = (d, c)
        if best:
            hues.append(from_hls(hls(best[1])[0], lightness, max(hls(best[1])[2], 0.45)))
        else:
            # Nothing near this hue: tint it toward the image's dominant vivid colour.
            seed = vivid[0][1] if vivid else mix(dark, light, 0.5)
            hues.append(from_hls(target * 0.75 + hls(seed)[0] * 0.25, lightness, 0.50))
    # The image's most characteristic colour becomes the blue slot (the accent).
    if vivid:
        hues[3] = from_hls(hls(vivid[0][1])[0], lightness, max(hls(vivid[0][1])[2], 0.5))
    return build_palette(bg, fg, hues, mode)


def palette_from_wallust_json(data: dict, mode: str) -> dict:
    p = {}
    for k in ["background", "foreground", "cursor"] + ["color%d" % i for i in range(16)]:
        v = str(data.get(k, ""))
        hex_to_rgb(v)  # validates
        p[k] = v.lower()
    if contrast(p["foreground"], p["background"]) < 4.5:
        p["foreground"] = ensure_contrast(p["foreground"], p["background"], 7)
    return derive_roles(p, mode)


# ── templates ────────────────────────────────────────────────────────────
def render(template: str, values: dict) -> str:
    """Replace ``{{name}}``, ``{{name.hex}}``, ``{{name.rgb}}``,
    ``{{name.rgba(0.8)}}`` and ``{{name.hypr(ee)}}``. Unknown names are an error."""
    def sub(m: re.Match) -> str:
        name, fmt = m.group(1), m.group(2)
        if name not in values:
            raise KeyError("template uses unknown variable %r" % name)
        v = str(values[name])
        if fmt is None:
            return v
        r, g, b = hex_to_rgb(v)
        if fmt == "hex":
            return "%02x%02x%02x" % (r, g, b)
        if fmt == "rgb":
            return "%d, %d, %d" % (r, g, b)
        if fmt.startswith("rgba"):
            return "rgba(%d, %d, %d, %s)" % (r, g, b, m.group(3))
        return "rgba(%02x%02x%02x%s)" % (r, g, b, m.group(4))
    return VAR_RE.sub(sub, template)


# ── paths and state ──────────────────────────────────────────────────────
def repo_dir() -> Path:
    return Path(__file__).resolve().parents[2]


def config_home() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")


def classic_dir() -> Path:
    return config_home() / "aether-shell" / "classic"


def state_path() -> Path:
    return classic_dir() / "state.conf"


def read_state() -> dict:
    st = {"mode": "dark", "source": "image", "preset": "graphite",
          "waybar_layout": "default", "waybar_style": "pills"}
    try:
        for line in state_path().read_text(encoding="utf-8").splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.split("=", 1)
                st[k.strip()] = v.strip()
    except FileNotFoundError:
        pass
    return st


def write_state(st: dict) -> None:
    path = state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    body = "# AetherOS classic interface state (written by aether-colors / aether-wall)\n"
    body += "".join("%s=%s\n" % (k, st[k]) for k in sorted(st) if "\n" not in str(st[k]))
    atomic_write(path, body)


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".tmp-")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(tmp, path)


def interface() -> str:
    try:
        v = (config_home() / "aether-shell" / "interface").read_text(encoding="utf-8").strip()
        return v if v in ("classic", "aether") else "classic"
    except FileNotFoundError:
        return "classic"


def targets() -> list[tuple[str, Path]]:
    c, cfg = classic_dir(), config_home()
    out = [
        ("waybar.css", c / "waybar" / "colors.css"),
        ("gtk-colors.css", c / "swaync" / "colors.css"),
        ("gtk-colors.css", c / "wlogout" / "colors.css"),
        ("rofi.rasi", c / "colors" / "rofi.rasi"),
        ("hyprlock.conf", c / "colors" / "hyprlock.conf"),
        ("kitty.conf", cfg / "aether-shell" / "terminal" / "kitty-theme.conf"),
        ("palette.sh", c / "colors" / "palette.sh"),
    ]
    if interface() == "classic":
        out.append(("hyprland.conf", cfg / "aether-shell" / "hypr" / "interface-theme.conf"))
    return out


def wrapper_css(colors: Path, base: Path) -> str:
    return ("/* Generated by aether-colors — edit %s instead. */\n"
            '@import url("%s");\n@import url("%s");\n') % (base, colors, base)


# ── palette sources ──────────────────────────────────────────────────────
def run(cmd: list[str], timeout: int = 60) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=False)


def from_wallust(image: str, mode: str) -> dict:
    exe = shutil.which("wallust")
    if not exe:
        raise RuntimeError("wallust is not installed")
    out = classic_dir() / "colors" / "wallust.json"
    out.unlink(missing_ok=True)
    pal = "dark16" if mode == "dark" else "light16"
    r = run([exe, "run", "-s", "-q", "-p", pal, image], timeout=120)
    if r.returncode != 0:
        raise RuntimeError("wallust failed: " + (r.stderr.strip().splitlines() or ["exit %d" % r.returncode])[-1])
    if not out.exists():
        raise RuntimeError("wallust ran but did not write %s (is ~/.config/wallust linked?)" % out)
    return palette_from_wallust_json(json.loads(out.read_text(encoding="utf-8")), mode)


def from_image(image: str, mode: str) -> dict:
    exe = shutil.which("magick") or shutil.which("convert")
    if not exe:
        raise RuntimeError("ImageMagick is not installed")
    frame = image + "[0]"  # first frame of GIFs
    # jpeg:size lets libjpeg decode a 4K-8K photo at reduced scale (~7x faster).
    r = run([exe, "-define", "jpeg:size=320x320", frame, "-resize", "160x160>",
             "-colors", "24", "-format", "%c", "histogram:info:-"])
    if r.returncode != 0:
        raise RuntimeError("ImageMagick could not read %s" % image)
    return palette_from_histogram(r.stdout, mode)


def resolve_palette(st: dict) -> tuple[dict, str, list[str]]:
    """Return (palette, source actually used, notes about fallbacks)."""
    mode = st.get("mode", "dark") if st.get("mode") in MODES else "dark"
    notes: list[str] = []
    image = st.get("palette_image") or st.get("wallpaper", "")
    order = {"wallust": ["wallust", "image"], "image": ["image"], "preset": []}.get(st.get("source", "image"), ["image"])
    for src in order:
        if not image or not os.path.isfile(image):
            notes.append("%s: no wallpaper recorded yet" % src)
            break
        try:
            return (from_wallust if src == "wallust" else from_image)(image, mode), src, notes
        except (RuntimeError, ValueError, OSError, json.JSONDecodeError, subprocess.TimeoutExpired) as e:
            notes.append("%s: %s" % (src, e))
    name = st.get("preset", "")
    if name not in PRESETS or (st.get("source") != "preset" and PRESETS[name]["mode"] != mode):
        name = DEFAULT_PRESET[mode]
    pal = preset_palette(name)
    if pal["mode"] != mode:
        notes.append("preset %s is a %s palette" % (name, pal["mode"]))
    return pal, "preset:" + name, notes


# ── apply ────────────────────────────────────────────────────────────────
def template_dir() -> Path:
    return repo_dir() / "theme" / "classic" / "templates"


def template_values(pal: dict, st: dict) -> dict:
    values = dict(pal)
    values["wallpaper"] = st.get("wallpaper", "")
    # Translucency of floating surfaces follows the glass level (aether-glass).
    lvl = st.get("glass", "acrylic")
    a = {"off": 0.97, "subtle": 0.88, "acrylic": 0.74, "deep": 0.60}.get(lvl, 0.74)
    values["glass_kitty"] = "%.2f" % {"off": 1.0, "subtle": 0.86, "acrylic": 0.72, "deep": 0.58}.get(lvl, 0.72)
    for role in ("background", "surface"):
        r, g, b = hex_to_rgb(pal[role])
        values["glass_" + role] = "rgba(%d, %d, %d, %.2f)" % (r, g, b, a)
    return values


def write_outputs(pal: dict, st: dict) -> list[Path]:
    values = template_values(pal, st)
    written = []
    for tpl, dest in targets():
        text = render((template_dir() / tpl).read_text(encoding="utf-8"), values)
        atomic_write(dest, text)
        written.append(dest)
    cfg, c = config_home(), classic_dir()
    style = st.get("waybar_style", "pills")
    if not STYLE_NAMES_RE.match(style) or not (cfg / "waybar" / "styles" / (style + ".css")).exists():
        style = "pills"
    for name, colors, base in (
        ("waybar", c / "waybar" / "colors.css", cfg / "waybar" / "styles" / (style + ".css")),
        ("swaync", c / "swaync" / "colors.css", cfg / "swaync" / "style.css"),
        ("wlogout", c / "wlogout" / "colors.css", cfg / "wlogout" / "style.css"),
    ):
        dest = c / name / "style.css"
        atomic_write(dest, wrapper_css(colors, base))
        written.append(dest)
    # Lock-screen design: hyprlock.conf sources this copy, so it must always exist.
    design = st.get("lock_design", "signature")
    designs = repo_dir() / "config" / "hypr" / "hyprlock"
    if not STYLE_NAMES_RE.match(design) or not (designs / (design + ".conf")).is_file():
        design = "signature"
    dest = c / "colors" / "hyprlock-design.conf"
    atomic_write(dest, "# Copied by aether-colors from config/hypr/hyprlock/%s.conf — choose with: aether-lock design NAME\n" % design
                 + (designs / (design + ".conf")).read_text(encoding="utf-8"))
    written.append(dest)
    atomic_write(c / "colors" / "palette.json", json.dumps(pal, indent=2, sort_keys=True) + "\n")
    return written


def reload_apps(pal: dict) -> None:
    def quiet(cmd: list[str]) -> None:
        if shutil.which(cmd[0]):
            try:
                run(cmd, timeout=10)
            except subprocess.TimeoutExpired:
                pass
    scheme = "prefer-dark" if pal["mode"] == "dark" else "prefer-light"
    quiet(["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", scheme])
    # Running apps belong to a graphical session: outside one (a TTY, a script
    # with another HOME) a signal would reach some other session's Waybar and
    # kitty. pkill matches by name, so it is also limited to this user.
    if not (os.environ.get("WAYLAND_DISPLAY") or os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")):
        return
    uid = str(os.getuid())
    quiet(["pkill", "-SIGUSR2", "-u", uid, "-x", "waybar"])
    quiet(["swaync-client", "--reload-css"])
    quiet(["pkill", "-SIGUSR1", "-u", uid, "-x", "kitty"])
    if interface() == "classic" and os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        a, b = render("{{accent.hex}}", pal), render("{{accent2.hex}}", pal)
        quiet(["hyprctl", "keyword", "general:col.active_border",
               "rgba(%see) rgba(%see) 45deg" % (a, b)])
        quiet(["hyprctl", "keyword", "general:col.inactive_border",
               "rgba(%saa)" % render("{{border.hex}}", pal)])


def apply(st: dict, reload: bool = True) -> tuple[str, list[str]]:
    pal, used, notes = resolve_palette(st)
    write_outputs(pal, st)
    if reload:
        reload_apps(pal)
    return used, notes


def outputs_missing() -> bool:
    return any(not dest.exists() for _, dest in targets()) or \
        not (classic_dir() / "waybar" / "style.css").exists() or \
        not (classic_dir() / "colors" / "hyprlock-design.conf").exists()


# ── CLI ──────────────────────────────────────────────────────────────────
USAGE = """aether-colors — palette engine for the AetherOS classic interface

  aether-colors apply [--wallpaper FILE] [--no-reload]   regenerate every app's colours
  aether-colors init                                     write colours only if missing (no reload)
  aether-colors mode dark|light|toggle                   switch dark/light and re-apply
  aether-colors source wallust|image|preset [NAME]       choose where the palette comes from
  aether-colors waybar-style NAME                        record the Waybar style and re-apply
  aether-colors lock-design NAME                         choose the Hyprlock design (config/hypr/hyprlock/)
  aether-colors presets                                  list the built-in palettes
  aether-colors show                                     print the active palette (JSON)
  aether-colors waybar-json                              dark/light state for the Waybar module
"""


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if not args or args[0] in ("-h", "--help", "help"):
        print(USAGE, end="")
        return 0
    cmd, rest = args[0], args[1:]
    reload = "--no-reload" not in rest
    rest = [a for a in rest if a != "--no-reload"]
    st = read_state()
    try:
        if cmd == "apply":
            i = 0
            while i < len(rest):
                if rest[i] in ("--wallpaper", "--palette-image") and i + 1 < len(rest):
                    key = rest[i].lstrip("-").replace("-", "_")
                    st[key] = os.path.abspath(rest[i + 1])
                    if key == "wallpaper":
                        st.pop("palette_image", None)
                    i += 2
                else:
                    print("unknown option for apply: %s" % rest[i], file=sys.stderr)
                    return 2
        elif cmd == "init":
            if not outputs_missing():
                return 0
            reload = False
        elif cmd == "mode":
            want = rest[0] if rest else "toggle"
            if want == "toggle":
                want = "light" if st.get("mode") == "dark" else "dark"
            if want not in MODES:
                print("mode must be dark, light or toggle", file=sys.stderr)
                return 2
            st["mode"] = want
            if st.get("source") == "preset" and PRESETS.get(st.get("preset", ""), {}).get("mode") != want:
                st["preset"] = DEFAULT_PRESET[want]
        elif cmd == "source":
            if not rest or rest[0] not in SOURCES:
                print("source must be one of: " + ", ".join(SOURCES), file=sys.stderr)
                return 2
            st["source"] = rest[0]
            if rest[0] == "preset" and len(rest) > 1:
                if rest[1] not in PRESETS:
                    print("unknown preset %r; see: aether-colors presets" % rest[1], file=sys.stderr)
                    return 2
                st["preset"] = rest[1]
                st["mode"] = PRESETS[rest[1]]["mode"]
        elif cmd == "waybar-style":
            if not rest or not STYLE_NAMES_RE.match(rest[0]):
                print("usage: aether-colors waybar-style NAME", file=sys.stderr)
                return 2
            st["waybar_style"] = rest[0]
        elif cmd == "presets":
            for name in sorted(PRESETS):
                print("%-10s %s" % (name, PRESETS[name]["mode"]))
            return 0
        elif cmd == "lock-design":
            if not rest or not STYLE_NAMES_RE.match(rest[0]) or not (repo_dir() / "config" / "hypr" / "hyprlock" / (rest[0] + ".conf")).is_file():
                print("unknown lock design; see config/hypr/hyprlock/", file=sys.stderr)
                return 2
            st["lock_design"] = rest[0]
            reload = False
        elif cmd == "waybar-json":
            m = st.get("mode", "dark")
            print(json.dumps({"text": m, "alt": m, "class": m,
                              "tooltip": "%s mode · palette from %s" % (m.capitalize(), st.get("source", "image"))}))
            return 0
        elif cmd == "show":
            print(json.dumps(resolve_palette(st)[0], indent=2, sort_keys=True))
            return 0
        else:
            print(USAGE, end="", file=sys.stderr)
            return 2
        write_state(st)
        used, notes = apply(st, reload=reload)
    except (OSError, KeyError, ValueError) as e:
        print("aether-colors: %s" % e, file=sys.stderr)
        return 1
    for n in notes:
        print("aether-colors: fell back — %s" % n, file=sys.stderr)
    print("aether-colors: %s palette from %s" % (st.get("mode"), used))
    return 0


if __name__ == "__main__":
    sys.exit(main())
