"""Real buildings and landmarks from downloaded third-party models (Sketchfab, CC BY / CC0), made game-ready.

  blender -b --python tools/buildings/export_real_buildings.py -- [id ...]

For every entry in real_catalogue.json: import the model's glTF from /home/user/deps/sketchfab/<uid>/gltf, keep the
objects the entry's include/exclude regexes select, join them, scale to the real height in metres, put the origin
at the centre of the base, turn the most detailed side (the facade: the side with the most faces) to face front
(Godot +Z), decimate to the triangle budget, shrink textures to 1024 px and export glTF + textures to
godot/assets/buildings/real/<id>/. Writes real/index.json with each model's footprint, height, triangles and
licence, which RealBuildings uses to pick and fit models to OSM footprints and the credits page lists.
"""
import bpy, bmesh, glob, json, math, os, re, sys, mathutils

HERE = os.path.dirname(os.path.abspath(__file__))
CAT = json.load(open(os.path.join(HERE, "real_catalogue.json")))
OUT = os.path.join(HERE, "..", "..", "godot", "assets", "buildings", "real")
SRC = "/home/user/deps/sketchfab"
MANIFEST = json.load(open(os.path.join(SRC, "manifest.json")))
ONLY = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
TEX = 1024


def tris_of(objs):
    n = 0
    for o in objs:
        for p in o.data.polygons:
            n += len(p.vertices) - 2
    return n


def bounds(objs):
    mn = mathutils.Vector((1e18,) * 3)
    mx = -mn
    for o in objs:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            mn = mathutils.Vector(map(min, mn, w))
            mx = mathutils.Vector(map(max, mx, w))
    return mn, mx


def export(entry):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    files = glob.glob(f"{SRC}/{entry['uid']}/gltf/**/*.gltf", recursive=True) + glob.glob(f"{SRC}/{entry['uid']}/gltf/**/*.glb", recursive=True)
    bpy.ops.import_scene.gltf(filepath=files[0])
    inc = re.compile(entry.get("include", "."))
    exc = re.compile(entry["exclude"]) if entry.get("exclude") else None
    keep = [o for o in bpy.context.scene.objects if o.type == "MESH" and inc.search(o.name) and not (exc and exc.search(o.name))]
    for o in list(bpy.context.scene.objects):
        if o not in keep and o.type == "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    # Bake every transform into the meshes (glTF imports often carry unit scale and rotation on parents).
    for o in keep:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    bpy.ops.object.select_all(action="DESELECT")
    for o in keep:
        o.select_set(True)
    bpy.context.view_layer.objects.active = keep[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    src_tris = tris_of([ob])
    # Scale to the real height, origin at the base centre.
    mn, mx = bounds([ob])
    s = entry["height"] / max(mx.z - mn.z, 1e-6)
    c = (mn + mx) / 2
    for v in ob.data.vertices:
        v.co = (v.co - mathutils.Vector((c.x, c.y, mn.z))) * s
    # Facade: the side whose outward faces hold the most polygons (windows, doors, cornices) faces -Y (Godot +Z).
    front = entry.get("front", "auto")
    if front == "auto":
        score = {"+x": 0.0, "-x": 0.0, "+y": 0.0, "-y": 0.0}
        for p in ob.data.polygons:
            n = p.normal
            for k, axis in (("+x", (1, 0)), ("-x", (-1, 0)), ("+y", (0, 1)), ("-y", (0, -1))):
                if n.x * axis[0] + n.y * axis[1] > 0.7:
                    score[k] += 1.0
        front = max(score, key=score.get)
    turn = {"-y": 0.0, "+x": -math.pi / 2, "+y": math.pi, "-x": math.pi / 2}[front]
    rot = mathutils.Matrix.Rotation(turn, 4, "Z")
    for v in ob.data.vertices:
        v.co = rot @ v.co
    ob.data.update()
    # Decimate to budget.
    if src_tris > entry["budget"]:
        m = ob.modifiers.new("dec", "DECIMATE")
        m.decimate_type = "COLLAPSE"
        m.ratio = entry["budget"] / src_tris
        m.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier="dec")
    final = tris_of([ob])
    # Textures: at most 1024 px.
    for img in bpy.data.images:
        if img.size[0] > TEX or img.size[1] > TEX:
            k = TEX / max(img.size[0], img.size[1])
            img.scale(max(4, int(img.size[0] * k)), max(4, int(img.size[1] * k)))
    for mat in bpy.data.materials:   # restyle hooks in Godot key on these names
        mat.name = re.sub(r"[^A-Za-z0-9_]", "_", mat.name)[:40]
    mn, mx = bounds([ob])
    out_dir = os.path.join(OUT, entry["id"])
    os.makedirs(out_dir, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, entry["id"] + ".gltf"), export_format="GLTF_SEPARATE",
                              export_texture_dir="textures", export_image_format="JPEG", export_jpeg_quality=85,
                              export_yup=True, export_apply=True, export_animations=False, export_cameras=False, export_lights=False)
    man = MANIFEST.get(entry["uid"], {})
    info = {"id": entry["id"], "kind": entry["kind"], "cities": entry["cities"],
            "width": round(mx.x - mn.x, 2), "depth": round(mx.y - mn.y, 2), "height": round(mx.z - mn.z, 2),
            "tris": final, "source_tris": src_tris, "front": front,
            "name": man.get("name", ""), "author": man.get("author", ""), "licence": man.get("license", ""), "url": man.get("url", "")}
    with open(os.path.join(out_dir, "LICENSE.txt"), "w") as f:
        f.write(f"{info['name']} by {info['author']} — {info['licence']}\n{info['url']}\nModified for GRIDLINE: decimated, rescaled, re-oriented, textures resized.\n")
    print("EXPORTED", json.dumps(info))
    return info


index_path = os.path.join(OUT, "index.json")
index = json.load(open(index_path)) if os.path.exists(index_path) else {}
for e in CAT["buildings"] + CAT["landmarks"]:
    if ONLY and e["id"] not in ONLY:
        continue
    try:
        index[e["id"]] = export(e)
    except Exception as ex:
        print("FAILED", e["id"], ex)
os.makedirs(OUT, exist_ok=True)
json.dump(index, open(index_path, "w"), indent=1, sort_keys=True)
