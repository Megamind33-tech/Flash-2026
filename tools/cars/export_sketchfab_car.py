"""Headless Blender: convert a downloaded Sketchfab glTF car (CC-BY) into a GRIDLINE game car (.glb + spec .json).

  blender -b --python tools/cars/export_sketchfab_car.py -- <car_id> <model_dir> <out_dir>

Differences from export_car.py (which flattens every material to a canonical colour): this keeps the author's
textured materials (tyre tread and sidewall, rims, brake discs, light lenses, interior, carbon) with their UVs, so
the car keeps its detail. Only these are replaced by GRIDLINE's canonical slots, which the game drives at runtime:
  GL_paint  (body colour / livery, clear-coat paint in game), also every livery or sponsor-decal sheet
  GL_glass  (tinted glass)        GL_tail (brake lamps: lit by the brake)       GL_carbon / GL_black (branded trim)
Everything else is exported as KEEP_<name> and used as authored.
It also: drops maker badges / lettering (by part name or material), splits the four wheels (tyre + rim + disc)
from the body by connected geometry, leaves brake calipers on the body (they must not spin), orients the car with
its front to -Y (Godot +Z), scales to a real length, puts the tyre contact patch at z = 0, decimates to the LOD0
budget (Godot generates the lower LODs on import), and shrinks textures to 1024 px.
"""
import bpy, bmesh, sys, re, json, math, os
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

CARS = {
    # BMW-like CSL coupe (Black Snow, CC-BY-4.0): roundels are the M4xNME_Badge material
    "arden_v8": dict(src="m4csl", length=4.80, forward="-y", tyre_mat=r"^scene_-_root",
                     drop_mat=r"badge", drop=r"badge|logo|emblem|interior_light|license|plate",
                     paint=r"_paint(\.|$|_)|_paint2|colorable", glass=r"glassclear|glass(\.|$)", tail=r"taillight|fogred|brakelight"),
    # 911-like GT3 RS (Black Snow, CC-BY-4.0): crest / lettering are the "symbols" sheets on exterior parts
    "arden_gt3": dict(src="gt3rs", length=4.57, forward="-y", tyre_mat=r"^scene_-_root",
                      drop_mat=r"symbols\.004(_0)?$", drop=r"badge|logo|emblem|crest|lettering|script|plate",
                      paint=r"carpaint", glass=r"_glass\.004|_glass\.002|fascia_glass|glass_int", tail=r"brakelight"),
    # P1-like hybrid hypercar (vecarz, CC-BY-4.0): modelled at ~45 % scale; "Details" = maker script / P1 badges
    "ravenna_hybrid": dict(src="p1", length=4.59, forward="-y", tyre_mat=r"^tyre$",
                           drop_mat=r"^details$", drop=r"badge|logo|emblem|plate",
                           paint=r"^carpaint$", glass=r"windows|clear_glass", tail=r"taillights"),
    # GT LM test car (kevin / sohyalebret, CC-BY-4.0): livery sheet chassi.10, badges on chassi.6; front is +Y
    "solano_concept": dict(src="gt_lm", length=4.64, forward="+y", tyre_mat=r"^wheel\.0$",
                           drop_mat=r"^chassi\.6$|^chassi\.9$", drop=r"badge|logo|emblem|plate",
                           paint=r"^bluepad$|^chassi\.10$", glass=r"^glass\.001$|windscreen", tail=r"rear_light|rear light",
                           black=r"^chassi\.0$"),
    # E30-era touring car (Martin Trafas / Bexxie, CC-BY-4.0). Roundels / script = EMBLEMS material, caliper maker
    # plates = Logo_Plane; the tyre-sidewall lettering (normal map) and the rim centre-cap roundel are scrubbed in
    # the working copy before conversion (see tools/cars/SKETCHFAB_CARS.md). (Replaced the Supra GT300 candidate:
    # its exterior is stacked textured layers that cannot be reduced below ~200k triangles without tearing.)
    "elektra_egt": dict(src="e30", length=4.35, forward="-y", tyre_mat=r"_tire$",
                        drop_mat=r"emblems|logo_plane", drop=r"plate_number|license",
                        paint=r"_paint$", glass=r"_windows$", tail=r"taillight"),
    # ---- second batch (all CC BY 4.0, Sketchfab; badges / lettering dropped, tyre and rear-panel textures scrubbed) ----
    "kaze_r4": dict(src="r34", length=4.60, forward="auto", tyre_mat=r"^material\.010$", drop_mat=r"^material\.032$",
                    drop=r"badge|logo|emblem|plate_number", paint=r"^material\.001$", glass=r"^material$", tail=r"^material\.009$"),
    "kaze_rotor": dict(src="rx7fd", length=4.30, forward="auto", tyre_mat=r"^material\.011$", drop_mat=r"^$",
                       drop=r"badge|logo|emblem", paint=r"^material\.007$", glass=r"^material\.008$", tail=r"^material\.019$"),
    "hikari_ns1": dict(src="nsx", length=4.41, forward="auto", tyre_mat=r"^material\.011$", drop_mat=r"^$",
                       drop=r"badge|logo|emblem", paint=r"^material\.003$", glass=r"^material\.007$", tail=r"^material\.016$"),
    "alba_integra": dict(src="delta", length=3.90, forward="auto", tyre_mat=r"^tire$",
                         drop_mat=r"^logo$|^number$|^shield_2$|^red_suns$|^legion$|^legend$|^alpha_mask$",
                         drop=r"badge|logo|emblem|number plate", paint=r"^paint$", glass=r"^glass$", tail=r"light_rear"),
    "ridgeway_sv8": dict(src="gt500", length=4.82, forward="auto", tyre_mat=r"^tire$", drop_mat=r"^lambert1$",
                         drop=r"badge|logo|emblem|license|plate_number", paint=r"^carpaint$", glass=r"tinted_glass", tail=r"rearlight"),
    "ravenna_quaranta": dict(src="f40", length=4.36, forward="auto", tyre_mat=r"^scene_-_root", drop_mat=r"^f40_logos$",
                             drop=r"badge|logo|emblem", paint=r"^material$", glass=r"f40_glass|f40_window", tail=r"brakelight"),
    "kaze_gt35": dict(src="r35", length=4.71, forward="auto", tyre_mat=r"^scene_-_root", drop_mat=r"r35_badges|r35_symbols",
                      drop=r"badge|logo|emblem|lettering|nismo", paint=r"^r35_paint", glass=r"^r35_glass", tail=r"taillight"),
    "arden_gt12": dict(src="db11", length=4.74, forward="auto", tyre_mat=r"^scene_-_root", drop_mat=r"amdb11_amr|amdb11_stickers|amdb11_badging",
                       drop=r"badge|logo|emblem", paint=r"^amdb11$", glass=r"amdb11_glass|amdb11_rearglass", tail=r"amdb11_taillight"),
}
CANON = {   # base colour, metallic, roughness, emission, alpha
    "paint": ((0.80, 0.80, 0.82), 0.5, 0.25, 0.0, 1.0),
    "glass": ((0.02, 0.025, 0.03), 0.0, 0.05, 0.0, 0.55),
    "tail": ((0.85, 0.02, 0.02), 0.0, 0.1, 1.5, 1.0),
    "carbon": ((0.05, 0.05, 0.055), 0.3, 0.3, 0.0, 1.0),
    "black": ((0.03, 0.03, 0.03), 0.0, 0.55, 0.0, 1.0),
    "amber": ((1.0, 0.45, 0.02), 0.0, 0.1, 1.0, 1.0),
}
BODY_BUDGET = 24000     # LOD0 body incl. interior silhouette (tris); the paint / glass shell gets 1.5x its share
WHEEL_BUDGET = 2600     # per wheel: tyre + rim + disc
SHELL_CAP = 10 ** 9     # paint + glass shell: never reduced (layered panels tear when decimated: mottled paint)
if os.environ.get("CAR_NO_REDUCE"):   # diagnostics: full detail, no decimation, no normal transfer
    BODY_BUDGET = SHELL_CAP = WHEEL_BUDGET = 10 ** 9
TEX_MAX = 1024

args = sys.argv[sys.argv.index("--") + 1:]
car_id, model_dir, out_dir = args[0], args[1], args[2]
cfg = CARS[car_id]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(model_dir, "scene.gltf"))
_canon = {}


def canon(cat):
    if cat not in _canon:
        col, met, rough, emit, alpha = CANON[cat]
        m = bpy.data.materials.new("GL_" + cat)
        m.use_nodes = True
        p = m.node_tree.nodes["Principled BSDF"]
        p.inputs["Base Color"].default_value = (*col, 1.0)
        p.inputs["Metallic"].default_value = met
        p.inputs["Roughness"].default_value = rough
        if emit > 0:
            p.inputs["Emission Color" if "Emission Color" in p.inputs else "Emission"].default_value = (*col, 1.0)
            p.inputs["Emission Strength"].default_value = emit
        if alpha < 1:
            p.inputs["Alpha"].default_value = alpha
            m.blend_method = "BLEND"
        _canon[cat] = m
    return _canon[cat]


def category(mat):
    if mat is None:
        return "black"
    n = orig_name.get(mat.name, mat.name).lower()
    for cat in ("paint", "glass", "tail", "carbon", "black"):
        rx = cfg.get(cat)
        if rx and rx != r"^$" and re.search(rx, n):
            return cat
    return "keep"


kept = {}
orig_name = {}   # exported name -> the author's material name (tyre detection, reports)


def keep(mat):
    if mat.name not in kept:
        src = mat.name
        mat.name = "KEEP_" + re.sub(r"[^A-Za-z0-9_]", "_", mat.name)[:40]
        kept[mat.name] = mat
        orig_name[mat.name] = src
    return mat


def tris(me):
    return sum(len(p.vertices) - 2 for p in me.polygons)


drop_rx = re.compile(cfg["drop"], re.I)
dmat_rx = re.compile(cfg["drop_mat"], re.I) if cfg["drop_mat"] != r"^$" else None
tyre_rx = re.compile(cfg["tyre_mat"], re.I)
dg = bpy.context.evaluated_depsgraph_get()
parts, dropped = [], []
for o in list(bpy.context.scene.objects):
    if o.type != "MESH":
        continue
    mats = [s.material for s in o.material_slots]
    if drop_rx.search(o.name) or (dmat_rx and mats and all(m is not None and dmat_rx.search(m.name) for m in mats)):
        dropped.append(o.name)
        continue
    ev = o.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    if len(me.polygons) == 0:
        continue
    me.transform(ev.matrix_world)
    is_tyre = any(m is not None and tyre_rx.search(orig_name.get(m.name, m.name)) for m in mats)
    src_mats = {i: (orig_name.get(m.name, m.name) if m is not None else "?") for i, m in enumerate(mats)}
    for i, s in enumerate(o.material_slots):
        if i < len(me.materials):
            m = s.material
            cat = category(m)
            if dmat_rx and m is not None and dmat_rx.search(m.name):
                cat = "black"   # a badge material on a mixed part: blank it
            me.materials[i] = canon(cat) if cat != "keep" else keep(m)
    if dmat_rx and any(m is not None and dmat_rx.search(m.name) for m in mats):
        # badge material on a mixed part: delete those faces (blanking them left the crest's outline in black)
        bad = {i for i, m in enumerate(mats) if m is not None and dmat_rx.search(m.name)}
        bm = bmesh.new(); bm.from_mesh(me)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index in bad], context="FACES")
        bm.to_mesh(me); bm.free()
        if len(me.polygons) == 0:
            continue
    caliper = any(m is not None and re.search(r"caliper", m.name, re.I) for m in mats)
    parts.append(dict(name=o.name, me=me, tyre=is_tyre, caliper=caliper, src_mats=src_mats))
print("DROPPED", dropped)

fwd_axis = cfg["forward"]
if fwd_axis == "auto":   # the brake lamps are at the back: front is the other end along the long axis
    tail_y = [f.center.y for p in parts for f in p["me"].polygons
              if f.material_index < len(p["me"].materials) and p["me"].materials[f.material_index] == canon("tail")]
    assert tail_y, "forward=auto needs tail lamp faces"
    fwd_axis = "-y" if sum(tail_y) / len(tail_y) > 0 else "+y"
    print("FORWARD auto ->", fwd_axis)
rot = {"-y": 0.0, "-x": math.pi / 2, "+y": math.pi, "+x": -math.pi / 2}[fwd_axis]
for p in parts:
    p["me"].transform(Matrix.Rotation(rot, 4, "Z"))


def bbox(mes):
    mn = Vector((1e18,) * 3); mx = Vector((-1e18,) * 3)
    for me in mes:
        for v in me.vertices:
            for a in range(3):
                mn[a] = min(mn[a], v.co[a]); mx[a] = max(mx[a], v.co[a])
    return mn, mx


# tyre faces: the tyre material faces only (a material may also cover rims / chrome trim on some models)
def tyre_faces(p):
    me = p["me"]
    idx = [i for i, m in enumerate(me.materials) if m is not None and tyre_rx.search(orig_name.get(m.name, m.name))]
    return [f.center.copy() for f in me.polygons if f.material_index in idx]


pts = [c for p in parts if p["tyre"] for c in tyre_faces(p)]
assert pts, "no tyre faces"
lo = Vector((min(c.x for c in pts), min(c.y for c in pts), min(c.z for c in pts)))
hi = Vector((max(c.x for c in pts), max(c.y for c in pts), max(c.z for c in pts)))
mn, mx = bbox([p["me"] for p in parts])
scale = cfg["length"] / (mx.y - mn.y)
cx, cy = (lo.x + hi.x) / 2, (lo.y + hi.y) / 2
T = Matrix.Scale(scale, 4) @ Matrix.Translation((-cx, -cy, -lo.z))
for p in parts:
    p["me"].transform(T)
pts = [T @ c for c in pts]
keep_parts = []
for p in parts:   # drop display stands, antennas, studio cards: anything outside a car-sized box
    a, b = bbox([p["me"]])
    thin_mast = b.z > 1.45 and (b - a).x < 0.15 and (b - a).y < 0.15   # radio antenna: would make the collision box 1.8 m tall
    if thin_mast or a.z > 1.6 or b.z > 1.9 or b.z < -0.3 or a.x > 1.4 or b.x < -1.4 or a.y > cfg["length"] * 0.62 or b.y < -cfg["length"] * 0.62:
        dropped.append(p["name"] + "(outside)")
        continue
    keep_parts.append(p)
parts = keep_parts
# Livery / decal overlays: shells floating a few millimetres above the base paint (transparent decal sheets in the
# original). Painted opaque they weave through the base coat (mottled paint), and they carry the real sponsor art,
# so they go. Detection: a paint-category material whose faces mostly lie within 15 mm of a larger paint surface.
groups = {}   # source material name -> list of (part, face indices)
for p in parts:
    me = p["me"]
    for f in me.polygons:
        m = me.materials[f.material_index] if f.material_index < len(me.materials) else None
        if m is not None and m.name.startswith("GL_paint"):
            src = p.get("src_mats", {}).get(f.material_index, "?")
            groups.setdefault(src, []).append((p, f.index))
def _bvh(entries):
    verts, polys = [], []
    for p, fi in entries:
        f = p["me"].polygons[fi]
        base = len(verts)
        verts.extend(p["me"].vertices[v].co.copy() for v in f.vertices)
        polys.append(list(range(base, base + len(f.vertices))))
    return BVHTree.FromPolygons(verts, polys)
overlay = set()
order = sorted(groups, key=lambda k: -len(groups[k]))
for i, small in enumerate(order):
    if i == 0:
        continue
    others = [e for k in order[:i] if k not in overlay for e in groups[k]]
    if not others:
        continue
    tree = _bvh(others)
    sample = groups[small][:: max(1, len(groups[small]) // 400)]
    near = sum(1 for p, fi in sample if (lambda hit: hit[0] is not None and hit[3] < 0.015)(tree.find_nearest(p["me"].polygons[fi].center)))
    if near >= 0.6 * len(sample):
        overlay.add(small)
print("OVERLAYS", sorted(overlay), {k: len(v) for k, v in groups.items()})
if overlay:
    for p in parts:
        idx = {i for i, src in p.get("src_mats", {}).items() if src in overlay}
        if not idx:
            continue
        bm = bmesh.new(); bm.from_mesh(p["me"])
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index in idx], context="FACES")
        bm.to_mesh(p["me"]); bm.free()
    parts = [p for p in parts if len(p["me"].polygons) > 0]
    dropped.extend("overlay:" + k for k in sorted(overlay))
# Shading reference: every kept part as authored (custom split normals intact), in final car space. BMesh steps
# below (merge, badge delete, wheel split, triangulate) and decimation all drop custom normals; the final meshes get
# them back from this reference by a nearest-face normal transfer.
_ref_objs = []
for p in parts:
    ro = bpy.data.objects.new("ref", p["me"].copy())
    bpy.context.scene.collection.objects.link(ro)
    if hasattr(ro.data, "use_auto_smooth"):
        ro.data.use_auto_smooth = True
    _ref_objs.append(ro)

quad = {}
for c in pts:
    if c.z > 0.9:   # stray non-tyre faces sharing the material (roof trim etc.)
        continue
    k = ("L" if c.x > 0 else "R", "F" if c.y < 0 else "B")
    q = quad.setdefault(k, [Vector((1e9,) * 3), Vector((-1e9,) * 3)])
    for a in range(3):
        q[0][a] = min(q[0][a], c[a]); q[1][a] = max(q[1][a], c[a])
assert len(quad) == 4, f"expected 4 tyres, found {sorted(quad)}"
wheels = {}
for k, (a, b) in quad.items():
    d = max(b.y - a.y, b.z - a.z)
    centre = (a + b) / 2
    centre.z = d / 2
    w = b.x - a.x
    wheels[k] = dict(centre=centre, radius=d / 2, width=w,
                     env=(Vector((min(a.x, b.x) - 0.45 * w - 0.02, centre.y - d * 0.56, centre.z - d * 0.56)),
                          Vector((max(a.x, b.x) + 0.45 * w + 0.02, centre.y + d * 0.56, centre.z + d * 0.56))))


def inside(a, b, env):
    return all(a[i] >= env[0][i] and b[i] <= env[1][i] for i in range(3))


def components(bm):
    parent = list(range(len(bm.verts)))
    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]; x = parent[x]
        return x
    for e in bm.edges:
        ra, rb = find(e.verts[0].index), find(e.verts[1].index)
        if ra != rb:
            parent[ra] = rb
    return [find(f.verts[0].index) for f in bm.faces]


buckets = {"body": []}
for k in wheels:
    buckets[k] = []
for p in parts:
    me = p["me"]
    a, b = bbox([me])
    near = [k for k, w in wheels.items() if all(a[i] <= w["env"][1][i] and b[i] >= w["env"][0][i] for i in range(3))]
    if not near or p["caliper"]:
        buckets["body"].append(me)
        continue
    bm = bmesh.new(); bm.from_mesh(me); bm.verts.ensure_lookup_table(); bm.faces.ensure_lookup_table()
    comp = components(bm)
    cb = {}
    for f, c in zip(bm.faces, comp):
        l2, h2 = cb.setdefault(c, [Vector((1e9,) * 3), Vector((-1e9,) * 3)])
        for v in f.verts:
            for i in range(3):
                l2[i] = min(l2[i], v.co[i]); h2[i] = max(h2[i], v.co[i])
    target = {}
    for c, (l2, h2) in cb.items():
        target[c] = "body"
        for k in near:
            if inside(l2, h2, wheels[k]["env"]):
                target[c] = k
                break
    if set(target.values()) == {"body"}:   # nothing to split off (fenders near a wheel): keep the mesh as authored
        bm.free()
        buckets["body"].append(me)
        continue
    for dest in set(target.values()):
        bm2 = bm.copy(); bm2.faces.ensure_lookup_table()
        bmesh.ops.delete(bm2, geom=[f for f, c in zip(bm2.faces, comp) if target[c] != dest], context="FACES")
        m2 = me.copy(); bm2.to_mesh(m2); bm2.free()
        buckets[dest].append(m2)
    bm.free()

for o in list(bpy.data.objects):
    if o not in _ref_objs:
        bpy.data.objects.remove(o)
scn = bpy.context.scene
bpy.ops.object.select_all(action="DESELECT")
for ro in _ref_objs:
    ro.select_set(True)
bpy.context.view_layer.objects.active = _ref_objs[0]
bpy.ops.object.join()
REF = bpy.context.view_layer.objects.active
REF.name = "ShadingReference"
REF.hide_render = True


def make(name, meshes, budget):
    paint = canon("paint")
    glass = canon("glass")
    # Painted and glazed shells are never decimated: these models stack paint, clear-coat and stripe layers a few
    # millimetres apart, and reducing them separately pushes one through the other (mottled paint). The budget is
    # taken from everything else (interior, engine bay, underbody, trim).
    shell = [me for me in meshes if name == "Body" and (paint in list(me.materials) or glass in list(me.materials))]
    if shell:
        # Anything lying against the outer skin is part of the hull too (inner panel skins, trim, carbon layers a
        # few millimetres under the paint): reduced, it pokes through the paint as dark blotches. Only parts that
        # are mostly away from the hull (seats, engine, underbody, suspension) are reduced.
        verts, polys = [], []
        for me in shell:
            base = len(verts)
            verts.extend(v.co.copy() for v in me.vertices)
            polys.extend([base + i for i in pl.vertices] for pl in me.polygons)
        hull = BVHTree.FromPolygons(verts, polys)
        for me in meshes:
            if me in shell or len(me.vertices) == 0:
                continue
            step = max(1, len(me.vertices) // 300)
            vs = [me.vertices[i] for i in range(0, len(me.vertices), step)]
            near = sum(1 for v in vs if (lambda h: h[0] is not None and h[3] < 0.012)(hull.find_nearest(v.co)))
            if near > 0.4 * len(vs):
                shell.append(me)
    shell_t = sum(tris(me) for me in shell)
    rest_t = sum(tris(me) for me in meshes) - shell_t
    ratio = min(1.0, max(budget - min(shell_t, SHELL_CAP), budget * 0.3) / max(rest_t, 1))
    shell_r = min(1.0, SHELL_CAP / max(shell_t, 1))   # very dense shells get a mild, uniform reduction
    print("BUDGET", name, "shell", shell_t, "rest", rest_t, "ratio", round(ratio, 3))
    objs = []
    for me in meshes:
        if hasattr(me, "use_auto_smooth"):
            me.use_auto_smooth = True   # Blender 4.0 keeps custom split normals only with auto smooth on
        o = bpy.data.objects.new(name, me); scn.collection.objects.link(o)
        # the painted shell keeps more of its budget (silhouette, reflections); hidden detail gives way
        r = shell_r if me in shell else ratio
        if r < 0.97 and tris(me) > 120:
            mod = o.modifiers.new("dec", "DECIMATE"); mod.ratio = r
            bpy.ops.object.select_all(action="DESELECT"); o.select_set(True)
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.convert(target="MESH")
        objs.append(o)
    if name == "Body":   # hull-only copies for the distance LODs (no interior, engine bay or underbody)
        hull_objs = []
        for ob in objs:
            if ob.data in shell or any(ob.data is me for me in shell):
                c = bpy.data.objects.new("Body_LOD1", ob.data.copy()); scn.collection.objects.link(c); hull_objs.append(c)
        LOD_PARTS.extend(hull_objs)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name; o.data.name = name
    # Triangulate with the modifier: it keeps the author's custom split normals (BMesh drops them and the paint
    # shades with dents and blotches on models that rely on them).
    if hasattr(o.data, "use_auto_smooth"):
        o.data.use_auto_smooth = True
    tri = o.modifiers.new("tri", "TRIANGULATE")
    tri.keep_custom_normals = True
    tri.quad_method = "BEAUTY"; tri.ngon_method = "BEAUTY"
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True); bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier="tri")
    if name == "Body":   # a lamp material shared by front indicators and rear lamps: only the rear half brakes red
        mats = list(o.data.materials)
        if canon("tail") in mats:
            ti = mats.index(canon("tail"))
            if canon("amber") not in mats:
                o.data.materials.append(canon("amber"))
            ai = list(o.data.materials).index(canon("amber"))
            for poly in o.data.polygons:
                if poly.material_index == ti and poly.center.y < 0:
                    poly.material_index = ai
    # shading back from the authored surface (see ShadingReference)
    if not os.environ.get("CAR_NORMAL_TRANSFER"):   # off: tested worse than the imported normals (see notes)
        return o
    if hasattr(o.data, "use_auto_smooth"):
        o.data.use_auto_smooth = True
        o.data.auto_smooth_angle = math.radians(180)
    dt = o.modifiers.new("nt", "DATA_TRANSFER")
    dt.object = REF
    dt.use_loop_data = True
    dt.data_types_loops = {"CUSTOM_NORMAL"}
    dt.loop_mapping = "NEAREST_POLYNOR"   # nearest corner on a face facing the same way: never the inner skin of a panel
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier="nt")
    return o


LOD_PARTS = []
names = {("L", "F"): "Wheel_FL", ("R", "F"): "Wheel_FR", ("L", "B"): "Wheel_RL", ("R", "B"): "Wheel_RR"}
body = make("Body", buckets["body"], BODY_BUDGET)
# Distance LODs. LOD1 (30-90 m): the hull only, at full detail (decimating layered panels tears the paint).
# LOD2 (90 m+): the hull reduced to 30 % - the tearing is invisible when the car is a few dozen pixels wide.
lods = {}
if LOD_PARTS:
    bpy.ops.object.select_all(action="DESELECT")
    for ob in LOD_PARTS:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = LOD_PARTS[0]
    bpy.ops.object.join()
    l1 = bpy.context.view_layer.objects.active
    l1.name = "Body_LOD1"; l1.data.name = "Body_LOD1"
    l2 = bpy.data.objects.new("Body_LOD2", l1.data.copy()); scn.collection.objects.link(l2)
    l2.data.name = "Body_LOD2"
    mod = l2.modifiers.new("dec", "DECIMATE"); mod.ratio = 0.3
    bpy.ops.object.select_all(action="DESELECT"); l2.select_set(True); bpy.context.view_layer.objects.active = l2
    bpy.ops.object.convert(target="MESH")
    lods = {"lod1_tris": tris(l1.data), "lod2_tris": tris(l2.data)}
spec = dict(id=car_id, source=cfg["src"], wheels={})
for k, w in wheels.items():
    o = make(names[k], buckets[k], WHEEL_BUDGET)
    c = w["centre"]
    o.data.transform(Matrix.Translation(-c)); o.location = c
    spec["wheels"][names[k]] = dict(centre=[round(c.x, 4), round(c.y, 4), round(c.z, 4)],
                                    radius=round(w["radius"], 4), width=round(w["width"], 4), tris=tris(o.data))
for img in bpy.data.images:   # mobile texture budget
    if img.size[0] > TEX_MAX or img.size[1] > TEX_MAX:
        f = TEX_MAX / max(img.size[0], img.size[1])
        img.scale(max(1, int(img.size[0] * f)), max(1, int(img.size[1] * f)))
bmn, bmx = bbox([body.data])
spec.update(lods, length=round(bmx.y - bmn.y, 3), width=round(bmx.x - bmn.x, 3), height=round(bmx.z - bmn.z, 3),
            body_min=[round(v, 3) for v in bmn], body_max=[round(v, 3) for v in bmx], body_tris=tris(body.data),
            materials=sorted(m.name for m in body.data.materials), scale=scale, dropped=dropped, kept=sorted(kept))
bpy.data.objects.remove(REF)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=f"{out_dir}/{car_id}.glb", export_format="GLB", use_selection=True, export_yup=True,
                          export_apply=True, export_texcoords=True, export_materials="EXPORT", export_image_format="AUTO",
                          )
with open(f"{out_dir}/{car_id}.json", "w") as fh:
    json.dump(spec, fh, indent=1)
print("CAR_SPEC", json.dumps({k: v for k, v in spec.items() if k not in ("dropped", "kept", "materials")}))
