"""Fictional sponsor artwork for billboards and barrier banners (no real brands): 4x4 atlas, 512x256 per ad."""
import os
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "godot", "assets", "ads", "ads_atlas.png")
FONT = os.path.join(os.path.dirname(OUT), "..", "fonts")
ADS = [  # (headline, tagline, background, text colour, accent)
    ("KAFUE COLA", "ICE COLD SINCE 1974", "#c8102e", "#ffffff", "#ffd400"),
    ("COPPERLINE TYRES", "GRIP THAT HOLDS", "#111111", "#f2a900", "#f2a900"),
    ("NILE ENERGY", "FUEL FOR THE BRAVE", "#0b4f9c", "#ffffff", "#2ec4ff"),
    ("ZEDBANK", "BANKING ON THE MOVE", "#0f7a3d", "#ffffff", "#f7c600"),
    ("SAVANNA AIR", "FLY THE CONTINENT", "#f7f3e8", "#1a3b6e", "#e8701a"),
    ("GRIDLINE", "THE RACING LEAGUE", "#0d0f12", "#ffffff", "#ff6a00"),
    ("SKYLINE MOBILE", "4G EVERYWHERE", "#6a1b9a", "#ffffff", "#ffd54f"),
    ("HARMATTAN OIL", "SYNTHETIC RACING OIL", "#f2c200", "#111111", "#c8102e"),
    ("RIFT COFFEE", "HIGHLAND ROASTED", "#3e2417", "#f5deb3", "#d4a373"),
    ("KILN CEMENT", "BUILT TO LAST", "#7d8085", "#ffffff", "#ffb703"),
    ("BAOBAB FREIGHT", "LOGISTICS COAST TO COAST", "#1f2a44", "#ffffff", "#e63946"),
    ("NORDWERK", "PRÄZISION AUS BERLIN", "#e9ecef", "#212529", "#d00000"),
    ("THAMES & CO", "INSURANCE SINCE 1891", "#14213d", "#fca311", "#fca311"),
    ("SAHEL SOLAR", "POWER FROM THE SUN", "#ff7b00", "#ffffff", "#ffd000"),
    ("VOLT RUSH", "ENERGY DRINK", "#00b4d8", "#03045e", "#ffffff"),
    ("ARDEN MOTORS", "DRIVEN BY YOU", "#9a031e", "#ffffff", "#f6f6f6"),
]


def font(name, size):
    for f in (name, "BebasNeue-Regular.ttf"):
        p = os.path.join(FONT, f)
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


img = Image.new("RGB", (2048, 1024))
for i, (head, tag, bg, fg, acc) in enumerate(ADS):
    x, y = (i % 4) * 512, (i // 4) * 256
    d = ImageDraw.Draw(img)
    d.rectangle([x, y, x + 511, y + 255], fill=bg)
    d.polygon([(x + 380, y), (x + 512, y), (x + 512, y + 256), (x + 300, y + 256)], fill=acc)
    d.rectangle([x, y + 230, x + 511, y + 255], fill=acc)
    size = 96
    f1 = font("BebasNeue-Regular.ttf", size)
    while d.textlength(head, font=f1) > 330 and size > 40:   # keep the name clear of the accent stripe
        size -= 4
        f1 = font("BebasNeue-Regular.ttf", size)
    f2 = font("BarlowCondensed-SemiBold.ttf", 30)
    d.text((x + 28, y + 40), head, font=f1, fill=fg)
    d.text((x + 30, y + 160), tag, font=f2, fill=fg)
img.save(OUT)
print("ads atlas", OUT, len(ADS))
