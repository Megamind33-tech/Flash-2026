"""Headless Blender: turn a Poly Haven modular facade kit (CC0) into mobile-ready facade pieces for the city circuits.

    blender -b --factory-startup --python tools/buildings/export_facade_kit.py -- <kit.gltf> <kit_name> <out_dir>

A bay is a 3 m x 3 m wall piece plus its window/door insert (the kit places both at the same origin). Each piece is
normalised to one convention so the game can tile it along a building face:
  - origin at the bottom-centre of the facade plane, wall running along X, up +Y (Godot), front facing +Z;
  - the front side is found from the wall's own face normals, not assumed from the kit layout.
Pieces are decimated to the budgets below; the kit's own textures and normal maps carry the fine detail.
Writes <out_dir>/<piece>.gltf (+ .bin), a shared <out_dir>/textures/ and <out_dir>/kit.json (size and triangles of each piece).
"""
import bpy, bmesh, sys, os, json, math, mathutils

argv = sys.argv[sys.argv.index("--") + 1:]
src, kit, out_dir = argv[0], argv[1], argv[2]
os.makedirs(out_dir, exist_ok=True)

# piece name -> (wall piece, insert piece or None, triangle budget)
PIECES = {
    "urban": {
        "bay_window_a": ("wall_window_centered_large_01", "window_centered_large_01", 700),
        "bay_window_b": ("wall_window_centered_double_01", "window_centered_double_01", 700),
        "bay_window_c": ("wall_window_offset_small_01", "window_offset_small_01", 600),
        # Low-detail versions for upper storeys (seen from 10 m and more): same bay, 280-420 triangles.
        "bay_window_a_lo": ("wall_window_centered_large_01", "window_centered_large_01", 300),
        "bay_window_b_lo": ("wall_window_centered_double_01", "window_centered_double_01", 300),
        "bay_window_c_lo": ("wall_window_offset_small_01", "window_offset_small_01", 280),
        "bay_blank": ("wall_standard_standard_01", None, 250),
        "bay_shop": ("wall_door_window_small_01", "door_window_small_01", 800),
        "bay_door": ("wall_door_centered_large_01", "door_centered_large_01", 700),
        "strip_base": ("base_standard_01", None, 60),
        "strip_cornice": ("cornice_standard_standard_01", None, 80),
        "strip_crown": ("crown_standard_standard_01", None, 260),
    },
    "factory": {
        "bay_window_a": ("wall_window_centered_large_01", "window_centered_large_01", 700),
        "bay_window_b": ("wall_window_centered_double_01", "window_centered_double_01", 700),
        "bay_window_c": ("wall_window_centered_medium_01", "window_centered_medium_01", 650),
        "bay_window_a_lo": ("wall_window_centered_large_01", "window_centered_large_01", 420),   # steel grids need more
        "bay_window_b_lo": ("wall_window_centered_double_01", "window_centered_double_01", 420),
        "bay_window_c_lo": ("wall_window_centered_medium_01", "window_centered_medium_01", 400),
        "bay_blank": ("wall_standard_standard_01", None, 250),
        "bay_shop": ("wall_door_window_small_01", "door_window_small_01", 800),
        "bay_door": ("wall_door_recessed_large_01", "door_recessed_large_01", 800),
        "strip_base": ("base_standard_standard_01", None, 60),
        "strip_cornice": ("cornice01_standard_standard_01", None, 80),
        "strip_crown": ("crown_standard_standard_01", None, 200),
    },
}[kit]


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
lib = {o.name: o for o in bpy.context.scene.objects if o.type == "MESH"}
report = {}
for piece, (wall_name, insert_name, budget) in PIECES.items():
    if wall_name not in lib:
        print("MISSING", piece, wall_name, flush=True)
        continue
    names = [wall_name] + ([insert_name] if insert_name and insert_name in lib else [])
    copies = []
    for n in names:
        o = lib[n].copy()
        o.data = lib[n].data.copy()
        bpy.context.scene.collection.objects.link(o)
        copies.append(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in copies:
        o.select_set(True)
    bpy.context.view_layer.objects.active = copies[0]
    if len(copies) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = piece
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    # Move the kit origin to world origin (the kit lays pieces out on a grid).
    origin = lib[wall_name].matrix_world.translation.copy()
    obj.location = (0, 0, 0)
    obj.data.transform(mathutils.Matrix.Translation(-(origin - lib[wall_name].matrix_world.translation) * 0))
    # Front side: area-weighted average normal of the wall piece's faces (its outward side dominates).
    wall = lib[wall_name]
    nsum = mathutils.Vector()
    for p in wall.data.polygons:
        nsum += (wall.matrix_world.to_3x3() @ p.normal) * p.area
    front = mathutils.Vector((nsum.x, nsum.y, 0.0))
    if front.length < 1e-6:
        front = mathutils.Vector((0, -1, 0))
    front.normalize()
    # Rotate so the front faces Blender -Y (exports as glTF/Godot +Z).
    ang = math.atan2(front.x, -front.y)
    obj.data.transform(mathutils.Matrix.Rotation(ang, 4, "Z"))
    # Origin: bottom-centre of the facade plane (x centred, z at the bottom, y at the front-most wall plane).
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    xs = [v.co.x for v in bm.verts]
    zs = [v.co.z for v in bm.verts]
    bm.free()
    cx = (min(xs) + max(xs)) / 2
    wall_tmp = wall.copy()
    wall_tmp.data = wall.data.copy()
    wall_tmp.data.transform(wall.matrix_world)
    wall_tmp.data.transform(mathutils.Matrix.Rotation(ang, 4, "Z"))
    wall_y = min(v.co.y for v in wall_tmp.data.vertices)   # wall's front plane (front is -Y)
    bpy.data.meshes.remove(wall_tmp.data)
    obj.data.transform(mathutils.Matrix.Translation((-cx, -wall_y, -min(zs))))
    before = tris(obj)
    if before > budget:
        mod = obj.modifiers.new("dec", "DECIMATE")
        mod.ratio = budget / before
        bpy.ops.object.modifier_apply(modifier="dec")
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    # Separate .gltf + one shared textures/ folder: every piece references the same image files, so the game
    # loads each kit texture once instead of once per piece.
    bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, piece + ".gltf"), export_format="GLTF_SEPARATE",
                              export_texture_dir="textures", use_selection=True,
                              export_image_format="JPEG", export_jpeg_quality=88)
    d = obj.dimensions
    report[piece] = {"source": names, "width": round(d.x, 3), "depth": round(d.y, 3), "height": round(d.z, 3),
                     "tris_before": before, "tris": tris(obj)}
    print("PIECE %s %s before=%d after=%d %.2fx%.2fx%.2f" % (kit, piece, before, tris(obj), d.x, d.y, d.z), flush=True)
    bpy.data.objects.remove(obj, do_unlink=True)
json.dump({"kit": kit, "pieces": report}, open(os.path.join(out_dir, "kit.json"), "w"), indent=1)
