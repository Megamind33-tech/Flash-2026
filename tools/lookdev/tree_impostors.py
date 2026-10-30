"""
Renders CC0 Poly Haven tree models into 2-view RGBA sprites for cross-quad impostors (mobile-cheap foliage).
Usage: blender -b -P tree_impostors.py -- <model.gltf> <out_prefix> [height_px]
Writes <out_prefix>_a.png, <out_prefix>_b.png and prints the model height in metres.
"""
import bpy, sys, math
from mathutils import Vector
argv = sys.argv[sys.argv.index("--") + 1:]
src, out = argv[0], argv[1]
H = int(argv[2]) if len(argv) > 2 else 1024
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
mn = Vector((1e9,) * 3); mx = Vector((-1e9,) * 3)
for o in objs:
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c); mn = Vector(map(min, mn, w)); mx = Vector(map(max, mx, w))
size = mx - mn
centre = (mn + mx) / 2
sc = bpy.context.scene
sc.render.engine = "CYCLES"; sc.cycles.device = "CPU"; sc.cycles.samples = 24; sc.cycles.use_denoising = False
sc.render.film_transparent = True
width_m = max(size.x, size.y)
sc.render.resolution_y = H; sc.render.resolution_x = int(H * width_m / size.z) // 4 * 4
sc.view_settings.view_transform = "Standard"
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.75, 0.8, 0.85, 1); w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
sun = bpy.data.lights.new("s", "SUN"); sun.energy = 2.2; so = bpy.data.objects.new("s", sun); sc.collection.objects.link(so)
so.rotation_euler = (math.radians(50), 0, math.radians(30))
cam = bpy.data.cameras.new("c"); cam.type = "ORTHO"; cam.ortho_scale = max(size.z, width_m) * 1.02
co = bpy.data.objects.new("c", cam); sc.collection.objects.link(co); sc.camera = co
for tag, ang in (("a", 0.0), ("b", 90.0)):
    a = math.radians(ang)
    co.location = (centre.x + math.sin(a) * 50, centre.y - math.cos(a) * 50, centre.z)
    co.rotation_euler = (math.radians(90), 0, a)
    sc.render.filepath = f"{out}_{tag}.png"
    bpy.ops.render.render(write_still=True)
print("TREE_HEIGHT", round(size.z, 2), "WIDTH", round(width_m, 2))
