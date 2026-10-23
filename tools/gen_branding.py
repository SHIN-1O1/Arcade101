#!/usr/bin/env python3
"""Generates every branding image from code (no copied assets): launcher icon layers, splash,
Play Store icon and feature graphic.  Run:  python tools/gen_branding.py   (needs Pillow + numpy)

Writes to branding/ (used by the game and export), store/graphics/ (Play Console uploads) plus icon.svg (editor icon) in the project root.  Palette = Fruit Pop,
font = core/fonts/LilitaOne-Regular.ttf (OFL).  Output is deterministic, so rerunning only
changes files when this script changes.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "branding")  # imported by Godot: launcher icon layers + boot splash
STORE = os.path.join(ROOT, "store", "graphics")  # Play Console uploads; .gdignore keeps them out of the game
FONT = os.path.join(ROOT, "core", "fonts", "LilitaOne-Regular.ttf")

INDIGO = (0x2B, 0x2A, 0x6B)
TANGERINE = (0xFF, 0x8A, 0x1F)
LEMON = (0xFF, 0xD2, 0x3F)
SS = 4  # supersampling factor


def font(px):
    return ImageFont.truetype(FONT, int(px))


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def lerp_img(size, c0, c1, vertical=True):
    w, h = size
    t = np.linspace(0, 1, h if vertical else w)
    arr = np.array([mix(c0, c1, x) for x in t], dtype=np.uint8)
    arr = np.repeat(arr[:, None, :], w, axis=1) if vertical else np.repeat(arr[None, :, :], h, axis=0)
    return Image.fromarray(arr, "RGB").convert("RGBA")


NIGHT = (0x0C, 0x0A, 0x22)
PANEL = (0x16, 0x12, 0x3A)
PINK = (0xFF, 0x4F, 0xD8)
CYAN = (0x3D, 0xF5, 0xFF)


def glow(img, draw_fn, color, radii=(0.03, 0.012), strength=(0.9, 1.0)):
    """Neon look: draw_fn(draw, color) on a scratch layer, blur it at several radii, stack, then the sharp core."""
    w, h = img.size
    base = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(base), color + (255,))
    for r, k in zip(radii, strength):
        blur = base.filter(ImageFilter.GaussianBlur(max(1, w * r)))
        a = blur.getchannel("A").point(lambda v: min(255, int(v * 1.6 * k)))
        blur.putalpha(a)
        img.alpha_composite(blur)
    img.alpha_composite(base)


def background(size):
    """Synthwave night: indigo sky, striped sun on the horizon, perspective neon grid (like the hub)."""
    w, h = size
    img = lerp_img(size, NIGHT, mix(INDIGO, NIGHT, 0.35))
    hy = h * 0.62
    sun = Image.new("RGBA", size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(sun)
    rad = min(w, h) * 0.34
    cx, cy = w / 2, hy - rad * 0.25
    bands = 16
    for i in range(bands):
        y0 = cy - rad + i * (rad * 2 / bands)
        k = i / bands
        gap = 0 if k < 0.4 else (k - 0.4) * 1.1
        y1 = y0 + rad * 2 / bands
        ym = min(y1 - (y1 - y0) * gap, hy)
        if y0 >= hy or ym <= y0 + 0.5:
            continue
        col = mix(LEMON, PINK, min(1, k * 1.25))
        sd.rectangle([cx - rad, y0, cx + rad, ym], fill=col + (255,))
    # clip the stripes to the circle
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=255)
    sun.putalpha(Image.fromarray(np.minimum(np.array(sun.getchannel("A")), np.array(mask))))
    halo = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(halo).ellipse([cx - rad * 1.5, cy - rad * 1.5, cx + rad * 1.5, cy + rad * 1.5], fill=PINK + (70,))
    img.alpha_composite(halo.filter(ImageFilter.GaussianBlur(w * 0.08)))
    img.alpha_composite(sun)
    # floor
    floor = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(floor).rectangle([0, hy, w, h], fill=NIGHT + (255,))
    img.alpha_composite(floor)
    grid = Image.new("RGBA", size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(grid)
    for i in range(-9, 10):
        gd.line([(w / 2 + i * w * 0.035, hy), (w / 2 + i * w * 0.32, h)], fill=PINK + (150,), width=max(1, w // 200))
    for j in range(1, 10):
        z = j / 9
        y = hy + (h - hy) * z * z
        gd.line([(0, y), (w, y)], fill=PINK + (int(60 + 140 * z),), width=max(1, w // 200))
    img.alpha_composite(grid.filter(ImageFilter.GaussianBlur(w * 0.004)))
    img.alpha_composite(grid)
    hl = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(hl).line([(0, hy), (w, hy)], fill=mix(PINK, (255, 255, 255), 0.5) + (230,), width=max(2, w // 120))
    glow_layer = hl.filter(ImageFilter.GaussianBlur(w * 0.01))
    img.alpha_composite(glow_layer)
    img.alpha_composite(hl)
    return img


def star_points(cx, cy, r, inner=0.48, rot=-90):
    pts = []
    for i in range(10):
        rr = r if i % 2 == 0 else r * inner
        a = math.radians(rot + i * 36)
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    return pts


def neon_text(img, center, text, size, color, core=None):
    """Glowing sign lettering: blurred colour halo, bright near-white core with a coloured edge."""
    f = font(size)
    core = core or mix(color, (255, 255, 255), 0.78)
    sw = max(1, int(size * 0.035))

    def draw(d, col):
        d.text(center, text, font=f, fill=col, anchor="mm", stroke_width=max(1, int(size * 0.05)), stroke_fill=col)
    glow(img, draw, color, radii=(0.035, 0.012), strength=(0.8, 1.0))
    ImageDraw.Draw(img).text(center, text, font=f, fill=core + (255,), anchor="mm", stroke_width=sw, stroke_fill=color + (255,))


def emblem(size, mono=False):
    """The icon mark on a transparent canvas: a dark neon-ringed disc with a glowing '101' and a star.
    Everything sits inside the central 66% so any adaptive mask (circle, squircle) keeps it."""
    S = size * SS
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cx = cy = S // 2
    r = S * 0.30
    if mono:
        d = ImageDraw.Draw(canvas)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255, 255))
        cut = Image.new("L", (S, S), 0)
        ImageDraw.Draw(cut).text((cx, cy + S * 0.01), "101", font=font(S * 0.27), fill=255, anchor="mm")
        alpha = np.array(canvas.getchannel("A"), dtype=np.int16) - np.array(cut, dtype=np.int16)
        canvas.putalpha(Image.fromarray(np.clip(alpha, 0, 255).astype(np.uint8)))
        ImageDraw.Draw(canvas).polygon(star_points(cx + r * 0.78, cy - r * 0.78, S * 0.075), fill=(255, 255, 255, 255))
    else:
        disc = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(disc).ellipse([cx - r, cy - r, cx + r, cy + r], fill=NIGHT + (235,))
        canvas.alpha_composite(disc)
        ring = max(3, int(S * 0.016))
        glow(canvas, lambda d, c: d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=c, width=ring), PINK, radii=(0.03, 0.01))
        r2 = r * 0.86
        glow(canvas, lambda d, c: d.ellipse([cx - r2, cy - r2, cx + r2, cy + r2], outline=c, width=max(2, ring // 2)), CYAN, radii=(0.02, 0.006))
        neon_text(canvas, (cx, cy + S * 0.01), "101", S * 0.27, LEMON)
        sx, sy = cx + r * 0.78, cy - r * 0.78
        glow(canvas, lambda d, c: d.polygon(star_points(sx, sy, S * 0.085), fill=c), LEMON, radii=(0.025, 0.008))
    return canvas.resize((size, size), Image.LANCZOS)


def title_lockup(width):
    """'ARCADE' (neon pink) over '101' (lemon), the hub heading."""
    S = SS
    w, h = width * S, int(width * 0.62) * S
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    neon_text(img, (w // 2, int(h * 0.30)), "ARCADE", w * 0.2, PINK)
    neon_text(img, (w // 2, int(h * 0.74)), "101", w * 0.34, LEMON)
    return img.resize((width, h // S), Image.LANCZOS)


def rounded(img, radius_frac):
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, img.size[0] - 1, img.size[1] - 1],
                                        radius=int(img.size[0] * radius_frac), fill=255)
    out = img.copy()
    out.putalpha(m)
    return out


def save(img, name, out=OUT):
    img.save(os.path.join(out, name), optimize=True)
    print("wrote", os.path.relpath(os.path.join(out, name), ROOT))


def store_icon():
    base = background((512, 512))
    base.alpha_composite(emblem(512))
    return base


def feature_graphic():
    w, h = 1024, 500
    img = background((w, h))
    img.alpha_composite(emblem(430), (40, 35))
    img.alpha_composite(title_lockup(520), (450, 60))
    neon_text(img, (710, 425), "Offline puzzle & arcade games", 36, CYAN)
    return img


def splash():
    """Shown on a solid night boot_splash/bg_color; transparent so the colour fills the rest."""
    s = 720
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    img.alpha_composite(emblem(380), ((s - 380) // 2, 10))
    img.alpha_composite(title_lockup(560), ((s - 560) // 2, 330))
    return img


def icon_svg():
    """Vector editor icon (shown in the Godot editor / Windows, not the Android launcher)."""
    return """<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
<defs>
<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2b2a6b"/><stop offset="1" stop-color="#0c0a22"/></linearGradient>
<filter id="g" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="3"/></filter>
</defs>
<rect width="128" height="128" rx="28" fill="url(#bg)"/>
<circle cx="64" cy="66" r="40" fill="#16123a" stroke="#ff4fd8" stroke-width="4" filter="url(#g)"/>
<circle cx="64" cy="66" r="40" fill="#0c0a22" stroke="#ff4fd8" stroke-width="3"/>
<circle cx="64" cy="66" r="34" fill="none" stroke="#3df5ff" stroke-width="1.5"/>
<text x="64" y="80" font-family="sans-serif" font-weight="900" font-size="38" text-anchor="middle" fill="#fff6c8" stroke="#ffd23f" stroke-width="1.5">101</text>
<polygon points="STAR" fill="#ffd23f"/>
</svg>
""".replace("STAR", " ".join(f"{x:.1f},{y:.1f}" for x, y in star_points(98, 30, 12)))


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(STORE, exist_ok=True)
    open(os.path.join(ROOT, "store", ".gdignore"), "w").close()
    bg = background((432, 432))
    save(bg, "icon_background_432.png")
    save(emblem(432), "icon_foreground_432.png")
    save(emblem(432, mono=True), "icon_monochrome_432.png")
    # legacy launcher icon (Godot also uses it for older Android): full composite, rounded corners
    # emblem is drawn small inside the safe zone; for the legacy icon scale it up to fill the tile
    big = emblem(288).resize((192, 192), Image.LANCZOS)
    legacy = background((192, 192))
    legacy.alpha_composite(big)
    save(rounded(legacy, 0.22), "icon_legacy_192.png")
    save(store_icon(), "play_store_icon_512.png", STORE)
    save(feature_graphic().convert("RGB"), "play_feature_graphic_1024x500.png", STORE)
    save(splash(), "splash.png")
    with open(os.path.join(ROOT, "icon.svg"), "w") as f:
        f.write(icon_svg())
    print("wrote icon.svg")


if __name__ == "__main__":
    main()
