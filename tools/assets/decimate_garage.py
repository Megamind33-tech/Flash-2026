"""Game-ready versions of the Poly Haven garage props (they are film-quality: 13k-88k triangles each).

  blender -b --python tools/assets/decimate_garage.py

For every godot/assets/garage/models/<id>/<id>_1k.gltf over BUDGET triangles, writes <id>_game.gltf next to it
(collapse decimation to the budget, same 1k textures, same scale/origin). GarageStudio._prop loads the _game
version when it exists. Plants keep more triangles (leaf cards break under heavy decimation).
"""
import bpy, glob, os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "godot", "assets", "garage", "models")
BUDGET = 5000
SPECIAL = {"potted_plant_01": 9000, "potted_plant_02": 7000, "hanging_industrial_lamp": 2500, "mounted_fluorescent_lights": 1500,
           "covered_car": 6000, "sofa_02": 6000}


def tris():
    return sum(len(p.vertices) - 2 for o in bpy.context.scene.objects if o.type == "MESH" for p in o.data.polygons)


for path in sorted(glob.glob(os.path.join(ROOT, "*", "*_1k.gltf"))):
    ident = os.path.basename(os.path.dirname(path))
    budget = SPECIAL.get(ident, BUDGET)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    before = tris()
    out = os.path.join(os.path.dirname(path), ident + "_game.gltf")
    if before <= budget:
        if os.path.exists(out):
            os.remove(out)
        print("KEEP", ident, before)
        continue
    for o in [o for o in bpy.context.scene.objects if o.type == "MESH"]:
        n = sum(len(p.vertices) - 2 for p in o.data.polygons)
        if n < 200:
            continue
        m = o.modifiers.new("dec", "DECIMATE")
        m.ratio = max(0.02, budget / before)
        m.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier="dec")
    after = tris()
    # Same folder and texture names as the source, so no textures are duplicated.
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLTF_SEPARATE", export_texture_dir="textures",
                              export_image_format="AUTO", export_apply=True, export_animations=False)
    print("GAME", ident, before, "->", after)
