"""16:9 creatives for the in-world digital screens (fictional GRIDLINE sponsors only, no real brands).

  python3 -I tools/ads/make_screen_ads.py

Writes godot/assets/ads/screens/:
  <id>.jpg   1280x720 static creative (also the fallback frame for each video)
  <id>.ogv   640x360 Theora video, 8 s loop, 24 fps (Kafue Cola, Volt Rush, Arden Motors)
The registry godot/data/ads/screens.json maps every screen placement to one of these; swap the file or edit the
JSON to change what a screen shows without touching any scene.
"""
import math, os, subprocess, tempfile
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "godot", "assets", "ads", "screens")
FONTS = os.path.join(HERE, "..", "..", "godot", "assets", "fonts")
ADS = {   # id: (headline, tagline, colours top, bottom, text, accent)
    "kafue_cola": ("KAFUE COLA", "ICE COLD SINCE 1974", "#e0182e", "#7a0614", "#ffffff", "#ffd400"),
    "arden_motors": ("ARDEN MOTORS", "THE NEW V8 COUPÉ · DRIVEN BY YOU", "#1b1d22", "#5a0612", "#ffffff", "#e8e8e8"),
    "volt_rush": ("VOLT RUSH", "ENERGY DRINK · CHARGE THE LAP", "#00c2e8", "#023e8a", "#ffffff", "#f9f871"),
    "savanna_air": ("SAVANNA AIR", "FLY THE CONTINENT · 48 CITIES", "#fbf6ea", "#e8c896", "#1a3b6e", "#e8701a"),
    "copperline_tyres": ("COPPERLINE TYRES", "GRIP THAT HOLDS", "#151515", "#2b2b2b", "#f2a900", "#f2a900"),
    "nile_energy": ("NILE ENERGY", "FUEL FOR THE BRAVE", "#0b4f9c", "#06244a", "#ffffff", "#2ec4ff"),
    "zedbank": ("ZEDBANK", "BANKING ON THE MOVE", "#11904c", "#064d27", "#ffffff", "#f7c600"),
    "gridline": ("GRIDLINE", "THE RACING LEAGUE · SEASON 2026", "#0d0f12", "#1c2027", "#ffffff", "#f0b83a"),
}
VIDEOS = ["kafue_cola", "volt_rush", "arden_motors"]


def font(name, size):
    for f in (name, "BebasNeue-Regular.ttf"):
        p = os.path.join(FONTS, f)
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def gradient(w, h, top, bottom):
    img = Image.new("RGB", (w, h))
    a, b = hexc(top), hexc(bottom)
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / (h - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3)))
    return img


def frame(ad_id, w, h, t=1.0):
    """One frame of the creative; t in [0, 1] drives the animation (1.0 = the settled still)."""
    head, tag, top, bottom, fg, acc = ADS[ad_id]
    img = gradient(w, h, top, bottom)
    d = ImageDraw.Draw(img, "RGBA")
    k = w / 1280.0
    ease = 1 - (1 - min(1.0, t * 1.6)) ** 3
    # motif per brand
    if ad_id == "kafue_cola":
        for i in range(70):   # rising bubbles
            bx = (i * 97 % 1280) * k
            by = ((i * 53 - t * 900 * (0.6 + (i % 5) * 0.1)) % 760 - 20) * k
            r = (4 + i % 7) * k
            d.ellipse([bx - r, by - r, bx + r, by + r], outline=(255, 255, 255, 120), width=max(1, int(2 * k)))
        d.rounded_rectangle([900 * k, 120 * k, 1060 * k, 640 * k], radius=int(60 * k), fill=(140, 10, 22, 255))   # can
        d.rectangle([900 * k, 300 * k, 1060 * k, 420 * k], fill=hexc(acc))
    elif ad_id == "volt_rush":
        for i in range(9):   # lightning streaks
            x0 = ((i * 160 + t * 1400) % 1500 - 100) * k
            d.polygon([(x0, 0), (x0 + 60 * k, 0), (x0 - 140 * k, h), (x0 - 200 * k, h)], fill=(255, 255, 255, 38))
        d.polygon([(960 * k, 90 * k), (1060 * k, 90 * k), (1010 * k, 330 * k), (1110 * k, 330 * k), (930 * k, 650 * k),
                   (990 * k, 400 * k), (900 * k, 400 * k)], fill=hexc(acc))
    elif ad_id == "arden_motors":
        sweep = (t * 1.4 % 1.0) * 1600 - 200
        d.polygon([(sweep * k, 0), ((sweep + 160) * k, 0), ((sweep - 240) * k, h), ((sweep - 400) * k, h)], fill=(255, 255, 255, 30))
        # coupé silhouette
        pts = [(700, 520), (760, 440), (900, 395), (1060, 390), (1150, 440), (1230, 470), (1240, 520)]
        d.polygon([(x * k, y * k) for x, y in pts], fill=(10, 10, 12, 255))
        for cx in (800, 1150):
            d.ellipse([(cx - 42) * k, 480 * k, (cx + 42) * k, 564 * k], fill=(20, 20, 22, 255), outline=(200, 200, 200, 255), width=int(4 * k))
    elif ad_id == "savanna_air":
        d.ellipse([820 * k, 80 * k, 1180 * k, 440 * k], fill=(232, 112, 26, 255))
        d.polygon([(900 * k, 300 * k), (1220 * k, 250 * k), (1230 * k, 270 * k), (920 * k, 330 * k)], fill=hexc(fg))
    else:
        d.polygon([(880 * k, 0), (w, 0), (w, h), (740 * k, h)], fill=hexc(acc) + (255,))
    # type: headline slides in, tagline fades in
    hf = font("BebasNeue-Regular.ttf", int(150 * k))
    tf = font("BarlowCondensed-SemiBold.ttf", int(46 * k))
    x = (80 - (1 - ease) * 300) * k
    d.text((x, 230 * k), head, font=hf, fill=hexc(fg) + (int(255 * ease),))
    d.rectangle([x, 395 * k, x + 120 * k * ease, 404 * k], fill=hexc(acc) + (255,))
    d.text((x, 420 * k), tag, font=tf, fill=hexc(fg) + (int(255 * max(0.0, t * 2 - 0.6)) if t < 1 else 255,))
    d.text((80 * k, 640 * k), "FICTIONAL SPONSOR · GRIDLINE DEMO CREATIVE", font=font("BarlowCondensed-SemiBold.ttf", int(20 * k)),
           fill=hexc(fg) + (110,))
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    for ad_id in ADS:
        frame(ad_id, 1280, 720).save(os.path.join(OUT, ad_id + ".jpg"), quality=88)
        print("still", ad_id)
    for ad_id in VIDEOS:
        with tempfile.TemporaryDirectory() as tmp:
            n = 8 * 24
            for i in range(n):
                t = i / n
                img = frame(ad_id, 640, 360, t if t < 0.6 else 1.0 + (t - 0.6))   # animate in, then hold with motion
                img.save(os.path.join(tmp, "f%04d.png" % i))
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-framerate", "24", "-i", os.path.join(tmp, "f%04d.png"),
                            "-c:v", "libtheora", "-q:v", "6", "-pix_fmt", "yuv420p", os.path.join(OUT, ad_id + ".ogv")], check=True)
        print("video", ad_id, os.path.getsize(os.path.join(OUT, ad_id + ".ogv")) // 1024, "KB")
    with open(os.path.join(OUT, "LICENSE.md"), "w") as f:
        f.write("Fictional demonstration creatives generated by tools/ads/make_screen_ads.py (project-owned). "
                "No real brands. Replace via godot/data/ads/screens.json when licensed campaigns exist.\n")


if __name__ == "__main__":
    main()
