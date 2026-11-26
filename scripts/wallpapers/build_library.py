"""Builds NotchIsland's wallpaper library in Packaging/Wallpapers.

Three kinds of wallpaper, 15 light and 15 dark in total:

* Wall art: public-domain paintings and prints from the Art Institute of Chicago
  (images released under CC0 for public-domain works).
* Places: NASA photographs of Earth and space (NASA imagery is not copyrighted).
* Graphic designs: original designs drawn here, in popular poster styles.

Every downloaded image is checked against the source's public-domain flag where
the source has one, and its credit is written to catalog.json, which the app shows.

    python3 scripts/wallpapers/build_library.py             # build everything
    python3 scripts/wallpapers/build_library.py --preview   # contact sheet only

Requires numpy and Pillow, and network access to api.artic.edu, www.artic.edu,
images-api.nasa.gov and images-assets.nasa.gov.
"""
import argparse
import io
import json
import math
import pathlib
import shutil
import urllib.request

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "Packaging" / "Wallpapers"
CACHE = ROOT / ".build" / "wallpaper-cache"
SIZE = (2880, 1800)          # 16:10
THUMB = (432, 270)
USER_AGENT = "NotchIsland wallpaper library builder (open-source macOS app)"

# (slug, name, theme, Art Institute of Chicago artwork id, inset fraction)
ART = [
    ("great-wave", "The Great Wave", "light", 24645, 0.05),
    ("red-fuji", "Red Fuji", "light", 87005, 0.05),
    ("poppy-field", "Poppy Field", "light", 4783, 0.02),
    ("wheat-stacks-snow", "Wheat Stacks, Snow", "light", 81545, 0.02),
    ("waterloo-bridge", "Waterloo Bridge", "light", 20701, 0.02),
    ("crane-over-wave", "Crane over the Wave", "light", 47667, 0.04),
    ("sainte-adresse", "Beach at Sainte-Adresse", "light", 14598, 0.02),
    ("nocturne", "Nocturne in Blue and Gold", "dark", 56905, 0.02),
    ("vesuvius", "Eruption of Vesuvius", "dark", 57996, 0.01),
    ("catskills-mist", "Mist Rising at Sunset", "dark", 71971, 0.02),
    ("inness-sunset", "Landscape, Sunset", "dark", 64740, 0.02),
    ("water-lily-pond", "Water Lily Pond", "dark", 97933, 0.02),
]

# (slug, name, theme, NASA image id, credit)
PLACES = [
    ("sahara-dunes", "Sahara Dunes", "light", "iss013e65526", "NASA, Expedition 13 crew"),
    ("bahamas-reefs", "Bahamas Reefs", "light", "iss064e002482", "NASA, Expedition 64 crew"),
    ("iceland-cyclones", "Cyclones near Iceland", "light", "GSFC_20171208_Archive_e002167", "NASA Goddard"),
    ("teal-channels", "Teal Channels", "light", "iss069e060925", "NASA, Expedition 69 crew"),
    ("aurora-orbit", "Aurora from Orbit", "dark", "iss066e146457", "NASA, Expedition 66 crew"),
    ("orbital-sunrise", "Orbital Sunrise", "dark", "iss061e123468", "NASA, Expedition 61 crew"),
    ("city-lights", "City Lights", "dark", "iss035e017286", "NASA, Expedition 35 crew"),
    ("mystic-mountain", "Mystic Mountain", "dark", "GSFC_20171208_Archive_e002076", "NASA, ESA and the Hubble 20th Anniversary Team (STScI)"),
]


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "AIC-User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def fetch_json(url):
    return json.loads(fetch(url))


def cached(name, url):
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / name
    if not path.exists():
        path.write_bytes(fetch(url))
    return Image.open(io.BytesIO(path.read_bytes())).convert("RGB")


def fit(image, inset):
    """Trim the edges (paper margins, frames), crop the center to 16:10, resize."""
    w, h = image.size
    image = image.crop((int(w * inset), int(h * inset), int(w * (1 - inset)), int(h * (1 - inset))))
    w, h = image.size
    target = SIZE[0] / SIZE[1]
    if w / h > target:
        new_w = int(h * target)
        image = image.crop(((w - new_w) // 2, 0, (w - new_w) // 2 + new_w, h))
    else:
        new_h = int(w / target)
        image = image.crop((0, (h - new_h) // 2, w, (h - new_h) // 2 + new_h))
    return image.resize(SIZE, Image.LANCZOS)


def art_entries():
    for slug, name, theme, artwork_id, inset in ART:
        info = fetch_json(f"https://api.artic.edu/api/v1/artworks/{artwork_id}"
                          "?fields=id,title,artist_title,date_display,image_id,is_public_domain")["data"]
        if not info["is_public_domain"]:
            raise SystemExit(f"{name} is not marked public domain; leaving it out.")
        image = cached(f"aic-{artwork_id}.jpg", f"https://www.artic.edu/iiif/2/{info['image_id']}/full/3000,/0/default.jpg")
        credit = f"{info['artist_title']}, {info['title']} ({info['date_display']}). Art Institute of Chicago, CC0."
        yield slug, name, theme, "art", fit(image, inset), credit, f"https://www.artic.edu/artworks/{artwork_id}"


def place_entries():
    for slug, name, theme, nasa_id, credit in PLACES:
        assets = [item["href"] for item in fetch_json(f"https://images-api.nasa.gov/asset/{nasa_id}")["collection"]["items"]]
        url = next((a for a in assets if a.endswith("~orig.jpg")), None) or next(a for a in assets if a.endswith(".jpg"))
        image = cached(f"nasa-{nasa_id}.jpg", url.replace("http://", "https://"))
        yield slug, name, theme, "places", fit(image, 0.02), f"{credit}. Public domain.", f"https://images.nasa.gov/details/{nasa_id}"


# ---------------------------------------------------------------- graphic designs

def hex_rgb(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


class Poster:
    """Draws at twice the size, then scales down for smooth edges."""

    def __init__(self, background, top=None):
        self.w, self.h = SIZE[0] * 2, SIZE[1] * 2
        if top:
            t = np.linspace(0, 1, self.h)[:, None, None]
            gradient = np.array(hex_rgb(top)) * (1 - t) + np.array(hex_rgb(background)) * t
            self.image = Image.fromarray(np.repeat(gradient, self.w, axis=1).astype(np.uint8))
        else:
            self.image = Image.new("RGB", (self.w, self.h), hex_rgb(background))
        self.draw = ImageDraw.Draw(self.image)

    def px(self, x, y):
        return x * self.w, y * self.h

    def circle(self, cx, cy, r, color, width=0, outline=None):
        r *= self.h
        x, y = self.px(cx, cy)
        box = (x - r, y - r, x + r, y + r)
        if width:
            self.draw.ellipse(box, outline=hex_rgb(outline or color), width=int(width * self.h))
        else:
            self.draw.ellipse(box, fill=hex_rgb(color))

    def pie(self, cx, cy, r, start, end, color):
        r *= self.h
        x, y = self.px(cx, cy)
        self.draw.pieslice((x - r, y - r, x + r, y + r), start, end, fill=hex_rgb(color))

    def rect(self, x0, y0, x1, y1, color):
        self.draw.rectangle((*self.px(x0, y0), *self.px(x1, y1)), fill=hex_rgb(color))

    def polygon(self, points, color):
        self.draw.polygon([self.px(x, y) for x, y in points], fill=hex_rgb(color))

    def ridge(self, base, amplitude, frequency, phase, color, sharp=False):
        xs = np.linspace(0, 1, 400)
        wave = np.abs(np.sin(xs * math.pi * frequency + phase)) if sharp else np.sin(xs * math.pi * frequency + phase)
        ys = base - amplitude * wave - amplitude * 0.3 * np.sin(xs * math.pi * frequency * 2.7 + phase * 1.3)
        self.polygon(list(zip(xs, ys)) + [(1, 1.01), (0, 1.01)], color)

    def finish(self, grain=7):
        image = self.image.resize(SIZE, Image.LANCZOS)
        array = np.asarray(image).astype(np.float32)
        array += np.random.default_rng(7).normal(0, grain, array.shape[:2])[..., None]
        return Image.fromarray(np.clip(array, 0, 255).astype(np.uint8))


def bauhaus():
    p = Poster("#f2e8d8")
    p.circle(0.3, 0.45, 0.32, "#d0603f")
    p.pie(0.62, 0.62, 0.3, 180, 360, "#e3a53c")
    p.rect(0.55, 0.62, 0.69, 0.92, "#2f6f73")
    p.pie(0.83, 0.3, 0.2, 90, 180, "#1f2f4a")
    p.circle(0.45, 0.2, 0.05, "#1f2f4a")
    p.circle(0.82, 0.72, 0.09, "#e9c9a6")
    p.rect(0.08, 0.86, 0.48, 0.875, "#1f2f4a")
    return p.finish()


def paper_cutouts():
    p = Poster("#efe4d3")
    rng = np.random.default_rng(3)
    colors = ["#e07a5f", "#81b29a", "#3d405b", "#f2cc8f", "#e07a5f", "#81b29a", "#3d405b"]
    for i, color in enumerate(colors):
        cx, cy = 0.1 + i * 0.135, rng.uniform(0.3, 0.7)
        size = rng.uniform(0.12, 0.2)
        lobes = rng.integers(3, 6)
        angles = np.linspace(0, math.tau, 240)
        radius = size * (1 + 0.35 * np.sin(angles * lobes + rng.uniform(0, 6)) + 0.12 * np.sin(angles * 9))
        points = [(cx + r * math.cos(a) / (p.w / p.h), cy + r * math.sin(a)) for a, r in zip(angles, radius)]
        p.polygon(points, color)
    for _ in range(14):
        p.circle(rng.uniform(0.03, 0.97), rng.uniform(0.05, 0.95), rng.uniform(0.008, 0.02), "#3d405b")
    return p.finish()


def desert_sun():
    p = Poster("#f4ece1", top="#f8efe4")
    p.circle(0.66, 0.42, 0.2, "#e7a977")
    p.ridge(0.62, 0.1, 1.3, 0.4, "#e2c3a4", sharp=True)
    p.ridge(0.72, 0.08, 1.8, 2.1, "#d0a283", sharp=True)
    p.ridge(0.84, 0.06, 2.2, 0.9, "#b67c5c", sharp=True)
    p.ridge(0.95, 0.04, 1.2, 1.7, "#8f5a42")
    return p.finish()


def seventies():
    p = Poster("#f6ecdc")
    colors = ["#264653", "#2a9d8f", "#e9c46a", "#f4a261", "#e76f51"]
    for i, color in enumerate(colors):
        p.circle(0.5, 1.02, 0.95 - i * 0.16, color)
    p.circle(0.5, 1.02, 0.15, "#f6ecdc")
    return p.finish()


def night_mountains():
    p = Poster("#2b3f6b", top="#0d1733")
    p.circle(0.7, 0.3, 0.12, "#f2e6c9")
    p.ridge(0.6, 0.16, 1.1, 0.3, "#263d63", sharp=True)
    p.ridge(0.7, 0.13, 1.6, 1.9, "#1d3152", sharp=True)
    p.ridge(0.8, 0.1, 2.1, 0.7, "#142643", sharp=True)
    p.ridge(0.92, 0.06, 1.4, 2.6, "#0c1a33")
    image = p.finish(grain=6)
    # Mist between the ridges.
    array = np.asarray(image).astype(np.float32)
    y = np.linspace(0, 1, SIZE[1])[:, None, None]
    mist = np.exp(-((y - 0.66) ** 2) / 0.004) * 38 + np.exp(-((y - 0.77) ** 2) / 0.003) * 28
    return Image.fromarray(np.clip(array + mist, 0, 255).astype(np.uint8))


def synth_sunset():
    p = Poster("#ff6f91", top="#1a0b2e")
    cx, cy, r = 0.5, 0.58, 0.3
    p.circle(cx, cy, r, "#ffb86b")
    for i in range(7):
        y = cy + 0.02 + i * 0.04
        p.rect(0, y, 1, y + 0.008 + i * 0.004, "#ff6f91")
    p.rect(0, 0.62, 1, 1, "#160a29")
    for i in range(1, 14):
        t = i / 14
        y = 0.62 + (t ** 2.2) * 0.38
        p.rect(0, y, 1, y + 0.002 + t * 0.003, "#c13ef2")
    for i in range(-14, 15):
        x0 = 0.5 + i * 0.012
        x1 = 0.5 + i * 0.12
        p.draw.line((*p.px(x0, 0.62), *p.px(x1, 1.0)), fill=hex_rgb("#c13ef2"), width=4)
    return p.finish(grain=5)


def bauhaus_night():
    p = Poster("#141a2e")
    p.pie(0.25, 0.75, 0.42, 180, 360, "#e76f51")
    p.circle(0.68, 0.38, 0.22, "#f2cc8f")
    p.pie(0.68, 0.38, 0.22, 90, 270, "#4f9d9a")
    p.rect(0.82, 0.55, 0.9, 0.95, "#eae2d0")
    p.circle(0.5, 0.18, 0.035, "#eae2d0")
    p.rect(0.08, 0.15, 0.36, 0.165, "#4f9d9a")
    return p.finish(grain=6)


def swiss_rings():
    p = Poster("#111214")
    for i in range(18):
        p.circle(0.42, 0.55, 0.06 + i * 0.045, "#eae6dd", width=0.0025, outline="#eae6dd")
    p.circle(0.68, 0.38, 0.16, "#d6402e")
    return p.finish(grain=6)


def deco_fans():
    p = Poster("#0e1a1f")
    gold = hex_rgb("#c9a45c")
    radius = 0.11 * p.h
    rows = int(p.h / (radius * 0.5)) + 2
    cols = int(p.w / (radius * 2)) + 2
    for row in range(rows):
        for col in range(cols):
            cx = col * radius * 2 + (radius if row % 2 else 0)
            cy = row * radius * 0.5
            for k in range(4):
                r = radius * (1 - k * 0.22)
                p.draw.arc((cx - r, cy - r, cx + r, cy + r), 180, 360, fill=gold, width=7)
    return p.finish(grain=5)


def midnight_sea():
    p = Poster("#123b46", top="#061418")
    p.circle(0.5, 0.42, 0.13, "#f1d9a7")
    p.rect(0, 0.6, 1, 1, "#071c22")
    for i in range(16):
        y = 0.62 + i * 0.024
        half = 0.13 * (1 - i / 18) * (0.6 + 0.4 * ((i * 37) % 5) / 4)
        p.rect(0.5 - half, y, 0.5 + half, y + 0.006, "#d9bd86")
    return p.finish(grain=6)


GRAPHICS = [
    ("bauhaus", "Bauhaus", "light", bauhaus),
    ("paper-cutouts", "Paper Cut-outs", "light", paper_cutouts),
    ("desert-sun", "Desert Sun", "light", desert_sun),
    ("seventies", "Seventies", "light", seventies),
    ("night-mountains", "Night Mountains", "dark", night_mountains),
    ("synth-sunset", "Synth Sunset", "dark", synth_sunset),
    ("bauhaus-night", "Bauhaus Night", "dark", bauhaus_night),
    ("swiss-rings", "Swiss Rings", "dark", swiss_rings),
    ("deco-fans", "Deco Fans", "dark", deco_fans),
    ("midnight-sea", "Midnight Sea", "dark", midnight_sea),
]


def graphic_entries():
    for slug, name, theme, painter in GRAPHICS:
        yield slug, name, theme, "graphic", painter(), "Original design for NotchIsland. MIT License.", None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", action="store_true", help="only write docs/wallpapers.png")
    parser.add_argument("--graphics-only", action="store_true")
    args = parser.parse_args()

    sources = [graphic_entries()] if args.graphics_only else [art_entries(), place_entries(), graphic_entries()]
    entries = [entry for source in sources for entry in source]

    if not args.preview:
        if OUT.exists() and not args.graphics_only:
            shutil.rmtree(OUT)
        (OUT / "thumbs").mkdir(parents=True, exist_ok=True)
    catalog = []
    for slug, name, theme, category, image, credit, source in entries:
        if not args.preview:
            (OUT / theme).mkdir(exist_ok=True)
            image.save(OUT / theme / f"{slug}.jpg", quality=84, optimize=True, progressive=True)
            image.resize(THUMB, Image.LANCZOS).save(OUT / "thumbs" / f"{slug}.jpg", quality=85)
        catalog.append({"id": slug, "name": name, "theme": theme, "category": category,
                        "file": f"{theme}/{slug}.jpg", "thumb": f"thumbs/{slug}.jpg",
                        "credit": credit, "source": source})
        print(f"{theme:5} {category:8} {name}")

    if not args.preview and not args.graphics_only:
        (OUT / "catalog.json").write_text(json.dumps(catalog, indent=2) + "\n")

    # Contact sheet for the README.
    tw, th, cols = 320, 200, 6
    rows = math.ceil(len(entries) / cols)
    sheet = Image.new("RGB", (cols * (tw + 8) + 8, rows * (th + 8) + 8), "white")
    for i, entry in enumerate(entries):
        sheet.paste(entry[4].resize((tw, th), Image.LANCZOS), (8 + (i % cols) * (tw + 8), 8 + (i // cols) * (th + 8)))
    (ROOT / "docs").mkdir(exist_ok=True)
    sheet.save(ROOT / "docs" / "wallpapers.png")


if __name__ == "__main__":
    main()
