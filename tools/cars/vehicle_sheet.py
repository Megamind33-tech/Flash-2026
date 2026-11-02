"""Assemble the per-car validation renders from tools/vehicle_sheet.gd into one labelled sheet per car.
python3 tools/cars/vehicle_sheet.py <in_dir> <out_dir> [car ...]"""
import os, sys
from PIL import Image, ImageDraw, ImageFont
LABELS = ["1 front 3/4", "2 rear 3/4", "3 front wheel", "4 rear wheel", "5 full steering lock",
          "6 moving 40 km/h", "7 moving 120 km/h", "8 hard braking (dive)", "9 steady turn (roll)"]
src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)
cars = sys.argv[3:] or sorted({f.rsplit("_", 1)[0] for f in os.listdir(src) if f.endswith(".png")})
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 18)
    big = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 26)
except OSError:
    font = big = ImageFont.load_default()
for car in cars:
    w, h = 640, 400
    sheet = Image.new("RGB", (w * 3, h * 3 + 40), (18, 18, 20))
    d = ImageDraw.Draw(sheet)
    d.text((12, 6), car, fill=(255, 160, 40), font=big)
    for i, lab in enumerate(LABELS):
        p = os.path.join(src, "%s_%d.png" % (car, i + 1))
        if not os.path.exists(p):
            continue
        im = Image.open(p).convert("RGB").resize((w, h))
        x, y = (i % 3) * w, 40 + (i // 3) * h
        sheet.paste(im, (x, y))
        d.rectangle((x, y, x + 260, y + 28), fill=(0, 0, 0))
        d.text((x + 8, y + 4), lab, fill=(255, 255, 255), font=font)
    sheet.save(os.path.join(dst, car + ".jpg"), quality=85)
    print("sheet", car)
