#!/usr/bin/env python3
"""App/IconSource/icon-source.webp -> App/Assets.xcassets/AppIcon.appiconset (macOS sizes).
The source is the icon on a grey backdrop. The icon's outer rim was measured at BOX (source pixels); it is cropped
there, scaled to a square (the art is ~3% taller than wide), clipped by a squircle so the corners are transparent,
and placed in Apple's 824pt art box inside a 1024 canvas. If you replace the source image, update BOX."""
import json, pathlib
from PIL import Image, ImageDraw

root = pathlib.Path(__file__).resolve().parents[1]
BOX = (452, 122, 957, 645)     # left, top, right, bottom of the icon's outer rim in icon-source.webp
INSET = 3                       # px (in 824 space) shaved off so no backdrop halo remains
N = 5.0                         # squircle exponent (≈ macOS icon shape)

src = Image.open(root / "App/IconSource/icon-source.webp").convert("RGBA")
art = src.crop(BOX).resize((824, 824), Image.LANCZOS)

def squircle_mask(size, inset, n, ss=4):
    S = size * ss; r = (size / 2 - inset) * ss; c = S / 2
    pts = []
    for i in range(720):
        t = 6.283185307 * i / 720
        import math
        ct, st = math.cos(t), math.sin(t)
        pts.append((c + r * math.copysign(abs(ct) ** (2 / n), ct), c + r * math.copysign(abs(st) ** (2 / n), st)))
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m.resize((size, size), Image.LANCZOS)

art.putalpha(squircle_mask(824, INSET, N))
canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
canvas.paste(art, (100, 100), art)

out = root / "App/Assets.xcassets/AppIcon.appiconset"
images = []
for pt in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = pt * scale
        name = f"icon_{pt}x{pt}@{scale}x.png"
        canvas.resize((px, px), Image.LANCZOS).save(out / name)
        images.append({"idiom": "mac", "size": f"{pt}x{pt}", "scale": f"{scale}x", "filename": name})
(out / "Contents.json").write_text(json.dumps({"images": images, "info": {"version": 1, "author": "xcode"}}, indent=2))
(root / "App/Assets.xcassets/Contents.json").write_text(json.dumps({"info": {"version": 1, "author": "xcode"}}))
canvas.save(root / "App/IconSource/icon-preview-1024.png")
print("ok")
