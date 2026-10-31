"""Team-operations screen content for the headquarters (not adverts): race schedule, live timing, speed-trace
telemetry (animated) and tyre temperatures, in the GRIDLINE graphite-and-amber style. Fictional data.

  python3 -I tools/ads/make_info_screens.py

Writes godot/assets/ads/screens/<id>.jpg (1280x720) and telemetry_speed.ogv (640x360, 8 s Theora loop). They are
used through the same placement registry as the adverts (data/ads/screens.json).
"""
import math, os, random, subprocess, tempfile
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "godot", "assets", "ads", "screens")
FONTS = os.path.join(HERE, "..", "..", "godot", "assets", "fonts")
BG, PANEL, LINE, TEXT, MUTED, AMBER, GREEN, PURPLE, RED = (12, 13, 16), (24, 26, 30), (52, 55, 62), (236, 236, 238), (150, 154, 162), (245, 140, 40), (110, 205, 120), (180, 115, 255), (230, 70, 60)


def f(name, size):
    return ImageFont.truetype(os.path.join(FONTS, name), size)


def frame(w=1280, h=720, title=""):
    img = Image.new("RGB", (w, h), BG)
    d = ImageDraw.Draw(img)
    k = w / 1280
    d.rectangle([0, 0, w, int(70 * k)], fill=PANEL)
    d.rectangle([int(40 * k), int(30 * k), int(80 * k), int(36 * k)], fill=AMBER)
    d.text((int(96 * k), int(14 * k)), title, font=f("BebasNeue-Regular.ttf", int(46 * k)), fill=TEXT)
    d.text((w - int(330 * k), int(22 * k)), "GRIDLINE · TEAM OPERATIONS", font=f("BarlowCondensed-SemiBold.ttf", int(26 * k)), fill=MUTED)
    return img, d, k


def schedule():
    img, d, k = frame(title="RACE SCHEDULE · SEASON 2026")
    rows = [("R4", "KITWE STREET CIRCUIT", "ZAMBIA", "SAT 14:00", "NEXT"), ("R5", "NAIROBI CITY GRAND PRIX", "KENYA", "SAT 16:30", ""),
            ("R6", "GIZA PLATEAU ROAD", "EGYPT", "SUN 10:00", ""), ("R7", "LONDON EMBANKMENT", "UNITED KINGDOM", "SAT 15:00", ""),
            ("R8", "BERLIN MITTE", "GERMANY", "SAT 18:00", "")]
    for i, (r, name, ctry, when, tag) in enumerate(rows):
        y = 110 + i * 112
        d.rectangle([40, y, 1240, y + 96], fill=PANEL, outline=AMBER if tag else LINE, width=3 if tag else 1)
        d.text((64, y + 18), r, font=f("BebasNeue-Regular.ttf", 58), fill=AMBER if tag else MUTED)
        d.text((180, y + 12), name, font=f("BebasNeue-Regular.ttf", 50), fill=TEXT)
        d.text((182, y + 60), ctry, font=f("BarlowCondensed-SemiBold.ttf", 26), fill=MUTED)
        d.text((960, y + 24), when, font=f("BarlowCondensed-Bold.ttf", 40), fill=TEXT)
        if tag:
            d.rectangle([1130, y + 30, 1220, y + 66], fill=AMBER)
            d.text((1146, y + 30), "NEXT", font=f("BarlowCondensed-Bold.ttf", 30), fill=BG)
    return img


def timing():
    img, d, k = frame(title="LIVE TIMING · PRACTICE 2 · KITWE")
    d.text((60, 92), "POS   DRIVER                          TEAM                     BEST LAP      GAP     LAPS", font=f("BarlowCondensed-Bold.ttf", 26), fill=MUTED)
    rows = [("1", "M. REYES", "HALDEN MOTORSPORT", "1:31.383", "", "14"), ("2", "E. LINDQVIST", "CORSAIR RACING", "1:31.517", "+0.134", "15"),
            ("3", "YOU", "GRIDLINE TEAM", "1:31.902", "+0.519", "12"), ("4", "D. OKAFOR", "VANTOR ENGINEERING", "1:32.260", "+0.877", "13"),
            ("5", "J. BRANDT", "NORTHLINE GP", "1:32.845", "+1.462", "16")]
    for i, (p, n, t, best, gap, laps) in enumerate(rows):
        y = 140 + i * 104
        you = n == "YOU"
        d.rectangle([40, y, 1240, y + 90], fill=(38, 30, 22) if you else PANEL, outline=AMBER if you else LINE, width=3 if you else 1)
        d.text((64, y + 14), p, font=f("BebasNeue-Regular.ttf", 58), fill=AMBER if int(p) <= 3 else MUTED)
        d.text((150, y + 20), n, font=f("BarlowCondensed-Bold.ttf", 44), fill=TEXT)
        d.text((520, y + 26), t, font=f("BarlowCondensed-SemiBold.ttf", 34), fill=MUTED)
        d.text((860, y + 20), best, font=f("BarlowCondensed-Bold.ttf", 44), fill=PURPLE if p == "1" else TEXT)
        d.text((1050, y + 26), gap, font=f("BarlowCondensed-SemiBold.ttf", 34), fill=MUTED)
        d.text((1180, y + 26), laps, font=f("BarlowCondensed-SemiBold.ttf", 34), fill=MUTED)
    return img


def speed_trace(progress=1.0, w=1280, h=720):
    img, d, k = frame(w, h, "TELEMETRY · SPEED TRACE · LAP 12")
    x0, x1, y0, y1 = int(70 * k), int(1230 * k), int(130 * k), int(560 * k)
    d.rectangle([x0, y0, x1, y1], fill=PANEL)
    for g in range(1, 6):
        yy = y0 + (y1 - y0) * g // 6
        d.line([x0, yy, x1, yy], fill=LINE, width=1)
    for s in (0.33, 0.66):
        xx = int(x0 + (x1 - x0) * s)
        d.line([xx, y0, xx, y1], fill=AMBER, width=max(1, int(2 * k)))
    rng = random.Random(4)

    def speed(t):
        return 0.55 + 0.35 * math.sin(t * 9.0) * math.sin(t * 3.1 + 0.4) + 0.08 * math.sin(t * 40)

    pts_ref = [(x0 + (x1 - x0) * t, y1 - (y1 - y0) * speed(t + 0.003)) for t in [i / 400 for i in range(401)]]
    pts = [(x0 + (x1 - x0) * t, y1 - (y1 - y0) * speed(t)) for t in [i / 400 for i in range(int(401 * progress))]]
    d.line(pts_ref, fill=(90, 94, 104), width=max(1, int(2 * k)))
    if len(pts) > 1:
        d.line(pts, fill=AMBER, width=max(2, int(4 * k)))
    for i, (lab, val, col) in enumerate([("SECTOR 1", "28.412", GREEN), ("SECTOR 2", "33.105", PURPLE), ("SECTOR 3", "30.383", TEXT)]):
        x = int((90 + i * 390) * k)
        d.text((x, int(590 * k)), lab, font=f("BarlowCondensed-SemiBold.ttf", int(26 * k)), fill=MUTED)
        d.text((x, int(622 * k)), val, font=f("BebasNeue-Regular.ttf", int(56 * k)), fill=col)
    return img


def tyres():
    img, d, k = frame(title="TYRES · TEMPERATURE & WEAR")
    for i, (lab, temps, wear) in enumerate([("FRONT LEFT", (92, 96, 99), 18), ("FRONT RIGHT", (97, 101, 104), 22), ("REAR LEFT", (88, 90, 91), 12), ("REAR RIGHT", (90, 93, 95), 15)]):
        x = 80 + (i % 2) * 600
        y = 110 + (i // 2) * 300
        d.rectangle([x, y, x + 520, y + 270], fill=PANEL, outline=LINE)
        d.text((x + 24, y + 16), lab, font=f("BarlowCondensed-Bold.ttf", 34), fill=TEXT)
        for j, t in enumerate(temps):
            c = (int(80 + (t - 85) * 9), int(170 - (t - 85) * 6), 60)
            d.rectangle([x + 24 + j * 120, y + 70, x + 130 + j * 120, y + 190], fill=c)
            d.text((x + 40 + j * 120, y + 112), "%d°" % t, font=f("BebasNeue-Regular.ttf", 44), fill=BG)
        d.text((x + 400, y + 90), "WEAR", font=f("BarlowCondensed-SemiBold.ttf", 26), fill=MUTED)
        d.text((x + 400, y + 120), "%d%%" % wear, font=f("BebasNeue-Regular.ttf", 64), fill=AMBER)
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in [("race_schedule", schedule), ("live_timing", timing), ("telemetry_speed", speed_trace), ("telemetry_tyres", tyres)]:
        fn().save(os.path.join(OUT, name + ".jpg"), quality=88)
        print("still", name)
    with tempfile.TemporaryDirectory() as tmp:
        for i in range(8 * 24):
            speed_trace((i % 96) / 95.0, 640, 360).save(os.path.join(tmp, "f%04d.png" % i))
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-framerate", "24", "-i", os.path.join(tmp, "f%04d.png"), "-c:v", "libtheora", "-q:v", "6",
                        "-pix_fmt", "yuv420p", os.path.join(OUT, "telemetry_speed.ogv")], check=True)
    print("video telemetry_speed")


if __name__ == "__main__":
    main()
