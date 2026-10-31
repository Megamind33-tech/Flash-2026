"""Headless Blender: GRIDLINE's own trackside advertising hardware (no third-party meshes, so no licence risk).

  blender -b --python tools/ads/build_ad_hardware.py

Writes four GLBs at real-world dimensions (metres) to godot/assets/ads/hardware/. Each one has a "Screen" mesh
(material GL_screen, UV 0..1 across the visible face) that Godot fills with sponsor artwork; the housing uses
GL_frame / GL_steel / GL_concrete PBR materials. Godot axes after export: +Y up and the screen faces +Z.
"""
import bpy, bmesh, os, math

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "godot", "assets", "ads", "hardware")
MATS = {"GL_screen": ((0.05, 0.05, 0.05), 0.0, 0.25), "GL_frame": ((0.04, 0.04, 0.045), 0.6, 0.35),
        "GL_steel": ((0.55, 0.57, 0.6), 0.9, 0.3), "GL_concrete": ((0.62, 0.62, 0.6), 0.0, 0.9)}


def mat(name):
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    c, met, r = MATS[name]
    p.inputs["Base Color"].default_value = (*c, 1)
    p.inputs["Metallic"].default_value = met
    p.inputs["Roughness"].default_value = r
    return m


def box(name, size, loc, material, parent=None):
    """Blender coords: x right, y = depth (screen faces -Y so glTF faces +Z), z up."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(mat(material))
    if parent:
        o.parent = parent
    return o


def screen(name, w, h, loc):
    """Flat quad facing -Y (glTF +Z) with UVs 0..1, left-to-right / bottom-to-top."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    x, y, z = loc
    vs = [bm.verts.new((x - w / 2, y, z - h / 2)), bm.verts.new((x + w / 2, y, z - h / 2)),
          bm.verts.new((x + w / 2, y, z + h / 2)), bm.verts.new((x - w / 2, y, z + h / 2))]
    f = bm.faces.new(vs)
    uv = bm.loops.layers.uv.new()
    for loop, t in zip(f.loops, [(0, 0), (1, 0), (1, 1), (0, 1)]):
        loop[uv].uv = t
    bm.normal_update()
    if f.normal.y > 0:
        bmesh.ops.reverse_faces(bm, faces=[f])
    bm.to_mesh(me)
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    me.materials.append(mat("GL_screen"))
    return o


def export(fname):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, fname), export_format="GLB", use_selection=True,
                              export_yup=True, export_apply=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    print("exported", fname)


def main():
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # 1. LED trackside board: 6 x 1 m display on 0.8 m legs, 0.25 m deep cabinet.
    box("Cabinet", (6.2, 0.25, 1.15), (0, 0.13, 1.375), "GL_frame")
    for x in (-2.6, 2.6):
        box("Leg", (0.12, 0.12, 0.8), (x, 0.15, 0.4), "GL_steel")
    screen("Screen", 6.0, 1.0, (0, -0.005, 1.375))
    export("led_trackside_board.glb")
    # 2. Sponsor barrier: 3 m precast block (jersey profile approximated by two boxes) with a recessed panel.
    box("Base", (3.0, 0.6, 0.35), (0, 0.3, 0.175), "GL_concrete")
    box("Wall", (3.0, 0.32, 0.6), (0, 0.3, 0.65), "GL_concrete")
    screen("Screen", 2.8, 0.5, (0, 0.135, 0.62))
    export("sponsor_barrier.glb")
    # 3. Overhead ad gantry: 17 m span, 7.5 m columns, truss with double-sided 10 x 1.6 m screens.
    for x in (-8.5, 8.5):
        box("Column", (0.5, 0.5, 7.5), (x, 0, 3.75), "GL_steel")
    for z in (6.3, 7.4):
        box("Chord", (17.5, 0.25, 0.25), (0, 0, z), "GL_steel")
    for i in range(18):
        x = -8.5 + i
        box("Web", (0.08, 0.08, 1.2), (x + 0.5, 0, 6.85), "GL_steel").rotation_euler = (0, math.radians(35 if i % 2 else -35), 0)
    box("ScreenBox", (10.4, 0.5, 2.0), (0, 0, 6.85), "GL_frame")
    screen("Screen", 10.0, 1.6, (0, -0.26, 6.85))
    back = screen("ScreenBack", 10.0, 1.6, (0, -0.26, 6.85))
    back.rotation_euler = (0, 0, math.pi)   # same quad turned to face the other way; text still reads left-to-right
    export("overhead_ad_gantry.glb")
    # 4. Urban digital billboard: 8 x 4.5 m wall-mounted screen, 0.4 m frame, two brackets.
    box("Frame", (8.4, 0.4, 4.9), (0, 0.25, 2.45), "GL_frame")
    for x in (-3, 3):
        box("Bracket", (0.2, 0.6, 0.2), (x, 0.6, 2.45), "GL_steel")
    screen("Screen", 8.0, 4.5, (0, 0.045, 2.45))
    export("urban_digital_billboard.glb")


main()
