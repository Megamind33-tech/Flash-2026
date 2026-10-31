"""Headless Blender: move faces wrongly classified as headlamps (GL_head) to trim (GL_black).

    blender -b --factory-startup --python tools/cars/fix_lamp_slots.py -- <in.glb> <out.glb> [middle_fraction] [low_m]

export_car.py maps source materials to GRIDLINE's canonical set by name. Some source models reuse a lamp
material on body parts (Ravenna: the side intake strip; Solano: a front vent), so those parts glowed like
headlights in game. A headlamp can only sit at the ends of the car: any GL_head face whose centre lies in the
middle `middle_fraction` of the car's length (default 0.6), or lower than `low_m` metres above the ground
(default 0: off; headlamps sit high on the nose), is reassigned to GL_black. Node names (Wheel_*) and
the canonical material names are kept, so CarBuilder and CarSpecs are unaffected.
"""
import bpy, bmesh, sys, mathutils

argv = sys.argv[sys.argv.index("--") + 1:]
src, out = argv[0], argv[1]
middle = float(argv[2]) if len(argv) > 2 else 0.6
low = float(argv[3]) if len(argv) > 3 else 0.0

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
bpy.context.view_layer.update()
# Car length axis in Blender after glTF import: glTF +Z (front) -> Blender -Y.
ys = [(o.matrix_world @ mathutils.Vector(v)).y for o in meshes if not o.name.startswith("Wheel_") for v in o.bound_box]
zs = [(o.matrix_world @ mathutils.Vector(v)).z for o in meshes for v in o.bound_box]
ground = min(zs)
y0, y1 = min(ys), max(ys)
centre, half = (y0 + y1) / 2, (y1 - y0) / 2
black = next((m for m in bpy.data.materials if m.name.split(".")[0] == "GL_black"), None)
if black is None:
    black = bpy.data.materials.new("GL_black")
moved = 0
for o in meshes:
    names = [s.material.name.split(".")[0] if s.material else "" for s in o.material_slots]
    if "GL_head" not in names:
        continue
    if "GL_black" not in names:
        o.data.materials.append(black)
        names.append("GL_black")
    head_idx = [i for i, n in enumerate(names) if n == "GL_head"]
    black_idx = names.index("GL_black")
    bm = bmesh.new()
    bm.from_mesh(o.data)
    mw = o.matrix_world
    for f in bm.faces:
        if f.material_index in head_idx:
            c = mw @ f.calc_center_median()
            if abs(c.y - centre) < middle * half or (low > 0 and c.z - ground < low):
                f.material_index = black_idx
                moved += 1
    bm.to_mesh(o.data)
    bm.free()
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB")
print("FIXED moved=%d faces from GL_head to GL_black (car length %.2f m)" % (moved, y1 - y0))
