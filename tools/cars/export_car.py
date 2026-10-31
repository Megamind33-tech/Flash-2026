"""Headless Blender: convert a BlendSwap car .blend into a GRIDLINE game car (.glb + spec .json).

  blender -b --disable-autoexec <car.blend> --python tools/cars/export_car.py -- <car_id> <out_dir>

Keeps the author's geometry (no remodelling). It: drops studio/ground/lights and every manufacturer
badge or lettering object, caps subdivision for mobile, maps materials onto GRIDLINE's canonical set
(GL_paint, GL_glass, ...), splits the four wheels by geometry, orients the car front -> glTF +Z,
scales to a realistic length, puts the tyre contact patch at y = 0 and writes wheel positions.
"""
import bpy, bmesh, sys, re, json, math
from mathutils import Vector, Matrix

CARS = {
    "arden_v8": dict(length=4.43, forward="-y", tyre=r"^003_reifen",
                      exclude=r"emblem|font_logo|nr_schild|^earth$|^light_plane$|^motor$",
                      mat={"break_wheel": "rim", "kupfer": "rim", "guss": "rim"},
                      # the author left the front wheels steered 30 degrees; straighten them like the rears
                      set_rot_z={"Rad_R8_front_R": math.pi / 2, "Rad_R8_front_L": -math.pi / 2},
                      recalc_normals=True,
                      # exterior parts were fitted at subdivision 2 and overlap: lower levels or decimation
                      # push trim through the paint, so keep them intact; interior stays unsubdivided
                      subsurf_cap=2, body_budget=150000,
                      level_by_name={r"mittelkonsole|steering|sitz|tacho|room_schale|armatur|amarture|bedienung|navi"
                                     r"|verkl|car_chair|fussmatten|lueftung|rueckspiegel|wischer|a-sauele": 0,
                                     r"scheinwerfer_fass\.001|mirrow": 1},
                      protect=r"car_body|car_plastic|chorme|scheinwerfer_fass(ung|\.000)|tailgate|_door$|side_wings|mirrow|heck_glass"
                              r"|front_glass|rueckleuchten|air_plates|back_scheiben|seitengitter|front_gitter|back_gitter"),   # trim parts were fitted at level 2; level 1 lets them poke through the paint   # 2011 file relied on double-sided shading; make normals consistent
    "arden_gt3": dict(length=4.58, forward="-y", tyre=r"^wheel ",
                       exclude=r"^text$|^audi\.001$|^brake$|^circle\.000$|^plane|^ground$|^turn table$",
                       mat={"rim": "rim", "white": "paint", "grey": "brake"},
                       # four-ring badges on the nose and tail (car space, metres)
                       erase=[((-0.12, -2.25, 0.51), (0.12, -2.16, 0.58)), ((-0.12, 1.94, 0.68), (0.12, 2.0, 0.76))]),
    "ravenna_hybrid": dict(length=4.70, forward="-x", tyre=r"^tire",
                           exclude=r"^circle\.005$", mat={"yellow lid": "black", "chrommat": "rim"},
                           width_scale=0.88),   # the author's body is ~2.4 m wide; bring it to a real ~2.1 m
    "solano_concept": dict(length=4.50, forward="-x", tyre=r"^tire1",
                           exclude=r"^circle\.015$|^plane", mat={"rim mat": "rim", "rims": "chrome", "carpainrt": "tail"}),
    # Spectral GT RS (CC0 1.0, JaronKBragg7337, procedurally generated, no brand). Front is +X in its Blender scene.
    "spectral_gt_rs": dict(length=4.45, forward="+x", tyre=r"_Tire(_Block_\d)?$",
                           exclude=r"^(Backdrop|Platform|Platform_Inlay|Studio_Floor)$", mat={}, wheel_scale=0.74),
    "elektra_egt": dict(length=4.85, forward="+y", tyre_mat=r"rubber tire",
                        exclude=r"^plane\.001$|show lights|^vert\.005$", mat={"porsche white.005": "rim", "pbr - metal": "rim"}),
}
# Canonical material set: base colour, metallic, roughness, emission strength, alpha.
CANON = {
    "paint":    ((0.80, 0.80, 0.82), 0.5, 0.25, 0.0, 1.0),
    "glass":    ((0.02, 0.025, 0.03), 0.0, 0.05, 0.0, 0.55),
    "chrome":   ((0.85, 0.85, 0.87), 1.0, 0.12, 0.0, 1.0),
    "rim":      ((0.55, 0.56, 0.58), 1.0, 0.25, 0.0, 1.0),
    "black":    ((0.03, 0.03, 0.03), 0.0, 0.55, 0.0, 1.0),
    "carbon":   ((0.05, 0.05, 0.055), 0.3, 0.3, 0.0, 1.0),
    "interior": ((0.08, 0.075, 0.07), 0.0, 0.7, 0.0, 1.0),
    "tyre":     ((0.025, 0.025, 0.025), 0.0, 0.9, 0.0, 1.0),
    "brake":    ((0.30, 0.30, 0.31), 0.9, 0.45, 0.0, 1.0),
    "head":     ((0.95, 0.95, 1.0), 0.0, 0.05, 2.0, 1.0),
    "tail":     ((0.85, 0.02, 0.02), 0.0, 0.1, 1.5, 1.0),
    "amber":    ((1.0, 0.45, 0.02), 0.0, 0.1, 1.0, 1.0),
}
RULES = [  # first match wins (lower-case material name)
    ("brake", r"^break|brake|disk|bremse"), ("tyre", r"tire|tyre|reifen"),
    ("amber", r"blink|orange|dir\.light"), ("tail", r"red"),
    ("black", r"hologram|display|gps|camera|navi|tacho|text"),
    ("head", r"headlight|lens|lamp|light_front|blue_glass|lazer|(^|[ _.])led([ _.]|$)|^lights?$|lightglass"),
    ("glass", r"glass|window|tint|transparent|windshield"),
    ("paint", r"lack|carbodymat|car ?paint|carpaint|porsche white|^white$"),
    ("rim", r"^rim|felge|aloi"),
    ("chrome", r"chrom|alu|silver|metal|exhaust|gold|guss|kupfer|bolt|lug|mirror"),
    ("carbon", r"carbon"), ("interior", r"leder|leather|stoff|felt|seat|chair|fussmatt"),
]
STUDIO_MATS = r"^(stage|groundmat|road|earth|light)$"
BODY_BUDGET, WHEEL_BUDGET, OBJ_CAP = 70000, 1500, 20000

args = sys.argv[sys.argv.index("--") + 1:]
car_id, out_dir = args[0], args[1]
cfg = CARS[car_id]
# Optional: scale each complete wheel assembly (tyre, tread blocks, rim, disc, calipers) about its hub, so the
# axle stays where the author put it and the tyre matches a real road-car size. Tread blocks have their own
# origins, so per-object scaling would scatter them.
if "wheel_scale" in cfg:
    _f = cfg["wheel_scale"]
    _wheel_parts = re.compile(r"^(Front|Rear)_(Left|Right)_(Tire|Rim|Brake_Disc|Brake_Hat|Brake_Caliper)")
    for _o in list(bpy.data.objects):
        _m = _wheel_parts.match(_o.name)
        if not _m or _o.type != "MESH" or _o.parent is not None:
            continue
        _hub_name = f"{_m.group(1)}_{_m.group(2)}_Tire"
        _hub = bpy.data.objects[_hub_name].matrix_world.translation if _hub_name in bpy.data.objects else _o.location
        _o.location = _hub + (_o.location - _hub) * _f
        _o.scale = _o.scale * _f
_canon_mats = {}


def canon(cat):
    if cat not in _canon_mats:
        col, met, rough, emit, alpha = CANON[cat]
        m = bpy.data.materials.new("GL_" + cat)
        m.use_nodes = True
        p = m.node_tree.nodes["Principled BSDF"]
        p.inputs["Base Color"].default_value = (*col, 1.0)
        p.inputs["Metallic"].default_value = met
        p.inputs["Roughness"].default_value = rough
        if emit > 0:
            p.inputs["Emission Color"].default_value = (*col, 1.0)
            p.inputs["Emission Strength"].default_value = emit
        if alpha < 1:
            p.inputs["Alpha"].default_value = alpha
            m.blend_method = "BLEND"
        _canon_mats[cat] = m
    return _canon_mats[cat]


def classify(mat):
    if mat is None:
        return "black"
    n = re.sub(r"\.\d+$", "", mat.name.lower()).strip()
    for k, v in cfg.get("mat", {}).items():
        if n == k or mat.name.lower() == k:
            return v
    for cat, rx in RULES:
        if re.search(rx, n):
            return cat
    return "black"


def tris(me):
    return sum(len(p.vertices) - 2 for p in me.polygons)


# ---------- 1. evaluate visible car meshes into world-space meshes with canonical materials ----------
vl_objs = set(bpy.context.view_layer.objects)
excl = re.compile(cfg["exclude"], re.I)


def _child_centre(ob):
    pts = [c.matrix_world @ Vector(b) for c in ob.children_recursive if c.type == "MESH" for b in c.bound_box]
    return sum(pts, Vector()) / len(pts)


for n, z in cfg.get("set_rot_z", {}).items():   # straighten, keeping the wheel centred in its arch
    ob = bpy.data.objects[n]
    before = _child_centre(ob)
    ob.rotation_euler.z = z
    bpy.context.view_layer.update()
    ob.matrix_world.translation += before - _child_centre(ob)
    bpy.context.view_layer.update()
for o in bpy.data.objects:   # cap subdivision before evaluation (mobile budget); skip work on dropped objects
    skip = excl.search(o.name) or o.hide_render
    for m in o.modifiers:
        if skip:
            m.show_viewport = False
            continue
        if m.type == "SUBSURF":
            cap = cfg.get("subsurf_cap", 1)
            for rx, lv in cfg.get("level_by_name", {}).items():
                if re.search(rx, o.name, re.I):
                    cap = lv
            m.levels = min(max(m.levels, m.render_levels), cap)
            m.show_viewport = True
dg = bpy.context.evaluated_depsgraph_get()
parts = []   # (name, mesh)
dropped = []
for o in bpy.context.scene.objects:
    if o.type != "MESH" or o not in vl_objs or o.hide_render:
        continue
    if any(c.hide_render for c in o.users_collection):
        continue
    if excl.search(o.name):
        dropped.append(o.name)
        continue
    mats = [s.material for s in o.material_slots]
    if mats and all(m is not None and re.search(STUDIO_MATS, m.name.lower()) for m in mats):
        dropped.append(o.name + "(studio mat)")
        continue
    ev = o.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=False, depsgraph=dg)
    if len(me.polygons) == 0:
        continue
    me.transform(ev.matrix_world)
    for i, s in enumerate(o.material_slots):
        if i < len(me.materials):
            me.materials[i] = s.material
    for i in range(len(me.materials)):
        me.materials[i] = canon(classify(me.materials[i]))
    if not me.materials:
        me.materials.append(canon("black"))
    if cfg.get("protect") and re.search(cfg["protect"], o.name, re.I):
        me["gl_protect"] = 1
    me["gl_src"] = o.name
    parts.append([o.name, me, [m.name for m in mats if m]])

# ---------- 2. orientation (front -> -Y in Blender == +Z in glTF) and scale ----------
rot = {"-y": 0.0, "-x": math.pi / 2, "+y": math.pi, "+x": -math.pi / 2}[cfg["forward"]]
R = Matrix.Rotation(rot, 4, "Z")
for p in parts:
    p[1].transform(R)


def bbox(me_list):
    mn = Vector((1e18,) * 3); mx = Vector((-1e18,) * 3)
    for me in me_list:
        for v in me.vertices:
            for a in range(3):
                mn[a] = min(mn[a], v.co[a]); mx[a] = max(mx[a], v.co[a])
    return mn, mx


# Drop anything far bigger than a car (studio floors, backdrops) before measuring.
mn, mx = bbox([p[1] for p in parts])
sizes = [(p, bbox([p[1]])) for p in parts]
tyre_rx = re.compile(cfg.get("tyre", r"^$"), re.I)
tmat_rx = re.compile(cfg.get("tyre_mat", r"^$"), re.I)
is_tyre = lambda p: bool(tyre_rx.search(p[0])) or any(tmat_rx.search(n) for n in p[2])
tyres = [p for p in parts if is_tyre(p)]
assert tyres, "no tyre objects found"
tmn, tmx = bbox([p[1] for p in tyres])
# body extent = parts overlapping the tyre footprint lengthwise
span = (tmx.y - tmn.y)
keep = []
for p, (a, b) in sizes:
    if (b - a).y > 1.8 * span or (b - a).x > 1.5 * (tmx.x - tmn.x) or (b - a).z > 3.0 * (tmx.z - tmn.z):
        dropped.append(p[0] + "(oversize)")
        bpy.data.meshes.remove(p[1])
        continue
    keep.append(p)
parts = keep
mn, mx = bbox([p[1] for p in parts])
scale = cfg["length"] / (mx.y - mn.y)
cx, cy = (tmn.x + tmx.x) / 2, (tmn.y + tmx.y) / 2
T = Matrix.Scale(scale, 4) @ Matrix.Translation((-cx, -cy, -tmn.z))
T = Matrix.Diagonal((cfg.get("width_scale", 1.0), 1.0, 1.0, 1.0)) @ T
for p in parts:
    p[1].transform(T)
keep = []
for p in parts:   # drop studio cards/lights floating outside a car-sized box
    a, b = bbox([p[1]])
    if a.z > 1.7 or b.z < -0.3 or a.x > 1.4 or b.x < -1.4 or a.y > 3.2 or b.y < -3.2:
        dropped.append(p[0] + "(outside)")
        continue
    keep.append(p)
parts = keep

# ---------- 3. wheels: tyre faces clustered into quadrants; parts contained in a tyre envelope spin with it ----------
def face_centres(me):
    return [(f.index, f.center.copy()) for f in me.polygons]

quad = {}   # key -> [mn, mx]
for p in tyres:
    for _, c in face_centres(p[1]):
        k = ("L" if c.x > 0 else "R", "F" if c.y < 0 else "B")
        q = quad.setdefault(k, [Vector((1e9,) * 3), Vector((-1e9,) * 3)])
        for a in range(3):
            q[0][a] = min(q[0][a], c[a]); q[1][a] = max(q[1][a], c[a])
assert len(quad) == 4, f"expected 4 tyres, found {sorted(quad)}"
wheels = {}
for k, (a, b) in quad.items():
    w = b.x - a.x
    d = max(b.y - a.y, b.z - a.z)
    centre = (a + b) / 2
    centre.z = d / 2   # contact patch at z = 0 (tyre bottom was translated to 0)
    wheels[k] = dict(centre=centre, radius=d / 2, width=w,
                     env=(Vector((a.x - 0.35 * w, centre.y - d * 0.54, centre.z - d * 0.54)),
                          Vector((b.x + 0.35 * w, centre.y + d * 0.54, centre.z + d * 0.54))))


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


def erase_badges(me, boxes, report):
    """Delete loose parts lying wholly inside an erase box (car space, metres); report small centred
    parts at the nose/tail so new badges can be spotted."""
    bm = bmesh.new(); bm.from_mesh(me); bm.verts.ensure_lookup_table(); bm.faces.ensure_lookup_table()
    comp = components(bm)
    cb = {}
    for f, c in zip(bm.faces, comp):
        lo, hi = cb.setdefault(c, [Vector((1e9,) * 3), Vector((-1e9,) * 3)])
        for v in f.verts:
            for i in range(3):
                lo[i] = min(lo[i], v.co[i]); hi[i] = max(hi[i], v.co[i])
    kill_c = set()
    for c, (lo, hi) in cb.items():
        if any(inside(lo, hi, (Vector(b[0]), Vector(b[1]))) for b in boxes):
            kill_c.add(c)
        elif report and abs((lo.x + hi.x) / 2) < 0.4 and max(hi - lo) < 0.3 and abs((lo.y + hi.y) / 2) > 1.7:
            print("BADGE?", report, [round(v, 3) for v in lo], [round(v, 3) for v in hi])
    if kill_c:
        bmesh.ops.delete(bm, geom=[f for f, c in zip(bm.faces, comp) if c in kill_c], context="FACES")
        bm.to_mesh(me)
    bm.free()
    return len(kill_c)


erased = 0
for name, me, _ in parts:
    erased += erase_badges(me, cfg.get("erase", []), name if "--scan" in sys.argv else "")

buckets = {"body": []}
for k in wheels:
    buckets[k] = []
for name, me, _ in parts:
    a, b = bbox([me])
    near = [k for k, w in wheels.items() if all(a[i] <= w["env"][1][i] and b[i] >= w["env"][0][i] for i in range(3))]
    if not near:
        buckets["body"].append(me); continue
    bm = bmesh.new(); bm.from_mesh(me); bm.verts.ensure_lookup_table(); bm.faces.ensure_lookup_table()
    comp = components(bm)
    cb = {}
    for f, c in zip(bm.faces, comp):
        lo, hi = cb.setdefault(c, [Vector((1e9,) * 3), Vector((-1e9,) * 3)])
        for v in f.verts:
            for i in range(3):
                lo[i] = min(lo[i], v.co[i]); hi[i] = max(hi[i], v.co[i])
    target = {}
    for c, (lo, hi) in cb.items():
        target[c] = "body"
        for k in near:
            if inside(lo, hi, wheels[k]["env"]):
                target[c] = k; break
    for dest in set(target.values()):
        bm2 = bm.copy(); bm2.faces.ensure_lookup_table()
        kill = [f for f, c in zip(bm2.faces, comp) if target[c] != dest]
        bmesh.ops.delete(bm2, geom=kill, context="FACES")
        m2 = me.copy(); bm2.to_mesh(m2); bm2.free()
        buckets[dest].append(m2)
    bm.free()


# ---------- 4. join, decimate, export ----------
for c in list(bpy.data.collections):
    bpy.data.collections.remove(c)
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
scn = bpy.context.scene


def make(name, meshes, budget):
    # Decimate per part (big parts first) so one pathological mesh can't stall a whole-car collapse.
    # Spend the budget on the painted shell first: detail parts (grilles, interior, tread) are decimated harder.
    paint = canon("paint")
    shell = [me for me in meshes if me.get("gl_protect") or (paint in list(me.materials) and tris(me) <= 2 * OBJ_CAP)]
    shell_t = sum(tris(me) for me in shell)
    rest_t = sum(tris(me) for me in meshes) - shell_t
    if "--scan" in sys.argv:
        print("SHELL", name, sorted(((tris(me), me.get("gl_src")) for me in shell), reverse=True)[:12])
    rest_ratio = min(1.0, max(budget - shell_t, 0.25 * budget) / max(rest_t, 1))
    objs = []
    for me in meshes:
        # Re-weld edge-split shells first: Decimate's collapse explodes on thousands of loose faces.
        bm = bmesh.new(); bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
        bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-5)
        if cfg.get("recalc_normals"):
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        loose = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
        bm.to_mesh(me); bm.free()
        o = bpy.data.objects.new(name, me); scn.collection.objects.link(o)
        r = 1.0 if me in shell else min(rest_ratio, OBJ_CAP / max(tris(me), 1))
        if r < 0.98 and tris(me) > 400:
            mod = o.modifiers.new("dec", "DECIMATE"); mod.ratio = r
            bpy.ops.object.select_all(action="DESELECT"); o.select_set(True)
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.convert(target="MESH")
        objs.append(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name; o.data.name = name
    if o.data.has_custom_normals:   # stale custom split normals from old files stall the glTF exporter
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    o.vertex_groups.clear()
    # Triangulate: decimation leaves huge n-gons that make split-normal calculation explode.
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.triangulate(bm, faces=bm.faces, quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(o.data); bm.free()
    while o.data.uv_layers:
        o.data.uv_layers.remove(o.data.uv_layers[0])
    bpy.ops.object.shade_smooth()
    if hasattr(o.data, "use_auto_smooth"):          # Blender < 4.1
        o.data.use_auto_smooth = True
        o.data.auto_smooth_angle = math.radians(40)
    else:                                           # Blender >= 4.1 (auto smooth removed in 5.x)
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
    return o


names = {("L", "F"): "Wheel_FL", ("R", "F"): "Wheel_FR", ("L", "B"): "Wheel_RL", ("R", "B"): "Wheel_RR"}
body = make("Body", buckets["body"], cfg.get("body_budget", BODY_BUDGET))
spec = dict(id=car_id, wheels={})
for k, w in wheels.items():
    o = make(names[k], buckets[k], WHEEL_BUDGET)
    c = w["centre"]
    o.data.transform(Matrix.Translation(-c)); o.location = c
    spec["wheels"][names[k]] = dict(centre=[round(c.x, 4), round(c.y, 4), round(c.z, 4)],
                                    radius=round(w["radius"], 4), width=round(w["width"], 4), tris=tris(o.data))
bmn, bmx = bbox([body.data])
spec.update(length=round(bmx.y - bmn.y, 3), width=round(bmx.x - bmn.x, 3), height=round(bmx.z - bmn.z, 3),
            body_min=[round(v, 3) for v in bmn], body_max=[round(v, 3) for v in bmx], body_tris=tris(body.data),
            materials=sorted(m.name for m in body.data.materials), scale=scale, dropped=dropped, badges_erased=erased)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=f"{out_dir}/{car_id}.glb", export_format="GLB", use_selection=True,
                          export_yup=True, export_apply=True, export_texcoords=False, export_materials="EXPORT")
with open(f"{out_dir}/{car_id}.json", "w") as fh:
    json.dump(spec, fh, indent=1)
print("CAR_SPEC", json.dumps({k: v for k, v in spec.items() if k != "dropped"}))
print("DROPPED", dropped)
