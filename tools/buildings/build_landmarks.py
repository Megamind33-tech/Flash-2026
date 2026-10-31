"""Gate G7 — one skyline landmark per city, modelled from primitives in headless Blender (project-owned, no
third-party geometry). Real-world proportions in metres, low triangle counts (<= 15k, §4 'landmark building').

  blender -b --python tools/buildings/build_landmarks.py

Writes godot/assets/landmarks/<city>.glb. Materials are named GL_* so Godot can restyle them per weather.
"""
import bpy, bmesh, math, os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "godot", "assets", "landmarks")
PAL = {"GL_concrete": (0.72, 0.7, 0.66, 0.0, 0.85), "GL_glass": (0.18, 0.24, 0.3, 0.6, 0.12),
       "GL_steel": (0.5, 0.52, 0.55, 0.9, 0.35), "GL_white": (0.9, 0.89, 0.85, 0.0, 0.7),
       "GL_stone": (0.78, 0.68, 0.5, 0.0, 0.9), "GL_red": (0.55, 0.15, 0.1, 0.3, 0.5),
       "GL_gold": (0.85, 0.65, 0.25, 1.0, 0.3), "GL_green": (0.25, 0.42, 0.35, 0.6, 0.4),
       "GL_dark": (0.12, 0.12, 0.13, 0.2, 0.6)}


def mat(n):
    if n in bpy.data.materials:
        return bpy.data.materials[n]
    m = bpy.data.materials.new(n)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    r, g, b, met, rough = PAL[n]
    p.inputs["Base Color"].default_value = (r, g, b, 1)
    p.inputs["Metallic"].default_value = met
    p.inputs["Roughness"].default_value = rough
    return m


def put(o, m):
    o.data.materials.clear()
    o.data.materials.append(mat(m))
    return o


def box(sx, sy, sz, x=0, y=0, z=0, m="GL_concrete"):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, z + sz / 2))
    o = bpy.context.active_object
    o.scale = (sx, sy, sz)
    bpy.ops.object.transform_apply(scale=True)
    return put(o, m)


def cyl(r, h, z=0, x=0, y=0, m="GL_concrete", seg=24, r2=None):
    bpy.ops.mesh.primitive_cone_add(vertices=seg, radius1=r, radius2=r if r2 is None else r2, depth=h, location=(x, y, z + h / 2))
    return put(bpy.context.active_object, m)


def sphere(r, z, x=0, y=0, m="GL_steel", seg=24):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=r, location=(x, y, z))
    return put(bpy.context.active_object, m)


def dome(r, z, x=0, y=0, m="GL_white"):
    o = sphere(r, z, x, y, m, 20)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.01], context="VERTS")
    bm.to_mesh(o.data)
    return o


def export(name):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.shade_flat()
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB", use_selection=True, export_yup=True)
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.context.selected_objects if o.type == "MESH")
    print(f"LANDMARK {name}: {tris} tris")
    bpy.ops.object.delete()


def lusaka():   # tall slab office tower with vertical fins (Findeco-House-like proportions, ~100 m)
    box(32, 22, 96, m="GL_concrete")
    for i in range(9):
        box(0.8, 23, 96, x=-14 + i * 3.5, m="GL_white")
    box(36, 26, 6, m="GL_dark")
    box(14, 10, 8, z=96, m="GL_concrete")


def kitwe():    # copper mine headframe: twin legs, back stay, sheave wheels, winder house
    for x in (-5, 5):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(x, 0, 21))
        o = bpy.context.active_object
        o.scale = (0.9, 0.9, 42)
        bpy.ops.object.transform_apply(scale=True)
        put(o, "GL_red")
        bpy.ops.mesh.primitive_cube_add(size=1, location=(x, -10, 18))
        o = bpy.context.active_object
        o.scale = (0.7, 0.7, 40)
        o.rotation_euler = (math.radians(-28), 0, 0)
        put(o, "GL_red")
    for z in range(6, 42, 6):
        box(11, 0.5, 0.5, z=z, m="GL_red")
    box(12, 6, 3, z=42, m="GL_dark")
    for x in (-3, 3):
        bpy.ops.mesh.primitive_torus_add(major_radius=2.6, minor_radius=0.25, location=(x, 0, 46), rotation=(0, math.pi / 2, 0))
        put(bpy.context.active_object, "GL_steel")
    box(24, 14, 12, y=-28, m="GL_concrete")


def nairobi():  # cylindrical tower with a saucer crown (KICC-like, ~105 m) and a conical hall beside it
    cyl(9, 92, m="GL_stone", seg=32)
    for i in range(16):
        a = i / 16 * math.tau
        box(0.6, 0.6, 92, x=9.2 * math.cos(a), y=9.2 * math.sin(a), m="GL_white")
    cyl(18, 4, z=92, m="GL_white", seg=40, r2=13)
    cyl(10, 6, z=96, m="GL_white", seg=40, r2=4)
    cyl(18, 16, x=34, m="GL_stone", seg=24, r2=2)


def mogadishu():  # whitewashed minaret and domed prayer hall
    box(30, 30, 10, m="GL_white")
    dome(11, 10, m="GL_white")
    cyl(2.6, 38, x=18, y=18, m="GL_white", seg=12)
    cyl(3.4, 1.2, z=30, x=18, y=18, m="GL_white", seg=12)
    cyl(2.6, 4, z=38, x=18, y=18, m="GL_green", seg=12, r2=0.2)


def cairo():    # two slender minarets beside a stone mosque with a dome
    box(40, 30, 16, m="GL_stone")
    dome(12, 16, m="GL_stone")
    for x in (-20, 20):
        cyl(2.4, 30, x=x, y=16, m="GL_stone", seg=8)
        cyl(3.2, 1.5, z=30, x=x, y=16, m="GL_stone", seg=8)
        cyl(1.8, 14, z=31.5, x=x, y=16, m="GL_stone", seg=8)
        cyl(2.0, 6, z=45.5, x=x, y=16, m="GL_stone", seg=8, r2=0.2)


def london():   # gothic clock tower: shaft, clock stage with four faces, belfry and spire (~96 m)
    box(12, 12, 55, m="GL_stone")
    for k in range(4):
        box(0.6, 0.6, 55, x=(-6 if k % 2 else 6), y=(-6 if k < 2 else 6), m="GL_stone")
    box(14, 14, 12, z=55, m="GL_stone")
    for (x, y, r) in [(7.05, 0, (0, math.pi / 2, 0)), (-7.05, 0, (0, math.pi / 2, 0)), (0, 7.05, (math.pi / 2, 0, 0)), (0, -7.05, (math.pi / 2, 0, 0))]:
        bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=4.2, depth=0.2, location=(x, y, 61), rotation=r)
        put(bpy.context.active_object, "GL_white")
    box(11, 11, 10, z=67, m="GL_stone")
    cyl(8.5, 19, z=77, m="GL_dark", seg=4, r2=0.3).rotation_euler = (0, 0, math.pi / 4)


def berlin():   # TV tower: tapering shaft, sphere with a ring, antenna (~368 m)
    cyl(16, 4, m="GL_concrete", seg=24, r2=8)
    cyl(5.5, 200, z=4, m="GL_concrete", seg=24, r2=4.2)
    sphere(16, 218, m="GL_steel", seg=28)
    cyl(16.4, 3, z=214, m="GL_dark", seg=28)
    cyl(2.2, 120, z=234, m="GL_white", seg=8, r2=0.6)


for fn in (lusaka, kitwe, nairobi, mogadishu, cairo, london, berlin):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    fn()
    export(fn.__name__)
