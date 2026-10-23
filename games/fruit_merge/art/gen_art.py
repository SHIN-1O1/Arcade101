#!/usr/bin/env python3
"""Paints Fruit Fusion's art from scratch (original, CC0): 11 fruit skins, two light overlays and the
orchard backdrop. Needs numpy and Pillow. Run from the project root:

    python games/fruit_merge/art/gen_art.py

Fruit skins (fruit_<tier>.png) are albedo only, painted on a sphere so detail wraps around it; they turn
with the body. light_shade.png / light_spec.png are drawn on top without turning, so light always comes
from the top left. Every fruit canvas is SIZE px with the fruit disc of radius DISC in the middle
(game.gd draws it at (SIZE / DISC) x the fruit radius). Re-run after editing a recipe.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent
SIZE = 384          # output canvas
DISC = 120          # output disc radius (stems and leaves use the margin)
SS = 2              # supersampling
W = SIZE * SS
C = W / 2.0
R = DISC * SS


def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


# --- noise -----------------------------------------------------------------

def _hash(ix, iy, iz, seed):
    h = (ix * 374761393 + iy * 668265263 + iz * 2147483647 + seed * 1274126177) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


def vnoise(x, y, z, seed=0):
    ix, iy, iz = np.floor(x).astype(np.int64), np.floor(y).astype(np.int64), np.floor(z).astype(np.int64)
    fx, fy, fz = x - ix, y - iy, z - iz
    fx, fy, fz = [f * f * (3 - 2 * f) for f in (fx, fy, fz)]
    out = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (fx if dx else 1 - fx) * (fy if dy else 1 - fy) * (fz if dz else 1 - fz)
                out = out + w * _hash(ix + dx, iy + dy, iz + dz, seed)
    return out


def fbm(x, y, z, octaves=4, seed=0):
    total, amp, norm = 0, 0.5, 0
    for o in range(octaves):
        total = total + amp * vnoise(x, y, z, seed + o * 17)
        norm += amp
        x, y, z, amp = x * 2.03, y * 2.03, z * 2.03, amp * 0.5
    return total / norm


def worley(x, y, z, seed=0):
    """(F1, F2) distances to jittered cell points in 3D."""
    ix, iy, iz = np.floor(x).astype(np.int64), np.floor(y).astype(np.int64), np.floor(z).astype(np.int64)
    f1 = np.full(x.shape, 9.0)
    f2 = np.full(x.shape, 9.0)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for dz in (-1, 0, 1):
                cx, cy, cz = ix + dx, iy + dy, iz + dz
                px = cx + _hash(cx, cy, cz, seed)
                py = cy + _hash(cx, cy, cz, seed + 1)
                pz = cz + _hash(cx, cy, cz, seed + 2)
                d = np.sqrt((x - px) ** 2 + (y - py) ** 2 + (z - pz) ** 2)
                f2 = np.where(d < f1, f1, np.minimum(f2, d))
                f1 = np.minimum(f1, d)
    return f1, f2


# --- sphere frame ----------------------------------------------------------

yy, xx = np.mgrid[0:W, 0:W].astype(np.float64)
U = (xx + 0.5 - C) / R
V = (yy + 0.5 - C) / R
D2 = U * U + V * V
INSIDE = D2 <= 1.0
Z = np.sqrt(np.clip(1.0 - D2, 0.0, 1.0))
LON = np.arctan2(U, Z)               # around the vertical axis, 0 facing the viewer
LAT = np.arcsin(np.clip(-V, -1, 1))  # +pi/2 at the top pole


def mix(a, b, t):
    t = np.clip(t, 0, 1)[..., None]
    return a * (1 - t) + b * t


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def lit(col, amount):
    """Brighten (amount > 0) or darken a colour field by a scalar field."""
    a = amount[..., None]
    return np.where(a >= 0, col + (1 - col) * a, col * (1 + a))


RELIEF = {"amount": 0.0}  # set per fruit in main(); 0 = flat


def emboss(rgb, amount, mask=None):
    """Fake bump mapping: the fine detail (luminance minus its blur) is treated as height and lit from
    the top left, so dimples, pores, fibres and eyes read as raised or sunk, not printed on."""
    if amount <= 0:
        return rgb
    lum = np.clip(rgb.mean(axis=-1), 0, 1)
    if mask is None:
        mask = INSIDE
    li = Image.fromarray((lum * 255).astype(np.uint8))
    blur = np.asarray(li.filter(ImageFilter.GaussianBlur(R * 0.05)), dtype=np.float64) / 255.0
    h = (lum - blur) * mask
    gy, gx = np.gradient(h)
    shade = -(gx * -0.55 + gy * -0.75) * amount * R * 0.08
    rim = smooth(0.92, 1.0, np.sqrt(D2))  # fade out at the silhouette
    return lit(rgb, np.clip(shade * (1 - rim), -0.45, 0.45))


def disc_rgba(rgb):
    rgb = emboss(rgb, RELIEF["amount"])
    img = np.zeros((W, W, 4))
    img[..., :3] = np.clip(rgb, 0, 1)
    img[..., 3] = INSIDE.astype(float)
    return img


def to_image(img):
    """Supersampled float RGBA -> downsampled PIL image (premultiplied average for clean edges)."""
    a = img[..., 3:4]
    pm = np.concatenate([img[..., :3] * a, a], axis=-1)
    pm = pm.reshape(SIZE, SS, SIZE, SS, 4).mean(axis=(1, 3))
    alpha = pm[..., 3:4]
    rgb = np.where(alpha > 1e-4, pm[..., :3] / np.maximum(alpha, 1e-4), 0)
    out = np.concatenate([rgb, alpha], axis=-1)
    return Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


def to_canvas(img):
    """Float RGBA at supersampled size -> PIL (still supersampled) for drawing stems on."""
    return Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


def finish(pil):
    return pil.resize((SIZE, SIZE), Image.LANCZOS)


def P(x, y):
    """Disc-relative (x right, y down, 1 = radius) -> canvas pixel."""
    return (C + x * R, C + y * R)


def leaf(draw, base, tip, width, col, vein=True):
    bx, by = base
    tx, ty = tip
    dx, dy = tx - bx, ty - by
    nx, ny = -dy, dx
    pts_l, pts_r = [], []
    for i in range(13):
        t = i / 12.0
        w = np.sin(np.pi * t) ** 0.8 * width
        cx, cy = bx + dx * t, by + dy * t
        pts_l.append(P(cx + nx * w, cy + ny * w))
        pts_r.append(P(cx - nx * w, cy - ny * w))
    dark = tuple(int(c * 255) for c in col * 0.72) + (255,)
    light = tuple(int(c * 255) for c in np.clip(col * 1.12, 0, 1)) + (255,)
    draw.polygon(pts_l + pts_r[::-1], fill=dark)
    draw.polygon(pts_l + [P(tx, ty)] + [P(bx + dx * t / 12, by + dy * t / 12) for t in range(12, -1, -1)], fill=light)
    if vein:
        draw.line([P(bx, by), P(bx + dx * 0.92, by + dy * 0.92)], fill=tuple(int(c * 255) for c in col * 0.55) + (255,),
                  width=max(2, int(R * 0.025)))


def stem(draw, pts, width, col=hexc("#6B4226")):
    poly = [P(x, y) for x, y in pts]
    draw.line(poly, fill=tuple(int(c * 255) for c in col) + (255,), width=int(width * R), joint="curve")
    hl = tuple(int(c * 255) for c in np.clip(col * 1.5, 0, 1)) + (255,)
    draw.line([(x - width * R * 0.18, y) for x, y in poly], fill=hl, width=max(2, int(width * R * 0.3)))


def dimple(rgb, cy=-0.93, size=0.16, depth=0.35):
    d = np.sqrt(U ** 2 + (V - cy) ** 2)
    return lit(rgb, -depth * (1 - smooth(0, size, d)))


# --- fruits ----------------------------------------------------------------

def blueberry():  # dusty blue with a five-point crown
    n = fbm(U * 3, V * 3, Z * 3, 3, 1)
    rgb = mix(hexc("#16257A"), hexc("#4F7FF0"), 0.3 + 0.55 * Z + (-V) * 0.15 + (n - 0.5) * 0.4)
    bloom = fbm(U * 14, V * 14, Z * 14, 3, 2)
    rgb = mix(rgb, hexc("#B9CBF5"), smooth(0.4, 0.8, bloom) * 0.35)
    # crown: a dark star-shaped pit at the top
    ang = np.arctan2(U, V + 0.9)
    d = np.sqrt(U ** 2 + (V + 0.9) ** 2)
    star = 0.13 + 0.06 * np.cos(ang * 5)
    rgb = lit(rgb, -0.55 * (1 - smooth(star - 0.03, star + 0.02, d)))
    rgb = mix(rgb, hexc("#2A1F55"), (1 - smooth(0.03, 0.07, d)))
    return to_canvas(disc_rgba(rgb))


def cherry():  # bright glossy red, long stem and a leaf
    n = fbm(U * 3, V * 3, Z * 3, 3, 3)
    rgb = mix(hexc("#9A0016"), hexc("#FF2E45"), 0.35 + 0.6 * smooth(-0.2, 1.0, -V * 0.4 + Z * 0.8) + (n - 0.5) * 0.3)
    rgb = dimple(rgb, size=0.22, depth=0.45)
    im = to_canvas(disc_rgba(rgb))
    dr = ImageDraw.Draw(im)
    stem(dr, [(0, -0.9), (0.08, -1.2), (0.22, -1.42), (0.42, -1.55)], 0.07, hexc("#5A7A2A"))
    leaf(dr, (0.4, -1.52), (0.95, -1.42), 0.18, hexc("#3EB04A"))
    return im


def grape():  # violet-magenta with a frosty bloom
    n = fbm(U * 2.5, V * 2.5, Z * 2.5, 4, 4)
    rgb = mix(hexc("#4A0E63"), hexc("#B145D6"), 0.35 + 0.5 * Z + (n - 0.5) * 0.5)
    bloom = fbm(U * 16, V * 16, Z * 16, 3, 5)
    rgb = mix(rgb, hexc("#E2C4F2"), smooth(0.45, 0.8, bloom) * 0.25)
    rgb = dimple(rgb, size=0.12, depth=0.3)
    im = to_canvas(disc_rgba(rgb))
    dr = ImageDraw.Draw(im)
    stem(dr, [(0, -0.92), (-0.04, -1.15), (0.05, -1.3)], 0.09, hexc("#7A5A2E"))
    leaf(dr, (0.02, -1.2), (0.5, -1.45), 0.15, hexc("#4CAF50"))
    return im


def lemon():  # sunny yellow, pitted peel, pointed tips
    n = fbm(U * 3, V * 3, Z * 3, 3, 6)
    rgb = mix(hexc("#E0A800"), hexc("#FFEB55"), 0.35 + 0.55 * Z + (n - 0.5) * 0.4)
    pores = fbm(U * 26, V * 26, Z * 26, 2, 7)
    rgb = lit(rgb, (pores - 0.5) * 0.3)
    rgb = mix(rgb, hexc("#C9D94A"), smooth(0.65, 0.85, fbm(U * 2, V * 2, Z * 2, 2, 8)) * 0.25)
    im = to_canvas(disc_rgba(rgb))
    dr = ImageDraw.Draw(im)
    for sx in (-1, 1):  # little nubs at both ends
        pts = [P(sx * 0.94, -0.16), P(sx * 1.1, -0.03), P(sx * 1.1, 0.03), P(sx * 0.94, 0.16)]
        dr.polygon(pts, fill=(226, 190, 20, 255))
        dr.polygon([P(sx * 0.95, -0.09), P(sx * 1.07, -0.02), P(sx * 0.95, 0.0)], fill=(255, 232, 90, 255))
    leaf(dr, (0.0, -0.95), (0.45, -1.3), 0.15, hexc("#3E9F45"))
    return im


def orange():
    n = fbm(U * 3, V * 3, Z * 3, 3, 9)
    rgb = mix(hexc("#E85A00"), hexc("#FFAE2E"), 0.35 + 0.5 * Z + (n - 0.5) * 0.4)
    dimples = fbm(U * 22, V * 22, Z * 22, 2, 10)
    rgb = lit(rgb, (dimples - 0.5) * 0.4)
    oil = vnoise(U * 40, V * 40, Z * 40, 11)
    rgb = lit(rgb, -0.2 * smooth(0.82, 0.95, oil))
    rgb = dimple(rgb, size=0.13, depth=0.35)
    im = to_canvas(disc_rgba(rgb))
    dr = ImageDraw.Draw(im)
    for a in np.linspace(0, 2 * np.pi, 6, endpoint=False):
        leaf(dr, (0, -0.93), (np.cos(a) * 0.1, -0.93 + np.sin(a) * 0.05), 0.05, hexc("#5E8C2A"), False)
    stem(dr, [(0, -0.93), (0.03, -1.07)], 0.06, hexc("#5E8C2A"))
    leaf(dr, (0.03, -1.03), (0.55, -1.3), 0.16, hexc("#2E9B3E"))
    return im


def green_apple():  # crisp lime-green with a yellow blush and pale freckles
    n = fbm(U * 2.5, V * 2.5, Z * 2.5, 4, 12)
    streak = fbm(LON * 6, LAT * 0.8, Z * 0.3, 4, 13)
    rgb = mix(hexc("#3E8E12"), hexc("#A8E33E"), 0.4 + 0.45 * Z + (streak - 0.5) * 0.3)
    rgb = mix(rgb, hexc("#E8E35A"), smooth(0.55, 0.9, n * 0.6 + streak * 0.4 - V * 0.2) * 0.45)
    dots = vnoise(U * 30, V * 30, Z * 30, 14)
    rgb = mix(rgb, hexc("#F2F7C8"), smooth(0.9, 0.97, dots) * 0.7)
    rgb = dimple(rgb, size=0.26, depth=0.4)
    im = to_canvas(disc_rgba(rgb))
    dr = ImageDraw.Draw(im)
    stem(dr, [(0, -0.84), (-0.03, -1.05), (-0.1, -1.25)], 0.07)
    leaf(dr, (-0.06, -1.1), (-0.62, -1.32), 0.17, hexc("#2E8B3E"))
    return im


def pomegranate():  # deep crimson, mottled, with a crown of pointed sepals
    n = fbm(U * 2.2, V * 2.2, Z * 2.2, 4, 15)
    rgb = mix(hexc("#7A0A22"), hexc("#E8304E"), 0.35 + 0.5 * Z - V * 0.1 + (n - 0.5) * 0.5)
    mott = fbm(U * 3.5 + 5, V * 3.5, Z * 3.5, 4, 16)
    rgb = mix(rgb, hexc("#F08A5A"), smooth(0.58, 0.8, mott) * 0.35)
    fine = vnoise(U * 50, V * 50, Z * 50, 17)
    rgb = lit(rgb, (fine - 0.5) * 0.08)
    rgb = dimple(rgb, cy=-0.9, size=0.2, depth=0.3)
    im = to_canvas(disc_rgba(rgb))
    dr = ImageDraw.Draw(im)
    dr.polygon([P(-0.24, -0.88), P(-0.2, -1.06), P(0.2, -1.06), P(0.24, -0.88)], fill=(150, 20, 45, 255))
    for k in range(6):  # sepals
        x0 = -0.2 + k * 0.08
        dr.polygon([P(x0, -1.04), P(x0 + 0.04 - (0.06 if k < 3 else -0.06), -1.28), P(x0 + 0.08, -1.04)],
                   fill=(170, 28, 52, 255) if k % 2 else (120, 14, 38, 255))
    dr.ellipse([P(-0.12, -1.1)[0], P(-0.12, -1.1)[1], P(0.12, -0.98)[0], P(0.12, -0.98)[1]], fill=(70, 8, 22, 255))
    return im


def coconut():  # brown husk with fibrous streaks and three eyes
    n = fbm(U * 2, V * 2, Z * 2, 4, 18)
    rgb = mix(hexc("#4A2A12"), hexc("#A8703E"), 0.3 + 0.5 * Z + (n - 0.5) * 0.5)
    fib = fbm(LON * 30, LAT * 3, Z * 2, 4, 19)  # streaks along the meridians
    rgb = lit(rgb, (fib - 0.5) * 0.55)
    hair = vnoise(LON * 90, LAT * 8, Z * 4, 20)
    rgb = mix(rgb, hexc("#D9A86A"), smooth(0.78, 0.95, hair) * 0.5)
    for ex, ey in [(-0.12, -0.78), (0.12, -0.78), (0.0, -0.6)]:
        d = np.sqrt((U - ex) ** 2 + (V - ey) ** 2)
        rgb = mix(rgb, hexc("#24120A"), 1 - smooth(0.05, 0.08, d))
    return to_canvas(disc_rgba(rgb))


def pineapple():  # oval body of raised eyes, tall spiky crown
    ax = 0.86  # narrower than tall
    uu = U / ax
    d2 = uu * uu + V * V
    inside = d2 <= 1.0
    z = np.sqrt(np.clip(1 - d2, 0, 1))
    a = uu * 3.2 + V * 3.8
    b = uu * 3.2 - V * 3.8
    fa, fb = a - np.floor(a) - 0.5, b - np.floor(b) - 0.5
    cell = np.maximum(np.abs(fa), np.abs(fb))  # diamond eyes: 0 at the centre, 0.5 on the seam
    n = fbm(U * 3, V * 3, z * 3, 3, 21)
    rgb = mix(hexc("#D67A0E"), hexc("#FFD24A"), 0.35 + 0.5 * z + (n - 0.5) * 0.4)
    rgb = mix(rgb, hexc("#B9BE3A"), smooth(0.0, -0.9, V) * 0.35)  # greener towards the crown
    rgb = lit(rgb, 0.22 * (1 - smooth(0.0, 0.42, cell)) - 0.3 * smooth(0.36, 0.5, cell))  # each eye bulges
    rgb = mix(rgb, hexc("#7A8A22"), smooth(0.44, 0.5, cell) * 0.7)  # green seams
    sp = np.sqrt((fa - 0.17) ** 2 + (fb + 0.17) ** 2)  # small brown point low in each eye
    rgb = mix(rgb, hexc("#6B3A10"), (1 - smooth(0.05, 0.09, sp)) * 0.85)
    rgb = lit(rgb, 0.25 * (1 - smooth(0.0, 0.05, np.sqrt((fa - 0.13) ** 2 + (fb + 0.21) ** 2))))
    # Lit here, not by the shared round light layers (they would show a circle around the oval):
    # game.gd skips the overlays for tiers in SELF_LIT.
    L = np.array([-0.45, -0.65, 0.62]) / np.linalg.norm([-0.45, -0.65, 0.62])
    ndl = np.clip(uu * L[0] + V * L[1] + z * L[2], 0, 1)
    rgb = lit(rgb, -(1 - (0.2 + 0.8 * ndl)) * 0.55 - (1 - z) ** 2.2 * 0.3)
    Hh = (L + np.array([0, 0, 1.0])) / np.linalg.norm(L + np.array([0, 0, 1.0]))
    ndh = np.clip(uu * Hh[0] + V * Hh[1] + z * Hh[2], 0, 1)
    rgb = lit(rgb, ndh ** 40 * 0.6)
    rgb = emboss(rgb, RELIEF["amount"], inside)
    img = np.zeros((W, W, 4))
    img[..., :3] = np.clip(rgb, 0, 1)
    img[..., 3] = inside.astype(float)
    im = to_canvas(img)
    dr = ImageDraw.Draw(im)
    greens = [hexc("#1F7A3A"), hexc("#2E9B4A"), hexc("#45B860")]
    fan = [(-0.75, -1.18, 0.09), (0.75, -1.18, 0.09), (-0.6, -1.36, 0.1), (0.6, -1.36, 0.1),
           (-0.42, -1.5, 0.1), (0.42, -1.5, 0.1), (-0.22, -1.58, 0.1), (0.22, -1.58, 0.1),
           (-0.05, -1.6, 0.1), (0.08, -1.6, 0.1)]
    for k, (tx, ty, w) in enumerate(fan):
        leaf(dr, (tx * 0.12, -0.9), (tx, ty), w, greens[k % 3], False)
    for tx, ty in [(-0.3, -1.25), (0.3, -1.25), (0.0, -1.38)]:  # short inner leaves on top
        leaf(dr, (0.0, -0.92), (tx, ty), 0.08, greens[2], False)
    return im


def pumpkin():  # deep orange with ribs and a chunky curled stem
    n = fbm(U * 2, V * 2, Z * 2, 4, 22)
    rgb = mix(hexc("#C0440A"), hexc("#FF9A2A"), 0.3 + 0.55 * Z + (n - 0.5) * 0.4)
    rib = np.cos(LON * 9)
    rgb = lit(rgb, 0.18 * smooth(0.2, 1.0, rib) - 0.35 * smooth(-0.6, -1.0, rib))
    rgb = lit(rgb, -0.3 * (1 - smooth(0.0, 0.45, np.abs(V + 0.95))))  # sunk top
    rgb = lit(rgb, -0.2 * (1 - smooth(0.0, 0.35, np.abs(V - 0.97))))
    im = to_canvas(disc_rgba(rgb))
    dr = ImageDraw.Draw(im)
    dr.polygon([P(-0.12, -0.86), P(-0.1, -1.18), P(0.04, -1.3), P(0.16, -1.24), P(0.1, -0.86)], fill=(92, 110, 40, 255))
    dr.polygon([P(-0.04, -0.9), P(-0.04, -1.16), P(0.04, -1.22), P(0.04, -0.9)], fill=(130, 150, 60, 255))
    stem(dr, [(0.12, -1.18), (0.38, -1.22), (0.5, -1.4), (0.36, -1.48)], 0.035, hexc("#4F8A2A"))
    leaf(dr, (0.1, -1.0), (0.62, -1.15), 0.15, hexc("#3E9F45"))
    return im


def watermelon():
    n = fbm(U * 2, V * 2, Z * 2, 4, 23)
    rgb = mix(hexc("#3FAE3A"), hexc("#94E06A"), 0.3 + 0.5 * Z + (n - 0.5) * 0.5)
    wob = fbm(LON * 3, LAT * 8, Z, 4, 24)
    stripe = np.sin(LON * 8 + (wob - 0.5) * 3.2)
    edge = (fbm(LON * 9, LAT * 22, Z, 3, 25) - 0.5) * 0.5
    dark = smooth(0.15 + edge, 0.35 + edge, stripe)
    rgb = mix(rgb, hexc("#0C5A24"), dark * 0.92)
    speck = fbm(U * 18, V * 18, Z * 18, 2, 26)
    rgb = lit(rgb, (speck - 0.5) * 0.16)
    rgb = dimple(rgb, size=0.1, depth=0.4)
    im = to_canvas(disc_rgba(rgb))
    dr = ImageDraw.Draw(im)
    stem(dr, [(0, -0.95), (0.06, -1.12), (0.18, -1.2)], 0.06, hexc("#5E7A2A"))
    leaf(dr, (0.12, -1.16), (0.55, -1.38), 0.14, hexc("#3E9F45"))
    return im


# Distinct hue (and silhouette) per tier, smallest first: blue, red, violet, yellow, orange, green,
# crimson with a crown, brown, gold oval, ribbed orange, striped green. Keep game.gd COLORS (burst particles) in step with these.
# relief strength per fruit (see emboss): smooth skins low, pitted or fibrous ones high
RELIEF_BY = {"blueberry": 0.6, "cherry": 0.3, "grape": 0.5, "lemon": 1.6, "orange": 1.1, "green_apple": 0.6,
             "pomegranate": 0.9, "coconut": 2.0, "pineapple": 2.2, "pumpkin": 1.4, "watermelon": 0.9}
SELF_LIT = [8]  # pineapple: oval, lit in its own recipe
FRUITS = [blueberry, cherry, grape, lemon, orange, green_apple, pomegranate, coconut, pineapple, pumpkin, watermelon]


# --- light overlays --------------------------------------------------------

def light_layers():
    L = np.array([-0.45, -0.65, 0.62])
    L = L / np.linalg.norm(L)
    ndl = np.clip(U * L[0] + V * L[1] + Z * L[2], 0, 1)
    shade = (1 - (0.2 + 0.8 * ndl)) * 0.55 + (1 - Z) ** 2.2 * 0.3
    shade += smooth(0.2, 1.0, V) * 0.14  # contact occlusion at the bottom
    s = np.zeros((W, W, 4))
    s[..., 3] = np.clip(shade, 0, 0.85) * INSIDE
    H = L + np.array([0, 0, 1.0])
    H = H / np.linalg.norm(H)
    ndh = np.clip(U * H[0] + V * H[1] + Z * H[2], 0, 1)
    spec = ndh ** 90 * 0.95 + ndh ** 12 * 0.28
    rim = (1 - Z) ** 3 * np.clip(U * 0.5 + V * 0.6, 0, 1) * 0.65  # cool bounce light, bottom right
    p = np.zeros((W, W, 4))
    p[..., :3] = 1.0
    p[..., 3] = np.clip(spec + rim, 0, 1) * INSIDE
    return finish(to_canvas(s)), finish(to_canvas(p))


# --- backdrop --------------------------------------------------------------

def backdrop(w=540, h=960):
    s = 2
    W2, H2 = w * s, h * s
    y = np.linspace(0, 1, H2)[:, None] * np.ones((1, W2))
    x = np.ones((H2, 1)) * np.linspace(0, 1, W2)[None, :]
    sky = mix(hexc("#1d1f33")[None, None, :] * np.ones((H2, W2, 3)), hexc("#3B2C7A"), smooth(0.0, 0.62, y))
    sky = mix(sky, hexc("#7A3E8C"), smooth(0.45, 0.72, y) * 0.55)
    sun = np.exp(-(((x - 0.72) * 1.6) ** 2 + ((y - 0.6) * 1.1) ** 2) * 9)
    sky = mix(sky, hexc("#FF8A1F"), sun * 0.55)
    sky = mix(sky, hexc("#FFD23F"), np.exp(-(((x - 0.72) * 1.6) ** 2 + ((y - 0.6) * 1.1) ** 2) * 60) * 0.6)
    img = Image.fromarray((np.clip(sky, 0, 1) * 255).astype(np.uint8), "RGB").convert("RGBA")
    rng = np.random.default_rng(3)
    dr = ImageDraw.Draw(img)
    for _ in range(90):  # stars in the upper sky
        sx, sy = rng.uniform(0, W2), rng.uniform(0, H2 * 0.45)
        r = rng.uniform(1.0, 3.2)
        a = int(rng.uniform(60, 200) * (1 - sy / (H2 * 0.45)))
        dr.ellipse([sx - r, sy - r, sx + r, sy + r], fill=(255, 245, 220, a))

    def hill(base, amp, freq, phase, col, trees, tree_col, fruit_cols):
        xs = np.linspace(0, W2, 200)
        ys = H2 * (base - amp * np.sin(xs / W2 * np.pi * freq + phase) - amp * 0.4 * np.sin(xs / W2 * 7 + phase * 2))
        layer = Image.new("RGBA", (W2, H2), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        for i in range(trees):  # round orchard trees on the ridge
            tx = rng.uniform(0, W2)
            ty = float(np.interp(tx, xs, ys))
            tr = rng.uniform(0.035, 0.06) * W2
            ld.rectangle([tx - tr * 0.12, ty - tr * 0.8, tx + tr * 0.12, ty + 4], fill=tree_col)
            for k in range(4):
                ox, oy = rng.uniform(-0.45, 0.45) * tr, rng.uniform(-0.35, 0.2) * tr
                cr = tr * rng.uniform(0.55, 0.8)
                ld.ellipse([tx + ox - cr, ty - tr * 1.2 + oy - cr, tx + ox + cr, ty - tr * 1.2 + oy + cr], fill=tree_col)
            for k in range(5):
                fx, fy = tx + rng.uniform(-0.7, 0.7) * tr, ty - tr * 1.2 + rng.uniform(-0.6, 0.5) * tr
                fr = tr * 0.11
                ld.ellipse([fx - fr, fy - fr, fx + fr, fy + fr], fill=fruit_cols[k % len(fruit_cols)])
        ld.polygon([(0, H2)] + list(zip(xs, ys)) + [(W2, H2)], fill=col)
        rim = [(px, py) for px, py in zip(xs, ys)]
        ld.line(rim, fill=tuple(min(255, c + 40) for c in col[:3]) + (120,), width=4)
        return layer

    img.alpha_composite(hill(0.66, 0.035, 2.2, 0.4, (78, 52, 128, 255), 6, (64, 44, 112, 255),
                             [(255, 138, 31, 140), (255, 210, 63, 140)]))
    img = img.filter(ImageFilter.GaussianBlur(1.2))
    img.alpha_composite(hill(0.76, 0.04, 1.6, 2.0, (52, 38, 104, 255), 5, (44, 32, 90, 255),
                             [(255, 138, 31, 200), (255, 90, 110, 190), (255, 210, 63, 200)]))
    img.alpha_composite(hill(0.88, 0.03, 2.8, 4.1, (32, 26, 72, 255), 4, (27, 22, 62, 255),
                             [(255, 138, 31, 230), (255, 210, 63, 230)]))
    glow = Image.new("RGBA", (W2, H2), (0, 0, 0, 0))  # soft bokeh drifting over everything
    gd = ImageDraw.Draw(glow)
    for _ in range(26):
        bx, by = rng.uniform(0, W2), rng.uniform(0, H2)
        br = rng.uniform(0.02, 0.07) * W2
        col = [(255, 210, 63), (255, 138, 31), (180, 160, 255)][rng.integers(0, 3)]
        gd.ellipse([bx - br, by - br, bx + br, by + br], fill=col + (int(rng.uniform(10, 26)),))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(10)))
    return img.convert("RGB").resize((w, h), Image.LANCZOS)


def main():
    for i, fn in enumerate(FRUITS):
        RELIEF["amount"] = RELIEF_BY.get(fn.__name__, 0.8)
        finish(fn()).save(OUT / f"fruit_{i}.png", optimize=True)
        print("fruit", i, fn.__name__)
    shade, spec = light_layers()
    shade.save(OUT / "light_shade.png", optimize=True)
    spec.save(OUT / "light_spec.png", optimize=True)
    backdrop().save(OUT / "backdrop.png", optimize=True)
    print("done")


if __name__ == "__main__":
    main()
