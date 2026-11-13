"""Theme helpers: wallpaper-derived accent colour and dark/light switching.

Accent extraction quantises the wallpaper with ImageMagick (`magick`, or the
legacy `convert`) into a 16-colour histogram, then scores each colour by
population x saturation, skipping near-greys and extremes. The winner is
nudged into a lightness band that keeps contrast against the shell's dark
or light surfaces. Without ImageMagick the command fails clearly — it never
returns a made-up colour.
"""

from __future__ import annotations

import colorsys
import json
import os
import re
from typing import List, Optional, Tuple

from .util import Context, config_dir

_HIST_RE = re.compile(r"^\s*(\d+):\s*\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)")


def parse_histogram(text: str) -> List[Tuple[int, Tuple[int, int, int]]]:
    out = []
    for line in text.splitlines():
        m = _HIST_RE.match(line)
        if not m:
            continue
        count = int(m.group(1))
        rgb = tuple(int(round(float(m.group(i)))) for i in (2, 3, 4))
        # 16-bit quantum builds report 0-65535.
        if max(rgb) > 255:
            rgb = tuple(int(c / 257) for c in rgb)
        out.append((count, rgb))  # type: ignore[arg-type]
    return out


def pick_accent(hist: List[Tuple[int, Tuple[int, int, int]]], mode: str = "dark") -> Optional[str]:
    if not hist:
        return None
    total = float(sum(c for c, _ in hist)) or 1.0
    best = None
    best_score = -1.0
    for count, (r, g, b) in hist:
        h, l, s = colorsys.rgb_to_hls(r / 255.0, g / 255.0, b / 255.0)
        if s < 0.18 or l < 0.08 or l > 0.94:
            continue  # greys, near-black, near-white make poor accents
        share = count / total
        # Favour vivid colours, but not tiny specks.
        score = (share ** 0.6) * (s ** 1.5) * (1.0 - abs(l - 0.55))
        if score > best_score:
            best_score, best = score, (h, l, s)
    if best is None:
        # Monochrome wallpaper: fall back to the most common colour's hue at a
        # moderate saturation so the accent still relates to the image.
        count, (r, g, b) = max(hist, key=lambda x: x[0])
        h, l, s = colorsys.rgb_to_hls(r / 255.0, g / 255.0, b / 255.0)
        best = (h, l, max(s, 0.35))
    h, l, s = best
    s = min(max(s, 0.45), 0.85)
    l = min(max(l, 0.62), 0.74) if mode == "dark" else min(max(l, 0.38), 0.48)
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return "#%02X%02X%02X" % (int(round(r * 255)), int(round(g * 255)), int(round(b * 255)))


def extract_accent(ctx: Context, image: str, mode: str = "dark") -> Tuple[Optional[str], Optional[str]]:
    """Return (hex colour, error)."""
    if not os.path.isfile(image):
        return None, "image not found: %s" % image
    tool = "magick" if ctx.which("magick") else ("convert" if ctx.which("convert") else None)
    if tool is None:
        return None, "ImageMagick is not installed (sudo dnf install ImageMagick)"
    # "[0]" selects the first frame (GIF/animated WebP) and keeps the decode cheap.
    argv = [tool, "-define", "jpeg:size=192x192", image + "[0]", "-resize", "96x96", "-colors", "16", "-depth", "8", "-format", "%c", "histogram:info:-"]
    res = ctx.run(argv, timeout=30)
    if not res.ok:
        return None, (res.err.strip().splitlines() or ["ImageMagick failed"])[-1]
    colour = pick_accent(parse_histogram(res.out), mode)
    if colour is None:
        return None, "could not derive a colour from the image histogram"
    return colour, None


# -- shell config.json --------------------------------------------------------

def config_file() -> str:
    return os.path.join(config_dir(), "config.json")


def update_shell_config(section: str, key: str, value) -> Tuple[bool, str]:
    """Atomically set one key in the shell's config.json.

    The running shell watches this file and applies the change live. A
    corrupt file is never overwritten — the caller is told to run
    `aether repair` instead.
    """
    path = config_file()
    data = {}
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except ValueError:
            return False, "%s is not valid JSON; run `aether repair` first" % path
        except OSError as exc:
            return False, str(exc)
    if not isinstance(data, dict):
        return False, "%s does not contain a JSON object" % path
    data.setdefault(section, {})
    if not isinstance(data[section], dict):
        return False, "%s: '%s' is not an object" % (path, section)
    data[section][key] = value
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(data, fh, indent=4)
        fh.write("\n")
    os.replace(tmp, path)
    return True, path


def set_color_scheme(ctx: Context, mode: str) -> Tuple[bool, str]:
    """Tell GTK/libadwaita/portal-aware apps about the colour scheme."""
    if not ctx.which("gsettings"):
        return False, "gsettings not found (GTK apps keep their current scheme)"
    value = "prefer-dark" if mode == "dark" else "prefer-light"
    res = ctx.run(["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", value], timeout=5)
    if not res.ok:
        return False, (res.err or "gsettings failed").strip()
    return True, value
