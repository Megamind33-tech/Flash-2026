"""Gate G3: bring over-budget props under their §4 budget in headless Blender, keeping materials and textures.

  blender -b --python tools/assets/decimate_props.py

Reads the failures from budget_check.py and imports each GLB. It collapse-decimates every mesh by the
ratio needed (5 % under budget), skipping meshes under 200 triangles, and re-exports in place with the
same textures. A copy of each original goes to tools/assets/originals/ (git-ignored) so a decimation can
be checked by render and reverted.
"""
import bpy, os, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "godot", "assets")
sys.path.insert(0, HERE)
import budget_check as bc  # noqa: E402


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


for path in sorted(__import__("glob").glob(os.path.join(ROOT, "props", "**", "*.glb"), recursive=True)):
    rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
    rule = next((r for r in bc.RULES if r[0] in rel), None)
    js, _ = bc.read_glb(path)
    total = sum(t for _, t in bc.triangles(js))
    if rule is None or total <= rule[2]:
        continue
    keep = os.path.join(HERE, "originals", rel)
    os.makedirs(os.path.dirname(keep), exist_ok=True)
    if not os.path.exists(keep):
        shutil.copy2(path, keep)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=keep)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    budget = min(rule[2], rule[3]) * 0.95
    now = sum(tris(o) for o in meshes)
    ratio = budget / now
    for o in meshes:
        if tris(o) < 200:
            continue
        m = o.modifiers.new("dec", "DECIMATE")
        m.ratio = ratio
        m.use_collapse_triangulate = True
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_image_format="AUTO")
    print(f"DECIMATED {rel}: {now} -> ~{int(now * ratio)} tris (budget {rule[2]})", flush=True)
