#!/usr/bin/env python3
"""Draw an approximate preview of an AetherOS Hyprlock design (no Hyprlock needed).

Reads the same files Hyprlock reads — the generated colours
(~/.config/aether-shell/classic/colors/hyprlock.conf) and a design from
config/hypr/hyprlock/ — and draws the background, labels (running their
cmd[...] commands), shapes and the password field with Pillow.

It is a preview, not Hyprlock: font metrics, blur and anti-aliasing differ a
little, and the password field is drawn empty. Use `aether-lock try` to see
the real thing.

  tools/preview-lockscreen.py DESIGN OUT.png [--size 1920x1080] [--colors FILE] [--wallpaper FILE]
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

REPO = Path(__file__).resolve().parents[1]
FONT_DIRS = [Path.home() / ".local/share/fonts", Path("/usr/local/share/fonts"), Path("/usr/share/fonts")]
SCALE = 1.33  # Hyprlock font sizes are points at 96 dpi


def find_font(family: str) -> str:
    weight = "Regular"
    for w in ("ExtraBold", "Bold", "Light", "Thin", "Italic"):
        if family.strip().endswith(w):
            weight = w
    for d in FONT_DIRS:
        for p in d.rglob("JetBrainsMonoNerdFont-%s.ttf" % weight):
            return str(p)
    for d in FONT_DIRS:
        for p in d.rglob("*.ttf"):
            return str(p)
    raise SystemExit("no TrueType font found")


def parse_color(v: str) -> tuple[int, int, int, int]:
    v = v.strip()
    m = re.match(r"rgba\(([0-9a-fA-F]{6})([0-9a-fA-F]{2})\)", v)
    if m:
        h = m.group(1)
        return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), int(m.group(2), 16)
    m = re.match(r"rgba\((\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)", v)
    if m:
        return int(m.group(1)), int(m.group(2)), int(m.group(3)), int(float(m.group(4)) * 255)
    m = re.match(r"#?([0-9a-fA-F]{6})", v)
    if m:
        h = m.group(1)
        return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255
    return 255, 255, 255, 255


def parse(text: str, variables: dict) -> list[tuple[str, dict]]:
    widgets, cur = [], None
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].rstrip() if not raw.strip().startswith("text") and "placeholder_text" not in raw \
            and "fail_text" not in raw else raw.rstrip()
        s = line.strip()
        if not s:
            continue
        m = re.match(r"^\$(\w+)\s*=\s*(.*)$", s)
        if m and cur is None:
            variables[m.group(1)] = m.group(2).strip()
            continue
        m = re.match(r"^([a-z-]+)\s*\{$", s)
        if m:
            cur = (m.group(1), {})
            continue
        if s == "}" and cur:
            widgets.append(cur)
            cur = None
            continue
        if cur and "=" in s:
            k, v = s.split("=", 1)
            cur[1][k.strip()] = v.strip()
    return widgets


def expand(v: str, variables: dict) -> str:
    return re.sub(r"\$([a-z0-9_]+)", lambda m: variables.get(m.group(1), m.group(0)), v)


def label_text(raw: str, variables: dict) -> str:
    m = re.match(r"cmd\[[^\]]*\]\s*(.*)$", raw)
    if m:
        try:
            out = subprocess.run(["bash", "-c", m.group(1)], capture_output=True, text=True, timeout=5,
                                 env=dict(os.environ, PATH=str(REPO / "scripts/bin") + ":" + os.environ.get("PATH", ""))).stdout
        except subprocess.TimeoutExpired:
            out = ""
        txt = out.strip()
    else:
        txt = raw
    txt = txt.replace("$USER", os.environ.get("USER", "user"))
    return re.sub(r"<[^>]+>", "", expand(txt, variables))


def place(W: int, H: int, w: int, h: int, pos: str, halign: str, valign: str) -> tuple[int, int]:
    x, y = (int(float(p)) for p in (pos or "0, 0").split(","))
    X = {"left": x, "right": W - w + x}.get(halign, W // 2 - w // 2 + x)
    Y = {"top": -y, "bottom": H - h - y}.get(valign, H // 2 - h // 2 - y)
    return X, Y


def render(design: Path, colors: Path, out: Path, size: tuple[int, int], wallpaper: str | None) -> None:
    W, H = size
    variables: dict = {}
    parse(colors.read_text(encoding="utf-8"), variables)
    variables.setdefault("font", "JetBrainsMono Nerd Font")
    if wallpaper:
        variables["wallpaper"] = wallpaper
    widgets = parse(design.read_text(encoding="utf-8"), variables)
    img = Image.new("RGBA", (W, H), (16, 18, 24, 255))
    draw = ImageDraw.Draw(img)
    for kind, p in widgets:
        p = {k: expand(v, variables) for k, v in p.items()}
        if kind == "background":
            path = p.get("path", "")
            if path and os.path.isfile(path):
                bg = ImageOps.fit(Image.open(path).convert("RGBA"), (W, H))
                passes, bsize = int(p.get("blur_passes", 0) or 0), int(p.get("blur_size", 0) or 0)
                if passes and bsize:
                    bg = bg.filter(ImageFilter.GaussianBlur(passes * bsize * 0.9))
                br = float(p.get("brightness", 1) or 1)
                bg = Image.eval(bg.convert("RGB"), lambda c, b=br: int(c * b)).convert("RGBA")
                img.paste(bg)
            else:
                img.paste(Image.new("RGBA", (W, H), parse_color(p.get("color", "rgba(101218ff)"))))
            draw = ImageDraw.Draw(img)
        elif kind == "shape":
            w, h = (int(v) for v in p.get("size", "100, 40").split(","))
            X, Y = place(W, H, w, h, p.get("position"), p.get("halign", "center"), p.get("valign", "center"))
            r = int(p.get("rounding", 0) or 0)
            r = min(w, h) // 2 if r < 0 else r
            layer = Image.new("RGBA", (W, H))
            ImageDraw.Draw(layer).rounded_rectangle([X, Y, X + w, Y + h], r, fill=parse_color(p.get("color", "")),
                                                    outline=parse_color(p["border_color"]) if p.get("border_size") else None,
                                                    width=int(p.get("border_size", 0) or 0))
            img = Image.alpha_composite(img, layer)
            draw = ImageDraw.Draw(img)
        elif kind == "label":
            txt = label_text(p.get("text", ""), variables)
            if not txt:
                continue
            font = ImageFont.truetype(find_font(p.get("font_family", variables["font"])), int(int(p.get("font_size", 16)) * SCALE))
            box = draw.multiline_textbbox((0, 0), txt, font=font)
            w, h = box[2] - box[0], box[3] - box[1]
            X, Y = place(W, H, w, h, p.get("position"), p.get("halign", "center"), p.get("valign", "center"))
            layer = Image.new("RGBA", (W, H))
            ImageDraw.Draw(layer).multiline_text((X - box[0], Y - box[1]), txt, font=font, fill=parse_color(p.get("color", "")),
                                                 align="center")
            img = Image.alpha_composite(img, layer)
            draw = ImageDraw.Draw(img)
        elif kind == "input-field":
            w, h = (int(v) for v in p.get("size", "300, 50").split(","))
            X, Y = place(W, H, w, h, p.get("position"), p.get("halign", "center"), p.get("valign", "center"))
            r = int(p.get("rounding", -1) or 0)
            r = h // 2 if r < 0 else r
            t = int(p.get("outline_thickness", 2) or 0)
            layer = Image.new("RGBA", (W, H))
            ImageDraw.Draw(layer).rounded_rectangle([X, Y, X + w, Y + h], r, fill=parse_color(p.get("inner_color", "")),
                                                    outline=parse_color(p.get("outer_color", "")) if t else None, width=t)
            ph = re.sub(r"<[^>]+>", "", p.get("placeholder_text", ""))
            if ph:
                font = ImageFont.truetype(find_font(variables["font"]), int(h * 0.36))
                box = ImageDraw.Draw(layer).textbbox((0, 0), ph, font=font)
                col = parse_color(p.get("font_color", ""))
                ImageDraw.Draw(layer).text((X + (w - (box[2] - box[0])) // 2 - box[0], Y + (h - (box[3] - box[1])) // 2 - box[1]),
                                           ph, font=font, fill=col[:3] + (150,))
            img = Image.alpha_composite(img, layer)
            draw = ImageDraw.Draw(img)
    img.convert("RGB").save(out)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("design")
    ap.add_argument("out")
    ap.add_argument("--size", default="1920x1080")
    ap.add_argument("--colors", default=str(Path.home() / ".config/aether-shell/classic/colors/hyprlock.conf"))
    ap.add_argument("--wallpaper")
    a = ap.parse_args()
    design = Path(a.design) if a.design.endswith(".conf") else REPO / "config/hypr/hyprlock" / (a.design + ".conf")
    w, h = (int(v) for v in a.size.lower().split("x"))
    render(design, Path(a.colors), Path(a.out), (w, h), a.wallpaper)
    print(a.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
