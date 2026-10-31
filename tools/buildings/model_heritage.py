"""Heritage landmarks with no clean, licensable game model: modelled here to real dimensions and textured with
Poly Haven scans (CC0).

  blender -b --python tools/buildings/model_heritage.py

- Tower Bridge (1894): two 65 m Gothic towers 61 m apart on boat-shaped piers, the bascule deck 9 m above the water,
  the two high-level walkways (lattice girders, 42 m), suspension chains to the shore towers, blue-and-white steel
  (the 1977 livery), Portland-stone cladding. About 244 m long.
- The Giza pyramids as they stand today: stepped limestone courses (the casing is gone), Khufu 230 m base / 138.5 m,
  Khafre 215 m / 136 m with its surviving casing cap, Menkaure 103 m / 61 m. A real pyramid is a stepped pile of
  stone courses, so the geometry is faithful at about 1.3k triangles each; the sandstone-block scan does the rest.

Writes godot/assets/buildings/real/<id>/<id>.gltf and adds the entries to real/index.json.
"""
import bpy, bmesh, json, math, os, random, shutil, mathutils

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "godot", "assets", "buildings", "real")
TEX = "/home/user/deps/polyhaven_tex"
rng = random.Random(7)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def image_mat(name, stem, tile_tint=(1, 1, 1), rough=0.85):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    img = nt.nodes.new("ShaderNodeTexImage")
    img.image = bpy.data.images.load(os.path.join(TEX, stem + "_diff_2k.jpg"))
    if tile_tint != (1, 1, 1):
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs[7].default_value = (*tile_tint, 1)
        nt.links.new(img.outputs["Color"], mix.inputs[6])
        nt.links.new(mix.outputs[2], p.inputs["Base Color"])
    else:
        nt.links.new(img.outputs["Color"], p.inputs["Base Color"])
    nimg = nt.nodes.new("ShaderNodeTexImage")
    nimg.image = bpy.data.images.load(os.path.join(TEX, stem + "_nor_gl_2k.jpg"))
    nimg.image.colorspace_settings.name = "Non-Color"
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(nimg.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], p.inputs["Normal"])
    p.inputs["Roughness"].default_value = rough
    return m


def flat_mat(name, rgb, metal=0.0, rough=0.6):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*rgb, 1)
    p.inputs["Metallic"].default_value = metal
    p.inputs["Roughness"].default_value = rough
    return m


class Mesh:
    """Accumulates quads per material; UVs are world-space box projection in metres / tile."""

    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new()
        self.mats = []

    def mat_index(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def face(self, pts, m, tile=4.0):
        vs = [self.bm.verts.new(p) for p in pts]
        f = self.bm.faces.new(vs)
        f.material_index = self.mat_index(m)
        f.normal_update()
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        u_ax, v_ax = {0: (1, 2), 1: (0, 2), 2: (0, 1)}[ax]
        for loop in f.loops:
            co = loop.vert.co
            loop[self.uv].uv = (co[u_ax] / tile, co[v_ax] / tile)
        return f

    def box(self, x0, x1, y0, y1, z0, z1, m, tile=4.0, top=True, bottom=False):
        c = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
        for q in ((0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
            self.face([c[i] for i in q], m, tile)
        if top:
            self.face([c[4], c[5], c[6], c[7]], m, tile)
        if bottom:
            self.face([c[3], c[2], c[1], c[0]], m, tile)

    def beam(self, a, b, w, h, m, tile=4.0):
        """A rectangular member from a to b (any direction), w wide (horizontal), h tall."""
        a = mathutils.Vector(a)
        b = mathutils.Vector(b)
        d = (b - a).normalized()
        side = d.cross(mathutils.Vector((0, 0, 1)))
        if side.length < 1e-4:
            side = mathutils.Vector((1, 0, 0))
        side.normalize()
        up = side.cross(d).normalized()
        s, u = side * w / 2, up * h / 2
        c = [a - s - u, a + s - u, a + s + u, a - s + u, b - s - u, b + s - u, b + s + u, b - s + u]
        for q in ((0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
            self.face([c[i] for i in q], m, tile)

    def prism(self, cx, cy, r, z0, z1, sides, m, tile=4.0, rot=0.0):
        pts = [(cx + r * math.cos(rot + 2 * math.pi * k / sides), cy + r * math.sin(rot + 2 * math.pi * k / sides)) for k in range(sides)]
        for k in range(sides):
            (x0, y0), (x1, y1) = pts[k], pts[(k + 1) % sides]
            self.face([(x0, y0, z0), (x1, y1, z0), (x1, y1, z1), (x0, y0, z1)], m, tile)

    def cone(self, cx, cy, r, z0, z1, sides, m, tile=4.0, rot=0.0):
        pts = [(cx + r * math.cos(rot + 2 * math.pi * k / sides), cy + r * math.sin(rot + 2 * math.pi * k / sides)) for k in range(sides)]
        for k in range(sides):
            (x0, y0), (x1, y1) = pts[k], pts[(k + 1) % sides]
            self.face([(x0, y0, z0), (x1, y1, z0), (cx, cy, z1)], m, tile)

    def finish(self, name):
        me = bpy.data.meshes.new(name)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        self.bm.to_mesh(me)
        for m in self.mats:
            me.materials.append(m)
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


def export(ob, ident, info):
    out_dir = os.path.join(OUT, ident)
    if os.path.isdir(out_dir):
        shutil.rmtree(out_dir)
    os.makedirs(out_dir)
    for img in bpy.data.images:
        if img.size[0] > 1024:
            img.scale(1024, 1024)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, ident + ".gltf"), export_format="GLTF_SEPARATE", use_selection=True,
                              export_texture_dir="textures", export_image_format="JPEG", export_jpeg_quality=85, export_yup=True)
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    mn = [min((ob.matrix_world @ v.co)[i] for v in ob.data.vertices) for i in range(3)]
    mx = [max((ob.matrix_world @ v.co)[i] for v in ob.data.vertices) for i in range(3)]
    info.update({"id": ident, "width": round(mx[0] - mn[0], 2), "depth": round(mx[1] - mn[1], 2), "height": round(mx[2] - mn[2], 2), "tris": tris,
                 "author": "GRIDLINE (modelled from public reference)", "licence": "Project-owned model; textures Poly Haven CC0", "url": "https://polyhaven.com"})
    with open(os.path.join(out_dir, "LICENSE.txt"), "w") as f:
        f.write("Modelled for GRIDLINE in tools/buildings/model_heritage.py (project-owned). Textures: Poly Haven, CC0.\n")
    print("MODELLED", ident, tris, "tris", info["width"], info["depth"], info["height"])
    return info


# ------------------------------------------------------------------------------------------------ Tower Bridge
def tower_bridge():
    reset()
    stone = image_mat("TB_stone", "castle_wall_varriation", (0.93, 0.9, 0.84), 0.85)
    blue = flat_mat("TB_steel_blue", (0.33, 0.55, 0.78), 0.35, 0.45)
    white = flat_mat("TB_steel_white", (0.86, 0.87, 0.86), 0.3, 0.5)
    road = flat_mat("TB_deck", (0.12, 0.12, 0.13), 0.0, 0.85)
    glass = flat_mat("TB_window", (0.05, 0.06, 0.08), 0.2, 0.25)
    slate = flat_mat("TB_roof", (0.22, 0.24, 0.27), 0.1, 0.6)
    gold = flat_mat("TB_gilt", (0.75, 0.6, 0.25), 1.0, 0.35)
    M = Mesh()
    DECK = 9.0
    for sx in (-1, 1):
        cx = sx * 40.5   # tower centres: 61 m clear span + half the 20 m tower
        # boat-shaped pier, -2 .. deck
        M.box(cx - 12, cx + 12, -16, 16, -2.0, DECK - 0.5, stone, 5.0)
        for sy in (-1, 1):
            M.face([(cx - 12, sy * 16, -2), (cx + 12, sy * 16, -2), (cx, sy * 24, -2)], stone)
            M.face([(cx - 12, sy * 16, -2), (cx, sy * 24, -2), (cx, sy * 24, DECK - 0.5), (cx - 12, sy * 16, DECK - 0.5)], stone, 5.0)
            M.face([(cx, sy * 24, -2), (cx + 12, sy * 16, -2), (cx + 12, sy * 16, DECK - 0.5), (cx, sy * 24, DECK - 0.5)], stone, 5.0)
            M.face([(cx - 12, sy * 16, DECK - 0.5), (cx, sy * 24, DECK - 0.5), (cx + 12, sy * 16, DECK - 0.5)], stone, 5.0)
        # tower: two legs either side of the roadway arch, a solid block above, turrets, roof and spires
        for sy in (-1, 1):
            M.box(cx - 10, cx + 10, sy * 6.5, sy * 12.0, DECK, 24.0, stone)
        M.box(cx - 10, cx + 10, -12.0, 12.0, 24.0, 52.0, stone)
        # string courses and cornice
        for z in (24.0, 34.0, 44.0):
            M.box(cx - 10.4, cx + 10.4, -12.4, 12.4, z, z + 0.6, stone, 2.0)
        M.box(cx - 10.8, cx + 10.8, -12.8, 12.8, 51.4, 52.6, stone, 2.0)
        # windows: tall gothic lancets on every face, three stages
        for z0, h in ((26.0, 6.5), (36.0, 6.5), (45.5, 4.5)):
            for k in (-1, 0, 1):
                for sy in (-1, 1):   # faces across the bridge (±y)
                    x = cx + k * 5.0
                    y = sy * 12.05
                    M.face([(x - 0.9, y, z0), (x + 0.9, y, z0), (x + 0.9, y, z0 + h), (x, y, z0 + h + 1.1), (x - 0.9, y, z0 + h)], glass)
                for sx2 in (-1, 1):   # faces along the bridge (±x)
                    x = cx + sx2 * 10.05
                    y = k * 6.0
                    M.face([(x, y - 0.9, z0), (x, y + 0.9, z0), (x, y + 0.9, z0 + h), (x, y, z0 + h + 1.1), (x, y - 0.9, z0 + h)], glass)
        # four octagonal corner turrets with spires and gilt finials
        for tx in (-1, 1):
            for ty in (-1, 1):
                px, py = cx + tx * 10.0, ty * 12.0
                M.prism(px, py, 2.6, DECK, 58.0, 8, stone, 4.0, math.pi / 8)
                M.prism(px, py, 3.0, 57.4, 58.4, 8, stone, 2.0, math.pi / 8)
                M.cone(px, py, 2.7, 58.4, 65.5, 8, slate, 4.0, math.pi / 8)
                M.beam((px, py, 65.4), (px, py, 67.0), 0.25, 0.25, gold)
        # main pyramid roof with dormers and the central spire
        M.face([(cx - 10.8, -12.8, 52.6), (cx + 10.8, -12.8, 52.6), (cx, 0, 61.5)], slate)
        M.face([(cx + 10.8, -12.8, 52.6), (cx + 10.8, 12.8, 52.6), (cx, 0, 61.5)], slate)
        M.face([(cx + 10.8, 12.8, 52.6), (cx - 10.8, 12.8, 52.6), (cx, 0, 61.5)], slate)
        M.face([(cx - 10.8, 12.8, 52.6), (cx - 10.8, -12.8, 52.6), (cx, 0, 61.5)], slate)
        M.prism(cx, 0, 1.6, 60.0, 64.0, 8, slate, 2.0)
        M.cone(cx, 0, 1.7, 64.0, 70.0, 8, slate)
        M.beam((cx, 0, 69.8), (cx, 0, 71.5), 0.3, 0.3, gold)
    # bascule deck (raised road), blue edge girders with white rails
    M.box(-30.5, 30.5, -9.0, 9.0, DECK - 0.8, DECK, road, 6.0, bottom=True)
    for sy in (-1, 1):
        M.box(-30.5, 30.5, sy * 9.0 - 0.4, sy * 9.0 + 0.4, DECK - 2.6, DECK + 1.2, blue, 3.0, bottom=True)
        M.box(-30.5, 30.5, sy * 9.0 - 0.1, sy * 9.0 + 0.1, DECK + 1.2, DECK + 1.3, white, 3.0)
    # high-level walkways: two lattice girders upstream and downstream
    for sy in (-1, 1):
        y = sy * 6.0
        for z in (42.0, 46.2):
            M.box(-30.5, 30.5, y - 1.6, y + 1.6, z, z + 0.8, blue, 3.0, bottom=True)
        n = 12
        for k in range(n):
            x0 = -30.5 + 61.0 * k / n
            x1 = -30.5 + 61.0 * (k + 1) / n
            for yy in (y - 1.6, y + 1.6):
                M.beam((x0, yy, 42.8), (x1, yy, 46.2), 0.3, 0.45, blue if k % 2 else white)
                M.beam((x1, yy, 42.8), (x0, yy, 46.2), 0.3, 0.45, blue)
                M.beam((x0, yy, 42.8), (x0, yy, 46.2), 0.3, 0.35, white)
    # side spans: deck from the main towers to the shore, suspension chains and hangers, abutment towers
    for sx in (-1, 1):
        x0, x1 = sx * 50.5, sx * 122.0
        lo, hi = (x0, x1) if sx > 0 else (x1, x0)
        M.box(lo, hi, -9.0, 9.0, DECK - 0.8, DECK, road, 6.0, bottom=True)
        for sy in (-1, 1):
            M.box(lo, hi, sy * 9.0 - 0.4, sy * 9.0 + 0.4, DECK - 1.8, DECK + 1.2, blue, 3.0, bottom=True)
            # chain: from the main tower at 40 m down to the deck mid-span and up to the shore tower at 24 m
            pts = []
            for k in range(13):
                t = k / 12.0
                x = x0 + (x1 - x0) * t
                z = 40.0 * (1 - t) ** 2 + 9.5 * 2 * t * (1 - t) + 24.0 * t ** 2
                pts.append((x, sy * 9.6, z))
            for a, b in zip(pts, pts[1:]):
                M.beam(a, b, 0.9, 1.4, blue)
            for a in pts[1:-1]:
                M.beam((a[0], a[1], DECK + 1.2), (a[0], a[1], a[2] - 0.7), 0.25, 0.25, white)
        # shore abutment tower
        ax = x1 + sx * 5.0
        M.box(ax - 6, ax + 6, -11, 11, -2.0, 24.0, stone)
        M.box(ax - 6.4, ax + 6.4, -11.4, 11.4, 23.4, 24.4, stone, 2.0)
        for ty in (-1, 1):
            M.prism(ax, ty * 9.0, 2.0, 24.4, 28.0, 8, stone)
            M.cone(ax, ty * 9.0, 2.1, 28.0, 32.0, 8, slate)
        for sy in (-1, 1):
            for k in (-1, 1):
                M.face([(ax + k * 2.2 - 0.8, sy * 11.05, 12.0), (ax + k * 2.2 + 0.8, sy * 11.05, 12.0), (ax + k * 2.2 + 0.8, sy * 11.05, 18.0),
                        (ax + k * 2.2, sy * 11.05, 19.0), (ax + k * 2.2 - 0.8, sy * 11.05, 18.0)], glass)
    ob = M.finish("tower_bridge")
    return export(ob, "tower_bridge", {"kind": "landmark", "cities": ["london"], "name": "Tower Bridge", "front": "-y", "source_tris": 0})


# ------------------------------------------------------------------------------------------------ pyramids
def pyramid(ident, base, h_full, h_now, courses, casing_from=None, seed=1):
    reset()
    r = random.Random(seed)
    stone = image_mat(ident + "_stone", "large_sandstone_blocks_01", (0.98, 0.9, 0.76), 0.92)
    casing = image_mat(ident + "_casing", "large_sandstone_blocks_01", (1.08, 1.02, 0.9), 0.8) if casing_from else None
    M = Mesh()
    dz = h_now / courses
    prev = None
    for c in range(courses):
        z0, z1 = c * dz, (c + 1) * dz
        cased = casing_from is not None and z0 >= casing_from
        half0 = base / 2 * (1 - z0 / h_full)
        half1 = base / 2 * (1 - z1 / h_full)
        if cased:
            # smooth casing: one sloped band, no step
            q0 = [(-half0, -half0), (half0, -half0), (half0, half0), (-half0, half0)]
            q1 = [(-half1, -half1), (half1, -half1), (half1, half1), (-half1, half1)]
            for k in range(4):
                a0, b0 = q0[k], q0[(k + 1) % 4]
                a1, b1 = q1[k], q1[(k + 1) % 4]
                M.face([(a0[0], a0[1], z0), (b0[0], b0[1], z0), (b1[0], b1[1], z1), (a1[0], a1[1], z1)], casing, 6.0)
            continue
        # stepped course: riser at half0 - jitter, tread to half1
        j = [r.uniform(-0.35, 0.35) for _ in range(4)]
        s = [half0 - 0.15 + j[k] * 0.4 for k in range(4)]   # per-face riser offset (weathering)
        t = half1
        q = [(-s[3], -s[0]), (s[1], -s[0]), (s[1], s[2]), (-s[3], s[2])]
        for k in range(4):
            a, b = q[k], q[(k + 1) % 4]
            M.face([(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1)], stone, 7.0)
        inner = [(-t, -t), (t, -t), (t, t), (-t, t)]
        for k in range(4):
            a, b = q[k], q[(k + 1) % 4]
            ia, ib = inner[k], inner[(k + 1) % 4]
            M.face([(a[0], a[1], z1), (b[0], b[1], z1), (ib[0], ib[1], z1), (ia[0], ia[1], z1)], stone, 7.0)
    top = base / 2 * (1 - h_now / h_full)
    if top > 0.5:
        M.face([(-top, -top, h_now), (top, -top, h_now), (top, top, h_now), (-top, top, h_now)], casing or stone)
    else:
        pass
    ob = M.finish(ident)
    return export(ob, ident, {"kind": "landmark", "cities": ["giza", "cairo"], "name": ident.replace("_", " ").title(), "front": "-y", "source_tris": 0})


index_path = os.path.join(OUT, "index.json")
index = json.load(open(index_path)) if os.path.exists(index_path) else {}
index["tower_bridge"] = tower_bridge()
index["great_pyramid"] = pyramid("great_pyramid", 230.3, 146.6, 138.5, 72, seed=3)
index["khafre_pyramid"] = pyramid("khafre_pyramid", 215.3, 143.5, 136.4, 70, casing_from=104.0, seed=5)
index["menkaure_pyramid"] = pyramid("menkaure_pyramid", 103.4, 65.5, 61.0, 40, seed=9)
json.dump(index, open(index_path, "w"), indent=1, sort_keys=True)
