"""Download CC0 PBR textures and glTF models from Poly Haven into a staging folder.

Nothing is written into the repo by default. Pass an output folder; every file is MD5-checked against the
hash the Poly Haven API publishes, and CREDITS.md records each source URL and licence.

    python3 -I tools/assets/fetch_polyhaven.py /home/user/deps/assets-staging

Idempotent: files already present with the right MD5 are skipped.
"""
import hashlib, json, os, sys, urllib.request

UA = {"User-Agent": "Mozilla/5.0 (GRIDLINE asset fetch)"}
API = "https://api.polyhaven.com/files/"

# Road surfaces: diffuse + GL normal + roughness + displacement (displacement drives real pothole geometry).
TEXTURE_SETS = ["asphalt_02", "asphalt_03", "asphalt_04", "asphalt_track", "asphalt_pit_lane",
                "brick_pavement_02", "cobblestone_floor_01"]
TEXTURE_MAPS = ["Diffuse", "nor_gl", "Rough", "Displacement"]
TEXTURE_RES = "2k"

# Street furniture and facade modules used for hand-placed, non-procedural scenery.
MODELS = {
    "concrete_road_barrier_02": "1k", "street_lamp_01": "1k", "fire_hydrant": "1k",
    "water_manhole_cover": "1k", "utility_box_01": "1k", "modular_electricity_poles": "1k",
    "modular_fire_escape": "1k", "modular_metal_gutter": "1k", "rollershutter_window_01": "1k",
    "modular_urban_apartments_facade": "1k", "modular_factory_facade": "1k",
}


def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=180).read()


def md5_ok(path, want):
    if not want:
        return os.path.exists(path)
    if not os.path.exists(path):
        return False
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest() == want


def save(url, dest, md5=None):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if md5_ok(dest, md5):
        return "cached"
    data = get(url)
    if md5 and hashlib.md5(data).hexdigest() != md5:
        raise SystemExit(f"MD5 mismatch for {url}")
    with open(dest, "wb") as f:
        f.write(data)
    return "downloaded"


def main(out):
    credits = ["# Poly Haven assets (all CC0 1.0)", "", "| Asset | Source | Licence |", "|---|---|---|"]
    for aid in TEXTURE_SETS:
        files = json.loads(get(API + aid))
        for m in TEXTURE_MAPS:
            node = files[m][TEXTURE_RES]
            fmt = "jpg" if "jpg" in node else "png"
            info = node[fmt]
            dest = os.path.join(out, "textures", f"{aid}_{m.lower()}_{TEXTURE_RES}.{fmt}")
            print(save(info["url"], dest, info.get("md5")), dest, flush=True)
        credits.append(f"| {aid} (textures) | https://polyhaven.com/a/{aid} | CC0 1.0 |")
    for mid, res in MODELS.items():
        node = json.loads(get(API + mid))["gltf"][res]["gltf"]
        base = os.path.join(out, "models", mid)
        print(save(node["url"], os.path.join(base, f"{mid}_{res}.gltf"), node.get("md5")), mid, flush=True)
        for rel, info in node.get("include", {}).items():
            print(save(info["url"], os.path.join(base, rel), info.get("md5")), rel, flush=True)
        credits.append(f"| {mid} (model) | https://polyhaven.com/a/{mid} | CC0 1.0 |")
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "CREDITS.md"), "w") as f:
        f.write("\n".join(credits) + "\n")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: fetch_polyhaven.py <output-folder>")
    main(sys.argv[1])
