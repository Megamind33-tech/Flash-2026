"""Download and install the GRIDLINE Blender add-on set from the official extensions catalogue.

Every archive is checked against the SHA-256 that extensions.blender.org publishes for it. Nothing is installed
unless the hash matches. Install target: Blender's user repository, so the add-ons are available to every
headless `blender -b` run in tools/.

    python3 -I tools/deps/fetch_blender_addons.py /home/user/deps/blender-5.2.2/blender /home/user/deps/blender-addons

Add-ons not in the catalogue (BlenderKit, BlenderGIS) are handled in docs/BLENDER_ADDONS.md, not here.
"""
import hashlib, json, os, subprocess, sys, urllib.request

CATALOGUE = "https://extensions.blender.org/api/v1/extensions/?type=add-on&limit=100"
UA = {"User-Agent": "Mozilla/5.0 (GRIDLINE add-on fetch)"}

# id -> why GRIDLINE needs it
ADDONS = {
    "lod_gen": "Generate LOD chains for props and cars (gate G2/G3)",
    "proto_game_asset_tools": "Game-ready export and naming for Godot (glTF path, gate G3)",
    "omi_physics_body_gltf_extension": "Export collision shapes into glTF for Godot physics bodies",
    "thebetterbaker": "PBR baking for facades, props and car paint (gates G6, G10)",
    "bake_preflight": "Catch common bake mistakes before baking",
    "gorani": "Urban site context: buildings, roads and terrain from data (gate G7)",
    "pterrain": "Real-world progressive terrain for scenic venues",
    "srtm_terrain_importer": "SRTM elevation for scenic venue terrain",
    "PolyQuilt_Fork": "Retopology for car and kit meshes",
    "hardflow": "Hard-surface boolean modelling toolkit (cars, kit modules)",
    "bagapie": "Scattering, ivy and architecture helpers for the kit",
    "ambientcg_material_importer": "Import ambientCG CC0 materials as PBR setups",
}


def catalogue():
    out, url = [], CATALOGUE
    while url:
        d = json.load(urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60))
        out += d["data"]
        url = d.get("next")
    return out


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main(blender, outdir):
    os.makedirs(outdir, exist_ok=True)
    by_id = {e["id"]: e for e in catalogue()}
    for ext_id, why in ADDONS.items():
        e = by_id.get(ext_id)
        if e is None:
            print(f"MISSING in catalogue: {ext_id}", flush=True)
            continue
        want = e["archive_hash"].split(":", 1)[1]
        dest = os.path.join(outdir, f"{ext_id}-{e['version']}.zip")
        if not (os.path.exists(dest) and sha256_of(dest) == want):
            data = urllib.request.urlopen(urllib.request.Request(e["archive_url"], headers=UA), timeout=300).read()
            with open(dest, "wb") as f:
                f.write(data)
        if sha256_of(dest) != want:
            raise SystemExit(f"SHA-256 mismatch for {ext_id}")
        r = subprocess.run([blender, "-b", "--factory-startup", "--command", "extension", "install-file",
                            "--repo", "user_default", "--enable", dest], capture_output=True, text=True)
        status = "installed" if r.returncode == 0 else f"install failed ({r.returncode})"
        print(f"{status:<10} {ext_id} {e['version']}  min Blender {e.get('blender_version_min','?')}  -- {why}", flush=True)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: fetch_blender_addons.py <blender-binary> <download-folder>")
    main(sys.argv[1], sys.argv[2])
