"""Draw XP Boost Reminder's logo (docs/logo.png) and in-game icon (Media/icon.tga):
a glowing "XP" with rising arrows, a crescent moon for the sleeping bag and a
drumstick for food. Original artwork, no game assets. Run: python tools/make_logo.py"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIZE, SCALE = 400, 4            # draw at 4x, then shrink for smooth edges
S = SIZE * SCALE
u = S / 400                     # one unit at the final size
NIGHT = (22, 28, 52)
PURPLE = (120, 80, 200)         # the experience bar's purple
GOLD = (245, 205, 95)
MEAT = (196, 112, 64)
BONE = (238, 230, 210)

root = Path(__file__).resolve().parent.parent

img = Image.new("RGB", (S, S), NIGHT)

# Soft purple glow behind the letters.
glow = Image.new("RGB", (S, S), (0, 0, 0))
ImageDraw.Draw(glow).ellipse((60 * u, 90 * u, 340 * u, 330 * u), fill=PURPLE)
glow = glow.filter(ImageFilter.GaussianBlur(70 * u))
img = Image.blend(img, glow, 0.55)
d = ImageDraw.Draw(img)


def circle(cx, cy, r, fill):
    d.ellipse(((cx - r) * u, (cy - r) * u, (cx + r) * u, (cy + r) * u), fill=fill)


def chevron(cx, cy, w, h, thick, fill):
    pts = [(cx - w, cy + h), (cx, cy), (cx + w, cy + h)]
    d.line([(x * u, y * u) for x, y in pts], fill=fill, width=int(thick * u), joint="curve")


# Rising arrows above the letters.
chevron(200, 52, 46, 34, 16, GOLD)
chevron(200, 92, 46, 34, 16, (250, 225, 150))

# "XP" in big bold letters.
try:
    font = ImageFont.truetype("arialbd.ttf", int(190 * u))
except OSError:
    font = ImageFont.load_default(size=190 * u)
d.text((200 * u, 238 * u), "XP", font=font, fill=GOLD, anchor="mm",
       stroke_width=int(6 * u), stroke_fill=(90, 60, 30))

# Crescent moon (sleeping bag), bottom left: a disc with a bite cut out of a
# mask, so the glow behind it shows through the bite.
moon = Image.new("L", (S, S), 0)
m = ImageDraw.Draw(moon)
m.ellipse((36 * u, 312 * u, 106 * u, 382 * u), fill=255)
m.ellipse((58 * u, 300 * u, 122 * u, 364 * u), fill=0)
img.paste(GOLD, (0, 0, S, S), moon)

# Drumstick (food), bottom right.
d.line((300 * u, 350 * u, 352 * u, 302 * u), fill=BONE, width=int(14 * u))
circle(356, 298, 10, BONE)
circle(366, 306, 10, BONE)
d.ellipse((268 * u, 318 * u, 330 * u, 376 * u), fill=MEAT)

out = root / "docs" / "logo.png"
out.parent.mkdir(exist_ok=True)
img.resize((SIZE, SIZE), Image.LANCZOS).save(out, optimize=True)
print(out)

# In-game icon for the AddOns list (## IconTexture). WoW can't load PNG;
# 32-bit TGA at a power-of-two size works everywhere.
media = root / "Media"
media.mkdir(exist_ok=True)
img.convert("RGBA").resize((64, 64), Image.LANCZOS).save(media / "icon.tga")
print(media / "icon.tga")
