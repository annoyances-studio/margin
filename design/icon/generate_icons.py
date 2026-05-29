"""Render Margin icon candidates (A/B/C) as anti-aliased PNGs + a contact sheet.

Draws in a 256-unit space at 4x supersample, then LANCZOS-downsamples so small
sizes stay crisp. No SVG dependency (Pillow can't read SVG); geometry mirrors
the .svg files next to this script.
"""
import os
from PIL import Image, ImageDraw

SS = 4  # supersample factor
INDIGO = (63, 81, 181, 255)  # Flutter Colors.indigo (#3F51B5)
WHITE = (255, 255, 255, 255)
HERE = os.path.dirname(os.path.abspath(__file__))
PNG = os.path.join(HERE, "png")
os.makedirs(PNG, exist_ok=True)


def _stroke(d, pts, w):
    """Polyline with round joints and round caps (Pillow has no cap style)."""
    d.line(pts, fill=WHITE, width=w, joint="curve")
    r = w / 2
    for (x, y) in pts:
        d.ellipse([x - r, y - r, x + r, y + r], fill=WHITE)


def draw(candidate, size):
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    k = s / 256.0  # 256-space -> pixel scale
    def P(x, y):
        return (x * k, y * k)

    # Rounded-square background (app-icon squircle-ish).
    rad = 56 * k
    d.rounded_rectangle([0, 0, s, s], radius=rad, fill=INDIGO)

    if candidate == "A":
        _stroke(d, [P(150, 64), P(96, 64), P(96, 192), P(150, 192)], int(20 * k))
    elif candidate == "B":
        _stroke(d, [P(120, 64), P(78, 64), P(78, 192), P(120, 192)], int(20 * k))
        r = 15 * k
        cx, cy = P(168, 128)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=WHITE)
    elif candidate == "C":
        _stroke(d, [P(86, 72), P(64, 72), P(64, 184), P(86, 184)], int(18 * k))
        _stroke(d, [P(170, 72), P(192, 72), P(192, 184), P(170, 184)], int(18 * k))
        _stroke(d, [P(104, 108), P(152, 108)], int(16 * k))
        _stroke(d, [P(104, 148), P(136, 148)], int(16 * k))

    return img.resize((size, size), Image.LANCZOS)


CANDS = ["A", "B", "C"]
SIZES = [256, 48, 32, 16]

# Per-candidate PNGs.
for c in CANDS:
    for sz in SIZES:
        draw(c, sz).save(os.path.join(PNG, f"{c}-{sz}.png"))

# Contact sheet: rows = candidates, cols = sizes, on light then dark panels.
pad, cell, label_w = 16, 96, 70
cols = len(SIZES)
panel_w = label_w + cols * (cell + pad) + pad
panel_h = pad + len(CANDS) * (cell + pad)
sheet = Image.new("RGBA", (panel_w, panel_h * 2 + pad), (255, 255, 255, 255))
ds = ImageDraw.Draw(sheet)

def panel(y0, bg):
    ds.rectangle([0, y0, panel_w, y0 + panel_h], fill=bg)
    for ri, c in enumerate(CANDS):
        cy = y0 + pad + ri * (cell + pad)
        for ci, sz in enumerate(SIZES):
            cx = label_w + pad + ci * (cell + pad)
            ic = draw(c, sz)
            # center the (possibly tiny) icon in the cell, bottom-aligned
            ox = cx + (cell - sz) // 2
            oy = cy + (cell - sz)
            sheet.paste(ic, (ox, oy), ic)

panel(0, (243, 243, 243, 255))
panel(panel_h + pad, (30, 30, 30, 255))
sheet.save(os.path.join(PNG, "contactsheet.png"))
print("wrote PNGs + contactsheet to", PNG)
