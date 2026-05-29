"""Paper / black-bracket / violet-dot explorations of candidate B.

Renders four colorways + a contact sheet at display sizes so small-size
legibility (and the violet dot at 16px) can be judged. No SVG dep.
"""
import os
from PIL import Image, ImageDraw

SS = 4
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "png_b")
os.makedirs(OUT, exist_ok=True)

INK = (30, 27, 22, 255)            # warm near-black bracket
PAPER = (243, 236, 221, 255)       # warm cream
PAPER_DEEP = (236, 226, 206, 255)  # deeper ecru
PAPER_WHITE = (246, 242, 233, 255) # near-white warm
STRIP = (231, 220, 198, 255)       # darker paper = the margin column
RULE = (210, 199, 176, 255)        # faint neutral margin rule
V1 = (108, 74, 182, 255)           # violet #6C4AB6
V2 = (126, 87, 194, 255)           # violet #7E57C2
V3 = (94, 53, 177, 255)            # deep violet #5E35B1

# name -> (paper, dot, two_tone)
VARIANTS = {
    "M1-flat-v1": (PAPER, V1, False),
    "M2-twotone-v1": (PAPER, V1, True),
    "M3-deep-v2": (PAPER_DEEP, V2, False),
    "M4-white-v3": (PAPER_WHITE, V3, False),
}


def _stroke(d, pts, w, color):
    d.line(pts, fill=color, width=w, joint="curve")
    r = w / 2
    for (x, y) in pts:
        d.ellipse([x - r, y - r, x + r, y + r], fill=color)


def draw(name, size):
    paper, dot, two_tone = VARIANTS[name]
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    k = s / 256.0
    def P(x, y):
        return (x * k, y * k)

    d.rectangle([0, 0, s, s], fill=paper)
    if two_tone:
        d.rectangle([0, 0, 70 * k, s], fill=STRIP)
        d.line([P(70, 0), P(70, 256)], fill=RULE, width=int(4 * k))

    _stroke(d, [P(120, 64), P(78, 64), P(78, 192), P(120, 192)], int(20 * k), INK)
    r = 15 * k
    cx, cy = P(168, 128)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=dot)

    # Round the square into an app-icon squircle via an alpha mask.
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s, s], radius=56 * k, fill=255)
    img.putalpha(mask)
    return img.resize((size, size), Image.LANCZOS)


SIZES = [256, 48, 32, 16]
for name in VARIANTS:
    for sz in SIZES:
        draw(name, sz).save(os.path.join(OUT, f"{name}-{sz}.png"))

# Contact sheet: rows = variants, cols = display sizes, on grey + dark panels.
names = list(VARIANTS)
disp = [96, 48, 32, 16]
pad, cell, label_w = 16, 100, 130
panel_w = label_w + len(disp) * (cell + pad) + pad
panel_h = pad + len(names) * (cell + pad)
sheet = Image.new("RGBA", (panel_w, panel_h * 2 + pad), (255, 255, 255, 255))


def panel(y0, bg):
    ImageDraw.Draw(sheet).rectangle([0, y0, panel_w, y0 + panel_h], fill=bg)
    for ri, name in enumerate(names):
        cy = y0 + pad + ri * (cell + pad)
        for ci, px in enumerate(disp):
            cx = label_w + pad + ci * (cell + pad)
            ic = draw(name, px)
            sheet.paste(ic, (cx + (cell - px) // 2, cy + (cell - px)), ic)


panel(0, (150, 152, 156, 255))
panel(panel_h + pad, (24, 24, 24, 255))
sheet.save(os.path.join(OUT, "contactsheet_b.png"))
print("wrote variants + contactsheet_b to", OUT)
