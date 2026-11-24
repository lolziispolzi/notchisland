"""Draws Packaging/AppIcon.png (1024x1024). Requires Pillow: pip install pillow"""
import pathlib
from PIL import Image, ImageDraw, ImageFilter

S = 1024
out = pathlib.Path(__file__).resolve().parent.parent / "Packaging" / "AppIcon.png"

# Vertical gradient background
bg = Image.new("RGBA", (S, S))
top, bottom = (58, 64, 92), (14, 16, 26)
px = bg.load()
for y in range(S):
    t = y / (S - 1)
    c = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3)) + (255,)
    for x in range(S):
        px[x, y] = c

# macOS-style rounded square with margin
mask = Image.new("L", (S, S), 0)
m = 100
ImageDraw.Draw(mask).rounded_rectangle((m, m, S - m, S - m), radius=185, fill=255)
icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
icon.paste(bg, (0, 0), mask)

# Glow under the island
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(glow).rounded_rectangle((300, 300, 724, 470), radius=85, fill=(120, 140, 255, 160))
glow = glow.filter(ImageFilter.GaussianBlur(40))
icon = Image.alpha_composite(icon, Image.composite(glow, Image.new("RGBA", (S, S)), mask))

d = ImageDraw.Draw(icon)
# The island
d.rounded_rectangle((292, 280, 732, 440), radius=80, fill=(0, 0, 0, 255))
# Artwork tile and equalizer bars inside the island
d.rounded_rectangle((330, 316, 418, 404), radius=22, fill=(255, 120, 90, 255))
for i, h in enumerate((40, 70, 52, 82)):
    x = 600 + i * 26
    d.rounded_rectangle((x, 360 - h // 2, x + 14, 360 + h // 2), radius=7, fill=(255, 255, 255, 255))

icon.save(out)
print(f"wrote {out}")
