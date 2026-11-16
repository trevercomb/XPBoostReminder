"""Draw XP Boost Reminder's logo (docs/logo.png): a sleeping bag under a
crescent moon. Original artwork, no game assets. Run: python tools/make_logo.py"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

SIZE, SCALE = 400, 4            # draw at 4x, then shrink for smooth edges
S = SIZE * SCALE
u = S / 400                     # one unit at the final size
NIGHT = (24, 30, 54)
GOLD = (240, 200, 100)
BAG = (196, 88, 58)
SEAM = (150, 60, 42)
PILLOW = (236, 226, 200)
SKY_TEXT = (150, 190, 240)      # the addon's chat color (|cff66ccff), softened

img = Image.new("RGB", (S, S), NIGHT)
d = ImageDraw.Draw(img)


def circle(cx, cy, r, fill):
    d.ellipse(((cx - r) * u, (cy - r) * u, (cx + r) * u, (cy + r) * u), fill=fill)


def rrect(x0, y0, x1, y1, r, fill):
    d.rounded_rectangle((x0 * u, y0 * u, x1 * u, y1 * u), radius=r * u, fill=fill)


# Stars, then a crescent moon (a gold circle with a night-colored bite).
for x, y, r in ((60, 60, 4), (130, 40, 3), (200, 85, 3), (80, 150, 3), (350, 200, 3), (170, 150, 2)):
    circle(x, y, r, GOLD)
circle(300, 100, 62, GOLD)
circle(328, 78, 56, NIGHT)

# The sleeping bag: quilted body with a pillow at the head end.
rrect(40, 240, 360, 340, 48, BAG)
for x in (170, 220, 270, 320):
    d.line((x * u, 248 * u, x * u, 332 * u), fill=SEAM, width=int(6 * u))
rrect(52, 254, 140, 326, 30, PILLOW)

# "z z" drifting up from the pillow.
for x, y, size in ((150, 190, 46), (195, 140, 62)):
    font = ImageFont.load_default(size=size * u)
    d.text((x * u, y * u), "z", font=font, fill=SKY_TEXT, anchor="mm")

out = Path(__file__).resolve().parent.parent / "docs" / "logo.png"
out.parent.mkdir(exist_ok=True)
img.resize((SIZE, SIZE), Image.LANCZOS).save(out, optimize=True)
print(out)
