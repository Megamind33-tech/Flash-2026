"""Milestone 1 - premium showroom / team garage assets, all CC0 from Poly Haven (polyhaven.com/license).

    python3 -I tools/assets/fetch_garage.py

Writes godot/assets/garage/:
  hdri/<id>_1k.hdr          interior HDRI for image-based lighting and paint/glass reflections
  models/<id>/<id>_1k.gltf  workshop props (gltf + bin + 1k textures), MD5-checked against the API
  CREDITS.md                source URL, author and licence for every asset
"""
import hashlib, json, os, urllib.request

UA = {"User-Agent": "Mozilla/5.0 (GRIDLINE asset fetch)"}
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "godot", "assets", "garage")
HDRIS = ["skylit_garage"]
MODELS = ["metal_tool_chest", "tool_cart", "worn_metal_rack", "old_tyre", "portable_welding_cart", "mounted_fluorescent_lights",
          "hanging_industrial_lamp", "metal_jerrycan", "plastic_crate_01", "portable_generator", "covered_car", "tire_pump",
          "metal_office_desk", "metal_stool_01", "industrial_storage_cart", "ladder_sectioned_01"]


def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=180).read()


def save(url, dest, md5=None):
    if os.path.exists(dest) and md5 and hashlib.md5(open(dest, "rb").read()).hexdigest() == md5:
        return "ok  "
    data = get(url)
    if md5 and hashlib.md5(data).hexdigest() != md5:
        raise SystemExit("MD5 mismatch " + url)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    open(dest, "wb").write(data)
    return "got "


def main():
    credits = ["# Garage / showroom assets", "", "All from Poly Haven, licence **CC0** (https://polyhaven.com/license).", "",
               "| Asset | Type | Authors | Source |", "|---|---|---|---|"]
    for h in HDRIS:
        node = json.loads(get("https://api.polyhaven.com/files/" + h))["hdri"]["1k"]["hdr"]
        print(save(node["url"], os.path.join(ROOT, "hdri", h + "_1k.hdr"), node.get("md5")), h, flush=True)
        info = json.loads(get("https://api.polyhaven.com/info/" + h))
        credits.append("| %s | HDRI 1k | %s | https://polyhaven.com/a/%s |" % (info["name"], ", ".join(info.get("authors", {})), h))
    for m in MODELS:
        node = json.loads(get("https://api.polyhaven.com/files/" + m))["gltf"]["1k"]["gltf"]
        base = os.path.join(ROOT, "models", m)
        print(save(node["url"], os.path.join(base, m + "_1k.gltf"), node.get("md5")), m, flush=True)
        for rel, inc in node.get("include", {}).items():
            save(inc["url"], os.path.join(base, rel), inc.get("md5"))
        info = json.loads(get("https://api.polyhaven.com/info/" + m))
        credits.append("| %s | model 1k | %s | https://polyhaven.com/a/%s |" % (info["name"], ", ".join(info.get("authors", {})), m))
    open(os.path.join(ROOT, "CREDITS.md"), "w").write("\n".join(credits) + "\n")


if __name__ == "__main__":
    main()
