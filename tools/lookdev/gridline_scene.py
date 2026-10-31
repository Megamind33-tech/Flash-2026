"""
GRIDLINE look-dev scene for Blender (headless). Rebuilds the game's assets from the repository so we can see them
without a Unity licence:
  * RVP Muscle Car from RVP's public-domain .blend source, materials converted from the Unity .mat files
    (Standard shader -> Principled BSDF), GRIDLINE liveries on the body.
  * Ashford Airfield Circuit from the same control points and rules as Assets/Gridline/Editor/TrackBuilder.cs
    (2 m centreline, 12 m tarmac, kerbs r<80 m, gravel r<60 m, armco at 24 m, pit wall, grid boxes, gantry, grandstand)
    with the ambientCG CC0 surfaces.
Usage: blender -b -P gridline_scene.py -- <repo> <rvp_blend> <out_dir> [shot ...]
"""
import bpy, bmesh, math, os, re, sys, glob
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
REPO, RVP_BLEND, OUT = argv[0], argv[1], argv[2]
SHOTS = argv[3:] or ["hero", "grid", "chase", "corner", "aerial", "liveries"]
RVP = os.path.join(REPO, "Assets/ThirdParty/RVP")
SURF = os.path.join(REPO, "Assets/Gridline/Art/Textures/Surfaces")
LIV = os.path.join(REPO, "Assets/Gridline/Art/Textures/Liveries")
os.makedirs(OUT, exist_ok=True)

# ---------------------------------------------------------------- circuit (port of CircuitLayout + TrackPath)
CTRL = [(0,0),(120,0),(240,0),(330,0),(385,-12),(405,-55),(385,-98),(340,-110),(280,-104),(232,-128),(214,-180),(236,-240),
        (292,-276),(362,-292),(432,-288),(482,-318),(494,-378),(456,-420),(385,-432),(250,-432),(120,-432),(0,-428),(-48,-412),
        (-66,-382),(-96,-368),(-136,-358),(-190,-330),(-222,-272),(-214,-205),(-178,-155),(-196,-95),(-184,-36),(-132,-4),(-60,0)]
HW = 6.0

def centreline(spacing=2.0):
    n = len(CTRL); dense = []
    for i in range(n):
        p0, p1, p2, p3 = (Vector(CTRL[(i + k) % n]) for k in (-1, 0, 1, 2))
        for k in range(48):
            t = k / 48; t2, t3 = t * t, t * t * t
            dense.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    total = sum((dense[i] - dense[(i + 1) % len(dense)]).length for i in range(len(dense)))
    count = round(total / spacing); step = total / count
    out = []; seg = 0; seg_start = 0.0; seg_len = (dense[1] - dense[0]).length
    for k in range(count):
        d = k * step
        while d > seg_start + seg_len and seg < len(dense) - 1:
            seg_start += seg_len; seg += 1; seg_len = (dense[(seg + 1) % len(dense)] - dense[seg]).length
        t = (d - seg_start) / seg_len if seg_len > 1e-5 else 0
        out.append(dense[seg].lerp(dense[(seg + 1) % len(dense)], min(max(t, 0), 1)))
    return out

# Unity (x, z) maps to Blender (x, y): swapping Y/Z converts Unity's left-handed frame without mirroring the circuit.
PTS = centreline()
N = len(PTS)
CUM = [0.0]
for i in range(N): CUM.append(CUM[-1] + (PTS[(i + 1) % N] - PTS[i]).length)
L = CUM[-1]

def curvature(i, span=5):
    a, b, c = PTS[(i - span) % N], PTS[i % N], PTS[(i + span) % N]
    ab, bc, ac = b - a, c - b, c - a
    cross = ab.x * bc.y - ab.y * bc.x
    den = ab.length * bc.length * ac.length
    return 0 if den < 1e-6 else -2 * cross / den   # >0 = right-hand bend, as in TrackPath

def right_vec(i):
    d = PTS[(i + 1) % N] - PTS[(i - 1) % N]; d.normalize()
    return Vector((d.y, -d.x))

def at(d):
    d %= L
    lo = max(0, min(N - 1, int(d / (L / N))))
    while lo > 0 and CUM[lo] > d: lo -= 1
    while lo < N - 1 and CUM[lo + 1] <= d: lo += 1
    t = (d - CUM[lo]) / (CUM[lo + 1] - CUM[lo])
    p = PTS[lo].lerp(PTS[(lo + 1) % N], t)
    tan = (PTS[(lo + 1) % N] - PTS[lo]).normalized()
    return p, tan, Vector((tan.y, -tan.x))

# ---------------------------------------------------------------- materials
def img(path, colour=True):
    im = bpy.data.images.load(path, check_existing=True)
    if not colour: im.colorspace_settings.name = "Non-Color"
    return im

def principled(name):
    m = bpy.data.materials.new(name); m.use_nodes = True
    return m, m.node_tree.nodes["Principled BSDF"], m.node_tree

def surface(name, tile, smooth_scale, tint=(1, 1, 1)):
    m, bsdf, nt = principled("Surface_" + name)
    uv = nt.nodes.new("ShaderNodeTexCoord"); mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1 / tile, 1 / tile, 1)
    nt.links.new(uv.outputs["UV"], mp.inputs["Vector"])
    alb = nt.nodes.new("ShaderNodeTexImage"); alb.image = img(f"{SURF}/{name}_albedo.jpg")
    nt.links.new(mp.outputs["Vector"], alb.inputs["Vector"])
    mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"; mix.inputs["Factor"].default_value = 1
    nt.links.new(alb.outputs["Color"], mix.inputs[6]); mix.inputs[7].default_value = (*tint, 1)
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    nrm = nt.nodes.new("ShaderNodeTexImage"); nrm.image = img(f"{SURF}/{name}_normal.jpg", False)
    nt.links.new(mp.outputs["Vector"], nrm.inputs["Vector"])
    nm = nt.nodes.new("ShaderNodeNormalMap"); nt.links.new(nrm.outputs["Color"], nm.inputs["Color"]); nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    ms = nt.nodes.new("ShaderNodeTexImage"); ms.image = img(f"{SURF}/{name}_ms.png", False)
    nt.links.new(mp.outputs["Vector"], ms.inputs["Vector"])
    # URP: smoothness = map.a * _Smoothness ; roughness = 1 - smoothness
    mul = nt.nodes.new("ShaderNodeMath"); mul.operation = "MULTIPLY"; mul.inputs[1].default_value = smooth_scale
    nt.links.new(ms.outputs["Alpha"], mul.inputs[0])
    inv = nt.nodes.new("ShaderNodeMath"); inv.operation = "SUBTRACT"; inv.inputs[0].default_value = 1
    nt.links.new(mul.outputs[0], inv.inputs[1]); nt.links.new(inv.outputs[0], bsdf.inputs["Roughness"])
    return m

def solid(name, rgb, metal=0.0, rough=0.5, emit=None, alpha=1.0):
    m, bsdf, nt = principled(name)
    bsdf.inputs["Base Color"].default_value = (*rgb, 1); bsdf.inputs["Metallic"].default_value = metal; bsdf.inputs["Roughness"].default_value = rough
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1); bsdf.inputs["Emission Strength"].default_value = 4
    if alpha < 1:
        bsdf.inputs["Alpha"].default_value = alpha; m.blend_method = "BLEND"
    return m

def kerb_material():
    m, bsdf, nt = principled("Kerb")
    uv = nt.nodes.new("ShaderNodeTexCoord"); sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(uv.outputs["UV"], sep.inputs["Vector"])
    div = nt.nodes.new("ShaderNodeMath"); div.operation = "DIVIDE"; div.inputs[1].default_value = 3.0
    nt.links.new(sep.outputs["Y"], div.inputs[0])
    fr = nt.nodes.new("ShaderNodeMath"); fr.operation = "FRACT"; nt.links.new(div.outputs[0], fr.inputs[0])
    gt = nt.nodes.new("ShaderNodeMath"); gt.operation = "GREATER_THAN"; gt.inputs[1].default_value = 0.5; nt.links.new(fr.outputs[0], gt.inputs[0])
    mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"
    mix.inputs[6].default_value = (0.52, 0.03, 0.03, 1); mix.inputs[7].default_value = (0.83, 0.83, 0.8, 1)
    nt.links.new(gt.outputs[0], mix.inputs["Factor"]); nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.6
    return m

# Unity Standard material -> Principled BSDF, reading the actual .mat/.meta files.
GUID = {}
for meta in glob.glob(RVP + "/Textures/**/*.meta", recursive=True):
    g = re.search(r"guid: (\w+)", open(meta).read()); GUID[g.group(1)] = meta[:-5]

def unity_material(path, base_override=None):
    t = open(path).read()
    # Supports both the Unity 5 ("- first: name: X / second:") and current ("- X:") material serialisations.
    tex = {k: GUID.get(g) for k, g in re.findall(r"(?:- |name: )(_\w+):?\n\s+(?:second:\n\s+)?m_Texture: \{fileID: \d+, guid: (\w+)", t)}
    fl = {k: float(v) for k, v in re.findall(r"(?:- |name: )(_\w+):?\n?\s*(?:second:)? ([-\d.]+)\n", t)}
    col = re.search(r"_Color:?\n?\s*(?:second:)? ?\{r: ([\d.]+), g: ([\d.]+), b: ([\d.]+), a: ([\d.]+)\}", t)
    rgba = [float(x) for x in col.groups()] if col else [1, 1, 1, 1]
    name = os.path.basename(path)[:-4]
    m, bsdf, nt = principled("RVP_" + name)
    base = base_override or tex.get("_MainTex")
    if base and not os.path.exists(base): print("MISSING TEXTURE", base, flush=True)
    if base and os.path.exists(base):
        n = nt.nodes.new("ShaderNodeTexImage"); n.image = img(base)
        tint = nt.nodes.new("ShaderNodeMix"); tint.data_type = "RGBA"; tint.blend_type = "MULTIPLY"; tint.inputs["Factor"].default_value = 1
        nt.links.new(n.outputs["Color"], tint.inputs[6]); tint.inputs[7].default_value = (*rgba[:3], 1)
        colour_out = tint.outputs[2]
    else:
        rgb = nt.nodes.new("ShaderNodeRGB"); rgb.outputs[0].default_value = (*rgba[:3], 1)
        colour_out = rgb.outputs[0]
    ao = tex.get("_OcclusionMap")
    if ao and os.path.exists(ao):
        n = nt.nodes.new("ShaderNodeTexImage"); n.image = img(ao, False)
        mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"; mix.inputs["Factor"].default_value = 1
        nt.links.new(colour_out, mix.inputs[6]); nt.links.new(n.outputs["Color"], mix.inputs[7]); colour_out = mix.outputs[2]
    nt.links.new(colour_out, bsdf.inputs["Base Color"])
    mg = tex.get("_MetallicGlossMap")
    if mg and os.path.exists(mg):
        n = nt.nodes.new("ShaderNodeTexImage"); n.image = img(mg, False)
        sep = nt.nodes.new("ShaderNodeSeparateColor"); nt.links.new(n.outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs["Red"], bsdf.inputs["Metallic"])
        mul = nt.nodes.new("ShaderNodeMath"); mul.operation = "MULTIPLY"; mul.inputs[1].default_value = fl.get("_GlossMapScale", 1)
        nt.links.new(n.outputs["Alpha"], mul.inputs[0])
        inv = nt.nodes.new("ShaderNodeMath"); inv.operation = "SUBTRACT"; inv.inputs[0].default_value = 1
        nt.links.new(mul.outputs[0], inv.inputs[1]); nt.links.new(inv.outputs[0], bsdf.inputs["Roughness"])
    else:
        bsdf.inputs["Metallic"].default_value = fl.get("_Metallic", 0); bsdf.inputs["Roughness"].default_value = 1 - fl.get("_Glossiness", 0.5)
    bump = tex.get("_BumpMap")
    if bump and os.path.exists(bump):
        n = nt.nodes.new("ShaderNodeTexImage"); n.image = img(bump, False)
        nm = nt.nodes.new("ShaderNodeNormalMap"); nt.links.new(n.outputs["Color"], nm.inputs["Color"]); nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    em = tex.get("_EmissionMap")
    if em and os.path.exists(em) and "_EMISSION" in t:
        n = nt.nodes.new("ShaderNodeTexImage"); n.image = img(em)
        nt.links.new(n.outputs["Color"], bsdf.inputs["Emission Color"]); bsdf.inputs["Emission Strength"].default_value = 1
    if fl.get("_Mode", 0) >= 2:   # fade / transparent
        bsdf.inputs["Alpha"].default_value = rgba[3]; m.blend_method = "BLEND"
        if bsdf.inputs.get("Transmission Weight") is not None: pass
    return m

# ---------------------------------------------------------------- car (from RVP source .blend)
GAME_PARTS = ["chassis", "bumper_front", "bumper_rear", "door_L", "door_R", "doorwindow_L", "doorwindow_R", "engine", "fender_L", "fender_R",
              "grille", "headlights_L", "headlights_R", "hood", "trunk", "under_front", "under_rear", "window_front", "window_rear",
              "smallwindow_L", "smallwindow_R", "brakelight_L", "brakelight_R", "blinker_front_L", "blinker_front_R", "blinker_rear_L",
              "blinker_rear_R", "reverselight_L", "reverselight_R", "transmission"]
PART_MAT = {"doorwindow": "Windows", "smallwindow": "Windows", "window_": "Windows", "headlights": "Headlights", "brakelight": "Brakelight",
            "blinker_front": "Blinker Front", "blinker_rear": "Blinker Rear", "reverselight": "Reverselight"}
CAR_ORIGIN = Vector((-5.02, -0.1, -0.96))   # body centre over the ground, Blender source units
SOURCE_TO_GAME = 0.5                          # Unity imports the source at half scale (verified against the prefab bumpers)
# Wheel centres relative to the chassis pivot, from the prefab suspension transforms (Unity units), mapped to Blender.
WHEELS = [(-0.634, 1.186), (0.634, 1.186), (-0.634, -1.113), (0.634, -1.113)]
WHEEL_Z = (-0.37 - CAR_ORIGIN.z) * SOURCE_TO_GAME

def load_car_source():
    with bpy.data.libraries.load(RVP_BLEND) as (src, dst):
        dst.objects = [n for n in src.objects if n in GAME_PARTS + ["tire", "rim"]]
    return {o.name: o for o in dst.objects if o is not None}

SRC = None
MATS = {}
def car_material(kind, livery=None):
    key = (kind, livery)
    if key not in MATS:
        if kind == "Body":
            MATS[key] = unity_material(f"{RVP}/Materials/Vehicles/Muscle Car/Body.mat", f"{LIV}/body_{livery}.png")
            MATS[key].name = "Body_" + livery
        elif kind == "Windows":
            MATS[key] = solid("Glass", (0.02, 0.025, 0.03), 0.0, 0.03, alpha=0.82)
        else:
            MATS[key] = unity_material(f"{RVP}/Materials/Vehicles/Muscle Car/{kind}.mat")
    return MATS[key]

def make_car(name, livery, location, heading, coll):
    """heading: unit 2D vector the car faces."""
    global SRC
    if SRC is None: SRC = load_car_source()
    root = bpy.data.objects.new(name, None); coll.objects.link(root)
    S = SOURCE_TO_GAME
    for part in GAME_PARTS:
        src = SRC.get(part)
        if src is None: continue
        o = src.copy(); coll.objects.link(o)
        o.parent = None
        o.matrix_world = Matrix.Translation(-CAR_ORIGIN * S) @ Matrix.Scale(S, 4) @ src.matrix_world
        o.parent = root
        kind = next((v for k, v in PART_MAT.items() if part.startswith(k)), "Body")
        o.data = src.data.copy() if kind == "Body" else src.data
        o.data.materials.clear(); o.data.materials.append(car_material(kind, livery))
        for poly in o.data.polygons: poly.use_smooth = True
    tire, rim = SRC["tire"], SRC["rim"]
    for wx, wz in WHEELS:
        centre = Vector((wx, wz, 0)) * 1.0
        for src, kind in ((tire, "Tire Simple"), (rim, "Rim")):
            o = src.copy(); o.data = src.data; coll.objects.link(o)
            local = Matrix.Translation(-src.matrix_world.translation) @ src.matrix_world   # rotation/scale only
            flip = Matrix.Rotation(math.pi, 4, "Z") if wx > 0 else Matrix.Identity(4)
            o.matrix_world = Matrix.Translation((wx, wz, WHEEL_Z)) @ flip @ Matrix.Scale(S, 4) @ local
            o.parent = root
            if not o.data.materials or o.data.materials[0] is None or True:
                o.data.materials.clear(); o.data.materials.append(car_material(kind))
    root.location = (location[0], location[1], 0.03)
    root.rotation_euler = (0, 0, math.atan2(-heading[0], heading[1]))
    return root

# ---------------------------------------------------------------- track meshes
def strip(name, a_fn, b_fn, za, zb, include, mat, coll):
    bm = bmesh.new(); uv = bm.loops.layers.uv.new()
    verts = []
    for i in range(N + 1):
        k = i % N; r = right_vec(k); p = PTS[k]; a, b = a_fn(k), b_fn(k)
        verts.append((bm.verts.new((p.x + r.x * a, p.y + r.y * a, za)), bm.verts.new((p.x + r.x * b, p.y + r.y * b, zb)), a, b, CUM[i] if i < N else L))
    for i in range(N):
        if include and not include(i): continue
        A0, B0, a0, b0, v0 = verts[i]; A1, B1, a1, b1, v1 = verts[i + 1]
        f = bm.faces.new((A0, B0, B1, A1))
        for loop, (u, v) in zip(f.loops, ((a0, v0), (b0, v0), (b1, v1), (a1, v1))): loop[uv].uv = (u, v)
    bm.normal_update()
    for f in bm.faces:
        if f.normal.z < 0: f.normal_flip()
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); o.data.materials.append(mat); coll.objects.link(o)
    return o

def wall(name, off_fn, z0, z1, include, mat, coll):
    bm = bmesh.new(); uv = bm.loops.layers.uv.new(); col = []
    for i in range(N + 1):
        k = i % N; r = right_vec(k); p = PTS[k]; o = off_fn(k)
        x, y = p.x + r.x * o, p.y + r.y * o
        col.append((bm.verts.new((x, y, z0)), bm.verts.new((x, y, z1)), CUM[i] if i < N else L))
    for i in range(N):
        if include and not include(i): continue
        a0, a1, v0 = col[i]; b0, b1, v1 = col[i + 1]
        f = bm.faces.new((a0, b0, b1, a1))
        for loop, (u, v) in zip(f.loops, ((v0, z0), (v1, z0), (v1, z1), (v0, z1))): loop[uv].uv = (u, v)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); o.data.materials.append(mat); coll.objects.link(o)
    sol = o.modifiers.new("thick", "SOLIDIFY"); sol.thickness = 0.12
    return o

def box(name, centre, size, yaw, mat, coll):
    bpy.ops.mesh.primitive_cube_add(size=1, location=centre, rotation=(0, 0, yaw))
    o = bpy.context.active_object; o.name = name; o.scale = size
    for c in o.users_collection: c.objects.unlink(o)
    coll.objects.link(o); o.data.materials.append(mat)
    return o

def smooth_loop(vals, radius):
    n = len(vals)
    return [sum(vals[(i + k) % n] for k in range(-radius, radius + 1)) / (2 * radius + 1) for i in range(n)]

def build_track(coll):
    asphalt = surface("asphalt", 8, 0.55, (0.82, 0.82, 0.84))
    grass = surface("grass", 5, 0.35, (0.78, 0.84, 0.74))
    gravel = surface("gravel", 4, 0.4, (0.93, 0.9, 0.84))
    concrete = surface("concrete", 4, 0.5, (0.86, 0.86, 0.86))
    paint = solid("Paint", (0.85, 0.85, 0.82), 0, 0.55)
    steel = solid("Armco", (0.62, 0.64, 0.66), 0.85, 0.42)
    dark = solid("SteelDark", (0.05, 0.055, 0.06), 0.6, 0.5)
    seats = solid("Seats", (0.04, 0.10, 0.25), 0, 0.5)
    lamp = solid("Lamp", (0.2, 0.01, 0.01), 0, 0.3, emit=(0.9, 0.02, 0.01))
    kerb = kerb_material()

    k5 = [curvature(i) for i in range(N)]
    strip("Road", lambda i: -HW, lambda i: HW, 0.02, 0.02, None, asphalt, coll)
    strip("EdgeL", lambda i: -HW + 0.15, lambda i: -HW + 0.4, 0.03, 0.03, None, paint, coll)
    strip("EdgeR", lambda i: HW - 0.4, lambda i: HW - 0.15, 0.03, 0.03, None, paint, coll)
    corner = lambda i: abs(k5[i]) > 1 / 80 or abs(k5[(i + 1) % N]) > 1 / 80
    strip("KerbR", lambda i: HW, lambda i: HW + 1.2, 0.03, 0.09, corner, kerb, coll)
    strip("KerbL", lambda i: -HW - 1.2, lambda i: -HW, 0.09, 0.03, corner, kerb, coll)
    strip("GravelR", lambda i: HW + 3, lambda i: HW + 15, 0.0, 0.0, lambda i: k5[i] < -1 / 60, gravel, coll)
    strip("GravelL", lambda i: -HW - 15, lambda i: -HW - 3, 0.0, 0.0, lambda i: k5[i] > 1 / 60, gravel, coll)

    right, left = [], []
    for i in range(N):
        k = curvature(i, 8); desired = HW + 18
        lim = 0.8 / abs(k) if abs(k) > 1e-4 else desired
        right.append(min(desired, lim) if k > 0 else desired)
        left.append(-min(desired, lim) if k < 0 else -desired)
    right, left = smooth_loop(right, 6), smooth_loop(left, 6)
    pit = lambda i: CUM[i] < 320 or CUM[i] > L - 60
    wall("ArmcoR", lambda i: right[i], 0.25, 0.95, None, steel, coll)
    wall("ArmcoL", lambda i: left[i], 0.25, 0.95, lambda i: not pit(i), steel, coll)
    wall("PitWall", lambda i: left[i], 0.0, 1.2, pit, concrete, coll)

    # Ground plane (grass) beneath everything.
    bpy.ops.mesh.primitive_plane_add(size=1, location=(140, -215, -0.05))
    g = bpy.context.active_object; g.name = "Ground"; g.scale = (2000, 1700, 1)
    bpy.ops.object.transform_apply(scale=True)
    me = g.data; uvl = me.uv_layers.active
    for poly in me.polygons:
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co; uvl.data[li].uv = (v.x, v.y)
    for c in g.users_collection: c.objects.unlink(g)
    coll.objects.link(g); g.data.materials.append(grass)

    # Start line and grid boxes (same slots as RaceDirector: 12 m + 8 m per slot, +-2.6 m).
    def stripe(name, d, length, a, b):
        p0, t0, r0 = at(d); p1, t1, r1 = at(d + length)
        me = bpy.data.meshes.new(name)
        vs = [(p0 + r0 * a), (p1 + r1 * a), (p1 + r1 * b), (p0 + r0 * b)]
        me.from_pydata([(v.x, v.y, 0.035) for v in vs], [], [(0, 3, 2, 1)]); o = bpy.data.objects.new(name, me)
        o.data.materials.append(paint); coll.objects.link(o)
    stripe("StartLine", 0, 0.8, -HW, HW)
    for s in range(6):
        d = -(12 + s * 8) + 2.6; lat = -2.6 if s % 2 == 0 else 2.6
        stripe(f"Grid{s}a", d, 0.25, lat - 1.3, lat + 1.3)
        stripe(f"Grid{s}b", d - 1.6, 1.6, lat - 1.3, lat - 1.05)
        stripe(f"Grid{s}c", d - 1.6, 1.6, lat + 1.05, lat + 1.3)

    # Gantry over the line.
    p, t, r = at(0); yaw = math.atan2(t.y, t.x); span = HW + 2.4
    for sgn in (1, -1):
        box("GantryPillar", (p.x + r.x * span * sgn, p.y + r.y * span * sgn, 3.6), (0.6, 0.6, 7.2), yaw, dark, coll)
    box("GantryBeam", (p.x, p.y, 6.6), (0.7, span * 2 + 0.6, 1.1), yaw, dark, coll)
    for k in range(5):
        off = (k - 2) * 1.1
        box("Lamp", (p.x + r.x * off - t.x * 0.37, p.y + r.y * off - t.y * 0.37, 6.6), (0.06, 0.7, 0.7), yaw, lamp, coll)

    # Grandstand outside the pit straight (left of the driving direction).
    a, _, rr = at(-40); b, _, _ = at(150); along = (b - a).normalized(); out = -at(50)[2]
    base = a + out * (HW + 18 + 6); length = (b - a).length; yaw = math.atan2(along.y, along.x)
    for row in range(9):
        z = 1.2 + row * 0.5; depth = row * 0.85
        c = base + out * (depth + 0.425) + along * length / 2
        box("Seats", (c.x, c.y, z + 0.25), (length, 0.85, 0.08), yaw, seats, coll)
        box("Riser", (c.x, c.y, z / 2 + 0.1), (length, 0.85, z), yaw, concrete, coll)
    top = 1.2 + 9 * 0.5; c = base + out * (9 * 0.85 * 0.45) + along * length / 2
    box("Roof", (c.x, c.y, top + 3.2), (length + 2, 9 * 0.85 + 3, 0.3), yaw, dark, coll)
    for k in range(7):
        q = base + out * (9 * 0.85) + along * (length * k / 6)
        box("Column", (q.x, q.y, (top + 3.2) / 2), (0.35, 0.35, top + 3.2), yaw, dark, coll)
    back = base + out * (9 * 0.85) + along * length / 2
    box("BackWall", (back.x, back.y, (top + 1.5) / 2), (length, 0.4, top + 1.5), yaw, concrete, coll)

# ---------------------------------------------------------------- scene
def setup_world():
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = int(os.environ.get("GL_SAMPLES", "128"))
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.02
    sc.cycles.use_denoising = False          # Ubuntu's Blender build ships without OpenImageDenoise
    sc.cycles.sample_clamp_indirect = 3.0
    sc.render.film_transparent = False
    sc.cycles.max_bounces = 4
    sc.render.resolution_x, sc.render.resolution_y = 1600, 900
    sc.render.resolution_percentage = int(os.environ.get("GL_PCT", "100"))
    sc.view_settings.view_transform = "AgX" if "AgX" in [i.name for i in bpy.types.ColorManagedViewSettings.bl_rna.properties["view_transform"].enum_items] else "Filmic"
    sc.view_settings.look = "None"
    w = bpy.data.worlds.new("Sky"); sc.world = w; w.use_nodes = True
    nt = w.node_tree; sky = nt.nodes.new("ShaderNodeTexSky"); sky.sky_type = "NISHITA"
    sky.sun_elevation = math.radians(38); sky.sun_rotation = math.radians(215); sky.air_density = 1.2; sky.dust_density = 1.6
    sky.sun_disc = False   # the sun lamp below provides the direct light and shadows
    nt.links.new(sky.outputs["Color"], nt.nodes["Background"].inputs["Color"])
    nt.nodes["Background"].inputs["Strength"].default_value = float(os.environ.get("GL_SKY", "0.12"))
    sun = bpy.data.lights.new("Sun", "SUN"); sun.energy = float(os.environ.get("GL_SUN", "2.6")); sun.angle = math.radians(1.2); sun.color = (1.0, 0.95, 0.88)
    so = bpy.data.objects.new("Sun", sun); sc.collection.objects.link(so)
    so.rotation_euler = (math.radians(90 - 38), 0, math.radians(215 + 90))

def camera(name, loc, target, lens=35):
    cam = bpy.data.cameras.new(name); cam.lens = lens; cam.clip_end = 2500
    o = bpy.data.objects.new(name, cam); bpy.context.scene.collection.objects.link(o)
    o.location = loc
    d = Vector(target) - Vector(loc); o.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    return o

def render(name, cam):
    sc = bpy.context.scene; sc.camera = cam
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", sc.render.filepath, flush=True)

def export_glb():
    """Export the existing car and circuit (no remodelling) as glTF for the Godot project.
    Material *names* carry through; Godot assigns mobile-friendly materials by name."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    track = bpy.data.collections.new("Track"); bpy.context.scene.collection.children.link(track)
    build_track(track)
    # Bake metre-based UVs into texture repeats so no material-side tiling is needed for repeating surfaces.
    for o in track.objects:
        if o.type != "MESH": continue
        for mod in list(o.modifiers):
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.modifier_apply(modifier=mod.name)
    out_track = os.path.join(OUT, "ashford_circuit.glb")
    bpy.ops.object.select_all(action="DESELECT")
    for o in track.objects: o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out_track, export_format="GLB", use_selection=True, export_apply=True,
                              export_materials="PLACEHOLDER", export_yup=True)
    print("EXPORTED", out_track, flush=True)
    for o in list(track.objects): bpy.data.objects.remove(o, do_unlink=True)

    cars = bpy.data.collections.new("Car"); bpy.context.scene.collection.children.link(cars)
    root = make_car("MuscleCar", "player_white", (0, 0), (0, 1), cars)
    root.location = (0, 0, 0)
    bpy.context.view_layer.update()
    # Body parts and one wheel set; wheels are positioned by VehicleWheel3D in Godot, so export a single
    # tyre+rim pair at the origin (left-side orientation) alongside the body.
    wheels = [o for o in cars.objects if o.type == "MESH" and (o.data.materials[0].name.startswith("RVP_Tire") or o.data.materials[0].name.startswith("RVP_Rim"))]
    keep = {}
    for o in wheels:
        kind = "tyre" if o.data.materials[0].name.startswith("RVP_Tire") else "rim"
        if kind in keep or o.matrix_world.translation.x > 0: 
            bpy.data.objects.remove(o, do_unlink=True); continue
        keep[kind] = o
        mw = o.matrix_world.copy(); o.parent = None
        o.matrix_world = Matrix.Translation(-mw.translation) @ mw
        o.name = "Wheel_" + kind
    bpy.ops.object.select_all(action="DESELECT")
    for o in cars.objects: o.select_set(True)
    out_car = os.path.join(OUT, "muscle_car.glb")
    bpy.ops.export_scene.gltf(filepath=out_car, export_format="GLB", use_selection=True, export_apply=True,
                              export_materials="PLACEHOLDER", export_yup=True)
    print("EXPORTED", out_car, flush=True)

def main():
    if SHOTS and SHOTS[0] == "export":
        export_glb()
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    setup_world()
    track = bpy.data.collections.new("Track"); bpy.context.scene.collection.children.link(track)
    cars = bpy.data.collections.new("Cars"); bpy.context.scene.collection.children.link(cars)
    build_track(track)
    liveries = ["player_white", "halden_blue", "corsair_red", "vantor_gold", "northline_green"]

    def car_at(name, livery, d, lateral):
        p, t, r = at(d); pos = p + r * lateral
        return make_car(name, livery, (pos.x, pos.y), (t.x, t.y), cars)

    # Field placement per shot is rebuilt so each image tells one story.
    def clear_cars():
        for o in list(cars.objects): bpy.data.objects.remove(o, do_unlink=True)

    for shot in SHOTS:
        clear_cars()
        if shot == "hero":
            car_at("Player", "player_white", 30, -1.5)
            p, t, r = at(30)
            cam = camera("cam", (p.x + t.x * 6.5 + r.x * -5.5, p.y + t.y * 6.5 + r.y * -5.5, 1.15), (p.x + r.x * -1.5, p.y + r.y * -1.5, 0.55), 45)
        elif shot == "grid":
            for s in range(5):
                car_at(f"Car{s}", liveries[(s + 1) % 5] if s < 4 else liveries[0], -(12 + s * 8), -2.6 if s % 2 == 0 else 2.6)
            p, t, r = at(-30)
            cam = camera("cam", (p.x + t.x * 30 + r.x * 16, p.y + t.y * 30 + r.y * 16, 7.5), (p.x - t.x * 2, p.y - t.y * 2, 0.5), 30)
        elif shot == "chase":
            # The in-game chase camera: 6.6 m behind, 2.3 m up, 58 deg vertical FOV, looking 3 m ahead of the car.
            d0 = 300
            car_at("Player", "player_white", d0, 1.0)
            car_at("AI1", "halden_blue", d0 + 22, 2.4)
            car_at("AI2", "corsair_red", d0 + 38, -1.2)
            p, t, r = at(d0); pos = p + r * 1.0
            cam = camera("cam", (pos.x - t.x * 6.6, pos.y - t.y * 6.6, 2.3), (pos.x + t.x * 3, pos.y + t.y * 3, 1.0), 25)
            cam.data.sensor_fit = "VERTICAL"; cam.data.angle_y = math.radians(58)
        elif shot == "corner":
            for k, (dd, lat, liv) in enumerate([(395, 1.8, "vantor_gold"), (384, -0.5, "player_white"), (372, 2.6, "halden_blue")]):
                car_at(f"C{k}", liv, dd, lat)
            p, t, r = at(392)
            cam = camera("cam", (p.x + r.x * -24 + t.x * 8, p.y + r.y * -24 + t.y * 8, 2.0), (p.x, p.y, 0.6), 70)
        elif shot == "aerial":
            for s in range(5): car_at(f"Car{s}", liveries[s], -(12 + s * 8), -2.6 if s % 2 == 0 else 2.6)
            cam = camera("cam", (140, -720, 520), (140, -215, 0), 32)
        elif shot == "liveries":
            p, t, r = at(60)
            for s, liv in enumerate(liveries):
                lat = (s - 2) * 3.0
                car_at(f"L{s}", liv, 60, lat)
            cam = camera("cam", (p.x + t.x * 13, p.y + t.y * 13, 3.2), (p.x, p.y, 0.4), 32)
        else:
            continue
        render(shot, cam)

main()
