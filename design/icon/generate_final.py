"""Final Margin icon: warm-cream paper, warm-black bracket, deep-violet dot.

Two artworks: a refined one for large sizes and a redrawn, chunkier one for
small sizes (<=32px) so the mark reads at tray size instead of being a shrunk
blur. Writes the multi-size .ico + platform assets directly into the repo.
"""
import io
import os
import struct
from PIL import Image, ImageDraw

SS = 4
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(HERE, "png_final")
os.makedirs(OUT, exist_ok=True)

INK = (30, 27, 22, 255)        # warm near-black
PAPER = (243, 236, 221, 255)   # warm cream  #F3ECDD
DOT = (94, 53, 177, 255)       # deep violet #5E35B1 (heritage nod)


def _stroke(d, pts, w, color):
    d.line(pts, fill=color, width=w, joint="curve")
    r = w / 2
    for (x, y) in pts:
        d.ellipse([x - r, y - r, x + r, y + r], fill=color)


def render(size):
    """Refined art for >32px, redrawn chunky art for <=32px."""
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    k = s / 256.0
    def P(x, y):
        return (x * k, y * k)

    d.rectangle([0, 0, s, s], fill=PAPER)

    if size <= 32:  # chunky: thicker, taller, fatter dot, less padding
        _stroke(d, [P(132, 44), P(62, 44), P(62, 212), P(132, 212)], int(30 * k), INK)
        r = 26 * k
        cx, cy = P(186, 128)
        rad = 40 * k
    else:  # refined
        _stroke(d, [P(120, 64), P(78, 64), P(78, 192), P(120, 192)], int(20 * k), INK)
        r = 15 * k
        cx, cy = P(168, 128)
        rad = 56 * k

    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=DOT)

    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s, s], radius=rad, fill=255)
    img.putalpha(mask)
    return img.resize((size, size), Image.LANCZOS)


def write_ico(path, sizes):
    """Hand-build a multi-image ICO so each size carries its own (redrawn)
    bitmap, stored as PNG (Windows Vista+ supports PNG-in-ICO). Pillow's own
    ICO save can't do distinct per-size artwork, hence the manual container."""
    pngs = []
    for s in sizes:
        buf = io.BytesIO()
        render(s).save(buf, format="PNG")
        pngs.append(buf.getvalue())

    header = struct.pack("<HHH", 0, 1, len(sizes))  # reserved, type=icon, count
    offset = 6 + 16 * len(sizes)
    entries, data = b"", b""
    for s, png in zip(sizes, pngs):
        entries += struct.pack(
            "<BBBBHHII",
            s & 0xFF, s & 0xFF,  # width, height (0 == 256)
            0, 0,                # colors, reserved
            1, 32,               # planes, bit depth
            len(png), offset,
        )
        data += png
        offset += len(png)

    with open(path, "wb") as f:
        f.write(header + entries + data)
    print(f"  {os.path.relpath(path, ROOT)} -> {len(sizes)} bitmaps")


# --- Windows app icon (multi-size, with redrawn small bitmaps) ---
print("icons:")
write_ico(os.path.join(ROOT, "windows", "runner", "resources", "app_icon.ico"),
          [16, 24, 32, 48, 64, 128, 256])

# --- System tray icon (small sizes matter most) ---
write_ico(os.path.join(ROOT, "assets", "tray_icon.ico"), [16, 24, 32, 48])
render(64).save(os.path.join(ROOT, "assets", "tray_icon.png"))  # mac/linux tray

# --- Android launcher icons (legacy mipmaps; all >=48 -> refined art) ---
android = {
    "mipmap-mdpi": 48, "mipmap-hdpi": 72, "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144, "mipmap-xxxhdpi": 192,
}
res = os.path.join(ROOT, "android", "app", "src", "main", "res")
for folder, px in android.items():
    render(px).save(os.path.join(res, folder, "ic_launcher.png"))
print(f"  android mipmaps -> {sorted(android.values())}")

# --- Review preview (large + the redrawn small sizes) ---
prev_sizes = [256, 48, 32, 24, 16]
pad, cell = 16, 100
W = pad + len(prev_sizes) * (cell + pad)
sheet = Image.new("RGBA", (W, (cell + pad) * 2 + pad), (255, 255, 255, 255))
for pi, bg in enumerate([(150, 152, 156, 255), (24, 24, 24, 255)]):
    y0 = pad + pi * (cell + pad)
    ImageDraw.Draw(sheet).rectangle([0, y0 - pad // 2, W, y0 + cell + pad // 2], fill=bg)
    for ci, sz in enumerate(prev_sizes):
        ic = render(sz)
        x = pad + ci * (cell + pad)
        sheet.paste(ic, (x + (cell - sz) // 2, y0 + (cell - sz)), ic)
sheet.save(os.path.join(OUT, "final_preview.png"))
print("preview:", os.path.relpath(os.path.join(OUT, "final_preview.png"), ROOT))
