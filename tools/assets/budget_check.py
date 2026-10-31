"""Gate G2: triangle and texture budgets for every GLB in godot/assets (docs/PRODUCTION_PLAN.md §4).

  python3 -I tools/assets/budget_check.py [--strict]

Reads each .glb directly (glTF JSON + binary chunk, no Blender needed) and counts triangles per mesh and per
file, plus the pixel size of every embedded texture. Each file is matched to a budget class by path. The
script prints a table and exits non-zero if any asset is over budget. Without --strict, known exceptions
listed in WAIVED are reported but do not fail; with --strict (CI), they fail too.
"""
import glob, io, json, os, struct, sys
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "godot", "assets")
# (path substring, class, max triangles per file at LOD0, max per single mesh, max texture edge px)
RULES = [
    ("models/cars/", "player car", 80000, 80000, 2048),
    ("buildings/", "facade module", 60000, 2000, 2048),
    ("ads/hardware/", "ad hardware", 1000, 1000, 0),
    ("hydrant", "hydrant", 1500, 1500, 1024),
    ("lamp", "street lamp", 2000, 2000, 1024),
    ("barrier", "barrier segment", 1000, 1000, 1024),
    ("guardrail", "barrier segment", 1000, 1000, 1024),
    ("on_broken_asphalt", "road patch scan", 3000, 3000, 1024),   # scanned road surface around a cover
    ("manhole", "manhole", 500, 500, 1024),
    ("electrical_box", "utility box", 800, 800, 1024),
    ("utility", "utility box", 800, 800, 1024),
    ("props/", "street prop", 3000, 3000, 1024),
    ("models/ashford_circuit", "legacy circuit", 10 ** 9, 10 ** 9, 0),
]
# Known, documented exceptions (fixed by later gates); --strict ignores this list.
WAIVED = {"models/cars/arden_v8.glb": "trim overlaps the paint below subdivision 2; restyle/rebuild under G10",
          "models/cars/elektra_egt.glb": "84.5k vs 80k; decimate under G10"}


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, _, _ = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67:
        raise ValueError("not a GLB")
    off, js, binary = 12, None, b""
    while off < len(data):
        ln, typ = struct.unpack_from("<II", data, off)
        chunk = data[off + 8: off + 8 + ln]
        if typ == 0x4E4F534A:
            js = json.loads(chunk)
        elif typ == 0x004E4942:
            binary = chunk
        off += 8 + ln
    return js, binary


def triangles(js):
    per_mesh = []
    acc = js.get("accessors", [])
    for mesh in js.get("meshes", []):
        t = 0
        for p in mesh.get("primitives", []):
            if p.get("mode", 4) != 4:
                continue
            if "indices" in p:
                t += acc[p["indices"]]["count"] // 3
            else:
                t += acc[p["attributes"]["POSITION"]]["count"] // 3
        per_mesh.append((mesh.get("name", "?"), t))
    return per_mesh


def textures(js, binary):
    sizes = []
    for img in js.get("images", []):
        if "bufferView" not in img:
            continue
        bv = js["bufferViews"][img["bufferView"]]
        raw = binary[bv.get("byteOffset", 0): bv.get("byteOffset", 0) + bv["byteLength"]]
        try:
            sizes.append(Image.open(io.BytesIO(raw)).size)
        except Exception:
            pass
    return sizes


def main():
    strict = "--strict" in sys.argv
    fails, rows = 0, []
    for path in sorted(glob.glob(os.path.join(ROOT, "**", "*.glb"), recursive=True)):
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        rule = next((r for r in RULES if r[0] in rel), ("", "unclassified", 20000, 20000, 2048))
        js, binary = read_glb(path)
        meshes = triangles(js)
        total = sum(t for _, t in meshes)
        worst = max(meshes, key=lambda m: m[1]) if meshes else ("-", 0)
        tex = textures(js, binary)
        edge = max([max(s) for s in tex], default=0)
        problems = []
        if total > rule[2]:
            problems.append(f"{total} tris > {rule[2]}")
        if worst[1] > rule[3]:
            problems.append(f"mesh '{worst[0]}' {worst[1]} > {rule[3]}")
        if rule[4] and edge > rule[4]:
            problems.append(f"texture {edge}px > {rule[4]}")
        status = "ok"
        if problems:
            if rel in WAIVED and not strict:
                status = "WAIVED (" + WAIVED[rel] + ")"
            else:
                status = "FAIL"
                fails += 1
        rows.append((rel, rule[1], total, edge, status, "; ".join(problems)))
    w = max(len(r[0]) for r in rows)
    for rel, cls, total, edge, status, why in rows:
        print(f"{rel:<{w}}  {cls:<16} {total:>8} tris  tex {edge:>4}px  {status}  {why}")
    print(f"budget check: {len(rows)} assets, {fails} over budget{' (strict)' if strict else ''}")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
