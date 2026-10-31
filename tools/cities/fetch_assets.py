"""Download the CC0 texture and sky set for the city circuits (ambientCG + Poly Haven) into godot/assets/city/.
Idempotent: skips files already present. Writes CREDITS.md with every source URL."""
import io, json, os, sys, urllib.request, zipfile
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "godot", "assets", "city")
UA = {"User-Agent": "Mozilla/5.0 (GRIDLINE asset fetch)"}
# name -> ambientCG asset id (1K-JPG). Opacity is kept for the fence.
ACG = {
    "plaster_white": "Plaster004", "plaster_rough": "Plaster003", "plaster_old": "Plaster007",
    "concrete_patch": "Concrete024", "concrete_beige": "Concrete048", "concrete_grey": "Concrete034",
    "bricks_a": "Bricks105", "bricks_b": "Bricks113A",
    "ground_dirt": "Ground110", "ground_sand": "Ground093A", "grass": "Grass004",
    "road_aged": "Asphalt031", "road_dark": "Asphalt033", "paving": "PavingStones138",
    "fence": "Fence006", "tower_glass": "Facade001", "tower_white": "Facade006",
    "tower_brick": "Facade018A", "tower_brick_b": "Facade020A", "tower_lit": "Facade018C",
}
HDRI = {  # name -> (Poly Haven id, resolution)
    "clear": ("kloppenheim_06_puresky", "2k"), "partly": ("kloofendal_48d_partly_cloudy_puresky", "2k"),
    "overcast": ("kloofendal_overcast_puresky", "1k"), "sunset": ("industrial_sunset_puresky", "2k"),
    "night": ("qwantani_night_puresky", "1k"), "misty": ("kloofendal_misty_morning_puresky", "1k"),
}


def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120).read()


def main():
    os.makedirs(ROOT, exist_ok=True)
    credits = ["# City circuit assets (all CC0)", "", "| File | Source | Licence |", "|---|---|---|"]
    for name, aid in ACG.items():
        out = os.path.join(ROOT, name + "_albedo.jpg")
        credits.append(f"| {name}_* | https://ambientcg.com/view?id={aid} | CC0 1.0 |")
        if os.path.exists(out):
            continue
        z = zipfile.ZipFile(io.BytesIO(get(f"https://ambientcg.com/get?file={aid}_1K-JPG.zip")))
        for member in z.namelist():
            low = member.lower()
            key = ("albedo" if "_color" in low else "normal" if "normalgl" in low else
                   "opacity" if "opacity" in low else "rough" if "roughness" in low else None)
            if not key or not low.endswith((".jpg", ".png")):
                continue
            im = Image.open(io.BytesIO(z.read(member)))
            if key == "albedo" and name == "fence":   # pack opacity into alpha later
                im = im.convert("RGB")
            if im.width > 1024:
                im = im.resize((1024, 1024))
            ext = ".png" if key == "opacity" else ".jpg"
            im.convert("L" if key in ("opacity", "rough") else "RGB").save(os.path.join(ROOT, f"{name}_{key}{ext}"), quality=88)
        if name == "fence":
            a = Image.open(os.path.join(ROOT, "fence_albedo.jpg")).convert("RGB")
            o = Image.open(os.path.join(ROOT, "fence_opacity.png")).convert("L").resize(a.size)
            a.putalpha(o)
            a.save(os.path.join(ROOT, "fence_rgba.png"))
        print("texture", name, aid, flush=True)
    for name, (pid, res) in HDRI.items():
        out = os.path.join(ROOT, f"sky_{name}.hdr")
        credits.append(f"| sky_{name}.hdr | https://polyhaven.com/a/{pid} | CC0 1.0 |")
        if os.path.exists(out):
            continue
        files = json.loads(get(f"https://api.polyhaven.com/files/{pid}"))
        url = files["hdri"][res]["hdr"]["url"]
        open(out, "wb").write(get(url))
        print("hdri", name, pid, flush=True)
    open(os.path.join(ROOT, "CREDITS.md"), "w").write("\n".join(credits) + "\n")


if __name__ == "__main__":
    main()
