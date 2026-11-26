"""Paints NotchIsland's wallpaper library: 15 light and 15 dark original wallpapers.

Every image is drawn from math (gradients, curves, noise), so the library is free
of third-party copyright and can be regenerated at any size.

    python3 scripts/wallpapers/generate.py            # full size into Packaging/Wallpapers
    python3 scripts/wallpapers/generate.py --preview  # small contact sheet only

Requires numpy and Pillow.
"""
import argparse
import json
import math
import pathlib

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "Packaging" / "Wallpapers"
WIDTH, HEIGHT = 3456, 2234  # 16-inch MacBook Pro native resolution
THUMB = (432, 280)


def rgb(hex_color):
    h = hex_color.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], dtype=np.float32)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


class Canvas:
    def __init__(self, w, h, seed):
        self.w, self.h = w, h
        self.aspect = w / h
        ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
        self.x = xs / (w - 1)          # 0 left .. 1 right
        self.y = ys / (h - 1)          # 0 top .. 1 bottom
        self.rng = np.random.default_rng(seed)

    def vertical(self, top, bottom):
        t = self.y[..., None]
        return rgb(top) * (1 - t) + rgb(bottom) * t

    def diagonal(self, a, b):
        t = np.clip((self.x * self.aspect + self.y) / (self.aspect + 1), 0, 1)[..., None]
        return rgb(a) * (1 - t) + rgb(b) * t


def blend(img, color, weight):
    w = weight[..., None]
    return img * (1 - w) + rgb(color) * w if isinstance(color, str) else img * (1 - w) + color * w


# ---------------------------------------------------------------- styles

def mesh(c, base, blobs, base2=None):
    """Soft color blobs over a base: (x, y, radius, color, strength)."""
    img = c.vertical(base, base2 or base)
    for bx, by, r, color, s in blobs:
        d2 = ((c.x - bx) * c.aspect) ** 2 + (c.y - by) ** 2
        img = blend(img, color, s * np.exp(-d2 / (2 * r * r)))
    return img


def waves(c, top, bands, base_y=0.35, spread=0.14, amp=0.05, shade=0.10, freq=1.1):
    """Layered wave bands from top to bottom, each a bit lower and darker/lighter."""
    img = c.vertical(top, top)
    for i, color in enumerate(bands):
        phase = c.rng.uniform(0, math.tau)
        y0 = base_y + i * spread
        edge = (y0 + amp * np.sin(c.x * math.tau * freq + phase)
                + amp * 0.45 * np.sin(c.x * math.tau * freq * 2.3 + phase * 1.7))
        inside = smoothstep(edge - 0.002, edge + 0.002, c.y)
        # Soft shadow just inside each band's top edge gives depth.
        depth = np.clip((c.y - edge) / 0.06, 0, 1)
        tone = rgb(color) * (1 - shade * (1 - depth))[..., None]
        img = img * (1 - inside[..., None]) + tone * inside[..., None]
    return img


def dunes(c, top, bands, base_y=0.3):
    """Waves with sharp crests, like sand dunes."""
    img = c.vertical(top, top)
    for i, color in enumerate(bands):
        phase = c.rng.uniform(0, math.tau)
        y0 = base_y + i * 0.15
        crest = 1 - np.abs(np.sin(c.x * math.pi * 1.3 + phase))
        edge = y0 + 0.07 * crest + 0.02 * np.sin(c.x * math.tau * 2.7 + phase)
        inside = smoothstep(edge - 0.0015, edge + 0.0015, c.y)
        side = 0.5 + 0.5 * np.cos(c.x * math.pi * 1.3 * 2 + phase * 2)
        tone = rgb(color)[None, None, :] * (0.92 + 0.08 * side)[..., None]
        img = img * (1 - inside[..., None]) + tone * inside[..., None]
    return img


def hills(c, sky_top, sky_bottom, layers, start=0.45):
    """Layered hill silhouettes, nearer layers lower on screen."""
    img = c.vertical(sky_top, sky_bottom)
    for i, color in enumerate(layers):
        phase = c.rng.uniform(0, math.tau)
        y0 = start + i * 0.1
        edge = (y0 - 0.06 * np.sin(c.x * math.pi * (1.2 + i * 0.35) + phase)
                - 0.02 * np.sin(c.x * math.tau * (2.1 + i) + phase))
        inside = smoothstep(edge - 0.0015, edge + 0.0015, c.y)
        haze = np.clip((c.y - edge) / 0.35, 0, 1)[..., None]
        tone = rgb(color) * (1 - 0.15 * haze)
        img = img * (1 - inside[..., None]) + tone * inside[..., None]
    return img


def ribbons(c, base, base2, ribbon_list, glow=0.35):
    """Smooth glowing ribbons: (y, amplitude, width, color_a, color_b)."""
    img = c.vertical(base, base2)
    for y0, amp, width, ca, cb in ribbon_list:
        phase = c.rng.uniform(0, math.tau)
        center = y0 + amp * np.sin(c.x * math.pi * 1.6 + phase) + amp * 0.3 * np.sin(c.x * math.tau * 1.9)
        d = np.abs(c.y - center)
        body = 1 - smoothstep(width * 0.55, width, d)
        halo = np.exp(-d / (width * 2.2)) * glow
        t = c.x[..., None]
        color = rgb(ca) * (1 - t) + rgb(cb) * t
        shade = (1 - 0.25 * (d / width).clip(0, 1))[..., None]
        img = img * (1 - halo[..., None]) + color * halo[..., None]
        img = img * (1 - body[..., None]) + color * shade * body[..., None]
    return img


def arcs(c, colors, cx, cy, ring=0.12):
    """Concentric rings from a point off to one side."""
    d = np.sqrt(((c.x - cx) * c.aspect) ** 2 + (c.y - cy) ** 2)
    idx = np.floor(d / ring).astype(int)
    frac = (d / ring) - np.floor(d / ring)
    palette = np.stack([rgb(col) for col in colors])
    a = palette[np.clip(idx, 0, len(colors) - 1)]
    edge = smoothstep(0.0, 0.03, frac)[..., None]       # crisp ring edge
    inner = 1 - 0.06 * (1 - frac)[..., None]           # slight shading inside each ring
    prev = palette[np.clip(idx - 1, 0, len(colors) - 1)]
    return (prev * (1 - edge) + a * edge) * inner


def stars(c, img, count, brightness=0.9):
    ys = c.rng.integers(0, c.h - 1, count)
    xs = c.rng.integers(0, c.w - 1, count)
    b = c.rng.uniform(0.3, 1, count) * brightness
    # 2x2 stars at full size so they stay visible on Retina screens.
    offsets = [(0, 0), (0, 1), (1, 0), (1, 1)] if c.w > 2000 else [(0, 0)]
    for dy, dx in offsets:
        img[ys + dy, xs + dx] = np.maximum(img[ys + dy, xs + dx], b[:, None])
    return img


def moon(c, img, mx, my, r, color="#f4f1e8"):
    d = np.sqrt(((c.x - mx) * c.aspect) ** 2 + (c.y - my) ** 2)
    disc = 1 - smoothstep(r * 0.97, r, d)
    glow = np.exp(-np.maximum(d - r, 0) / (r * 1.6)) * 0.35
    img = blend(img, color, glow)
    return blend(img, color, disc)


# ---------------------------------------------------------------- library

LIGHT = [
    ("morning-mist", "Morning Mist", lambda c: mesh(c, "#f6f0ea", [
        (0.15, 0.2, 0.28, "#ffd3b6", 0.9), (0.85, 0.25, 0.3, "#d9c8ff", 0.85),
        (0.55, 0.9, 0.35, "#bfe3ff", 0.9), (0.45, 0.45, 0.2, "#fff4e0", 0.6)])),
    ("lilac-waves", "Lilac Waves", lambda c: waves(c, "#f7f3ff", ["#e6dcff", "#d3c4fd", "#bfaaf8", "#a990f0"])),
    ("peach-dunes", "Peach Dunes", lambda c: dunes(c, "#fff4ec", ["#ffe0cb", "#ffcaa9", "#f9b38e", "#ef9c79"])),
    ("seafoam", "Seafoam", lambda c: mesh(c, "#effaf6", [
        (0.2, 0.75, 0.3, "#b8efe0", 0.95), (0.8, 0.2, 0.32, "#c9e8ff", 0.9),
        (0.65, 0.7, 0.22, "#fdf1c7", 0.7)])),
    ("sky-ribbons", "Sky Ribbons", lambda c: ribbons(c, "#f4f8ff", "#e4eeff", [
        (0.45, 0.12, 0.05, "#8fb8ff", "#b9a5ff"), (0.62, 0.1, 0.035, "#9fe3e3", "#8fb8ff")], glow=0.25)),
    ("paper-hills", "Paper Hills", lambda c: hills(c, "#fdf9f3", "#f3ece2", ["#e9e1d5", "#dacfbf", "#c9bba8", "#b6a691"])),
    ("rose-quartz", "Rose Quartz", lambda c: mesh(c, "#fcf0f3", [
        (0.2, 0.3, 0.3, "#f7c6d6", 0.9), (0.8, 0.75, 0.32, "#e9d1f7", 0.9),
        (0.75, 0.15, 0.2, "#fde3cf", 0.8)])),
    ("glacier", "Glacier", lambda c: waves(c, "#f3faff", ["#d9eefc", "#bcdef6", "#9bcaee", "#7eb5e4"], freq=0.8)),
    ("citrus-fade", "Citrus Fade", lambda c: mesh(c, "#fffbec", [
        (0.15, 0.25, 0.3, "#ffe59a", 0.9), (0.85, 0.65, 0.3, "#ffc9a0", 0.85),
        (0.5, 0.95, 0.28, "#c9f1b8", 0.8)])),
    ("sand-arcs", "Sand Arcs", lambda c: arcs(c, ["#fbf6ef", "#f6ece0", "#f0e1d0", "#e9d5bf", "#e1c8ae", "#d8bb9d", "#ceae8d", "#c4a17e"], -0.05, 1.1, ring=0.24)),
    ("cotton-sky", "Cotton Sky", lambda c: mesh(c, "#cfe6ff", [
        (0.2, 0.7, 0.18, "#ffffff", 0.95), (0.35, 0.78, 0.16, "#ffffff", 0.9),
        (0.75, 0.6, 0.2, "#ffffff", 0.85), (0.9, 0.72, 0.14, "#fdfdff", 0.9),
        (0.55, 0.95, 0.25, "#f6f9ff", 0.9)], base2="#f1f7ff")),
    ("lavender-haze", "Lavender Haze", lambda c: hills(c, "#f7f2ff", "#efe8fd", ["#e3d9fb", "#cfc1f3", "#b9a8e7", "#a391da"], start=0.5)),
    ("mint-ribbons", "Mint Ribbons", lambda c: ribbons(c, "#f4fcf8", "#e9f7f1", [
        (0.4, 0.14, 0.06, "#8fe3c4", "#9fcbff"), (0.66, 0.08, 0.03, "#c9f2a8", "#8fe3c4")], glow=0.2)),
    ("pearl", "Pearl", lambda c: mesh(c, "#f6f6f8", [
        (0.2, 0.2, 0.28, "#cfe4ff", 1.0), (0.8, 0.3, 0.28, "#f8d3e8", 1.0),
        (0.3, 0.85, 0.3, "#d3f5df", 0.95), (0.85, 0.85, 0.26, "#ffe8c4", 1.0)])),
    ("coral-bloom", "Coral Bloom", lambda c: arcs(c, ["#fff4f0", "#ffe8e0", "#ffdbcf", "#ffcdbe", "#fdbfad", "#f9b19d", "#f4a38d", "#ee967f"], 1.05, -0.1, ring=0.22)),
]

DARK = [
    ("midnight-aurora", "Midnight Aurora", lambda c: mesh(c, "#0e1838", [
        (0.25, 0.35, 0.22, "#1fb5a0", 0.75), (0.6, 0.25, 0.25, "#3fd3b0", 0.55),
        (0.8, 0.45, 0.22, "#6b4fd8", 0.75), (0.5, 0.9, 0.3, "#1a2f6b", 0.8)], base2="#121a3d")),
    ("deep-ocean", "Deep Ocean", lambda c: waves(c, "#0c1e36", ["#123459", "#17467a", "#1d5b99", "#2572b6"], shade=-0.25)),
    ("ember-dunes", "Ember Dunes", lambda c: dunes(c, "#1f1216", ["#40201f", "#632a24", "#8a3828", "#b04d2f"])),
    ("violet-night", "Violet Night", lambda c: mesh(c, "#170f2e", [
        (0.2, 0.25, 0.28, "#5b3fd1", 0.85), (0.8, 0.7, 0.3, "#b0379a", 0.75),
        (0.75, 0.15, 0.2, "#1f5fd6", 0.7)])),
    ("obsidian-ribbons", "Obsidian Ribbons", lambda c: ribbons(c, "#10131a", "#161a24", [
        (0.42, 0.13, 0.045, "#6c7cff", "#ff7ab6"), (0.62, 0.1, 0.03, "#43d6c4", "#6c7cff")], glow=0.45)),
    ("forest-night", "Forest Night", lambda c: hills(c, "#142a2a", "#1d3b37", ["#18392f", "#1c4a3b", "#215c49", "#277057"], start=0.48)),
    ("neon-dusk", "Neon Dusk", lambda c: mesh(c, "#1b1034", [
        (0.2, 0.8, 0.3, "#ff5f8f", 0.8), (0.55, 0.95, 0.25, "#ff9a3d", 0.75),
        (0.85, 0.25, 0.3, "#6a3dff", 0.8)])),
    ("graphite-arcs", "Graphite Arcs", lambda c: arcs(c, ["#20232b", "#262a33", "#2d313c", "#343945", "#3b414e", "#434958", "#4a5161", "#525a6b", "#5a6275", "#626b7e", "#6b7488", "#737d92"], 0.5, 1.25, ring=0.13)),
    ("indigo-waves", "Indigo Waves", lambda c: waves(c, "#10163a", ["#1d2664", "#27338c", "#3445b2", "#4a5fd6"], shade=-0.2)),
    ("cosmic-teal", "Cosmic Teal", lambda c: stars(c, mesh(c, "#082128", [
        (0.3, 0.35, 0.28, "#0fb5ae", 0.65), (0.75, 0.7, 0.3, "#2a6fdb", 0.6),
        (0.6, 0.15, 0.2, "#0c4f5e", 0.8)]), 900, 0.8)),
    ("night-dunes", "Night Dunes", lambda c: dunes(c, "#12142a", ["#212447", "#2f3263", "#3f427f", "#53559b"])),
    ("black-cherry", "Black Cherry", lambda c: mesh(c, "#1f0913", [
        (0.25, 0.3, 0.3, "#8a1538", 0.8), (0.8, 0.75, 0.28, "#c2356a", 0.7),
        (0.7, 0.2, 0.22, "#4a0f2a", 0.8)])),
    ("starfield", "Starfield", lambda c: stars(c, mesh(c, "#0d1330", [
        (0.7, 0.35, 0.3, "#3b2a78", 0.6), (0.25, 0.7, 0.28, "#1e3f7a", 0.55)], base2="#1d1542"), 2600, 1.0)),
    ("moonlit-bay", "Moonlit Bay", lambda c: moon(c, waves(c, "#141f48", ["#1c2c62", "#22397a", "#2a4891", "#3459a8"], base_y=0.55, spread=0.1, amp=0.02, shade=-0.15), 0.72, 0.28, 0.06)),
    ("copper-ribbons", "Copper Ribbons", lambda c: ribbons(c, "#171214", "#1e1719", [
        (0.4, 0.12, 0.05, "#e08a4a", "#c7577a"), (0.63, 0.09, 0.03, "#f2c27b", "#e08a4a")], glow=0.4)),
]


def render(painter, w, h, seed):
    c = Canvas(w, h, seed)
    img = painter(c)
    # Fine grain avoids banding in smooth gradients.
    img = img + c.rng.normal(0, 0.8 / 255, img.shape).astype(np.float32)
    return Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", action="store_true")
    args = parser.parse_args()

    library = [("light", item) for item in LIGHT] + [("dark", item) for item in DARK]

    if args.preview:
        tw, th = 384, 248
        sheet = Image.new("RGB", (tw * 5 + 6 * 8, th * 6 + 7 * 8), "white")
        for i, (theme, (slug, name, painter)) in enumerate(library):
            tile = render(painter, tw, th, seed=i)
            sheet.paste(tile, (8 + (i % 5) * (tw + 8), 8 + (i // 5) * (th + 8)))
        path = OUT.parent / "wallpapers-preview.png"
        sheet.save(path)
        print(path)
        return

    catalog = []
    for i, (theme, (slug, name, painter)) in enumerate(library):
        folder = OUT / theme
        folder.mkdir(parents=True, exist_ok=True)
        (OUT / "thumbs").mkdir(parents=True, exist_ok=True)
        image = render(painter, WIDTH, HEIGHT, seed=i)
        image.save(folder / f"{slug}.jpg", quality=90, optimize=True, progressive=True)
        image.resize(THUMB, Image.LANCZOS).save(OUT / "thumbs" / f"{slug}.jpg", quality=85)
        catalog.append({"id": slug, "name": name, "theme": theme, "file": f"{theme}/{slug}.jpg", "thumb": f"thumbs/{slug}.jpg"})
        print(f"{theme:5} {name}")
    (OUT / "catalog.json").write_text(json.dumps(catalog, indent=2) + "\n")


if __name__ == "__main__":
    main()
