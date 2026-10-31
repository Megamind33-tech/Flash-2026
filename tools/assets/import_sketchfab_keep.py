"""Headless Blender 5.x: turn the kept Sketchfab models into mobile-ready GLBs for godot/assets/props/.

    blender -b --factory-startup --python tools/assets/import_sketchfab_keep.py -- <keep_glb_dir> <out_dir> [slug ...]

Input: the Sketchfab-converted GLBs (textures embedded), downloaded per docs/SKETCHFAB_TRIAGE.md.
For each asset (config below) it:
  1. fixes scale and drops junk geometry (e.g. a 10 km ground plane),
  2. decimates to the triangle target in docs/PRODUCTION_PLAN.md section 4,
  3. for road-surface scans without a normal map, bakes a normal map from the full-detail scan onto the
     decimated mesh (Cycles, selected-to-active), so the pothole keeps its depth at a fraction of the triangles,
  4. caps texture size, sits the asset on the ground (min Z = 0), centres it, and exports a GLB.
Prints one ASSET line per asset with triangles before/after and final dimensions.
"""
import bpy, sys, os, re, math, mathutils

# slug: scale, triangle target, texture cap (px), bake normals, plain material if untextured, drop meshes larger than (m)
CFG = {
    "263_detroit_pothole":                     dict(tris=3500, tex=512, bake=True),
    "cracks_in_asfalt_road_free":              dict(tris=3000, tex=512, bake=True),
    "manhole_cover_on_broken_asphalt_road":    dict(tris=3000, tex=512, bake=True),
    "cracked_concrete_old_3d_scan":            dict(tris=3000, tex=512, bake=True),
    "photoscan_manhole_cover_2":               dict(tris=2500, tex=512, bake=True),
    "curb_3d_scan":                            dict(tris=4000, tex=1024, bake=True),
    "sidewalk_8m_long_hq":                     dict(tris=3000, tex=1024, bake=True),
    "road_04":                                 dict(tris=4000, tex=1024, bake=True),
    "concrete_barrier":                        dict(scale=0.45, tris=400, tex=512),   # source 2.03 m tall -> 0.91 m
    "electrical_box_free":                     dict(tris=1500, tex=512),
    "guardrail_and_terminal":                  dict(tris=1500, tex=512),
    "parapet_guardrail_unit":                  dict(tris=600, tex=512),
    "steel_road_barrier":                      dict(tris=1200, tex=512),
    "new_york_hot_dog_cart":                   dict(tris=2500, tex=512),
    "game_ready_modular_metal_guardrail":      dict(scale=2.5, tris=2500, tex=512),   # 600 tore the rail; source 0.30 m tall -> 0.75 m
    # railing dropped: its thin bars collapse under any mobile budget (render check, 2026-10-31).
    "road_safety_barrier_fence_urban_metal_di": dict(scale=0.1, tris=2000, tex=512, plain="galvanised"),
    # stadium_light dropped: its ground plane is fused into the same mesh as the floodlight.
    "traffic_cones":                           dict(tris=3000, tex=512),
    "traffic_lights_street_assets_vol_02":     dict(tris=2500, tex=512),
    "subway_traffic_light_gameready":          dict(scale=0.018, tris=1500, tex=512),   # source is ~198 m tall
    "bus_station":                             dict(scale=0.5, tris=4000, tex=512),   # source ~7 m tall; estimated
}


def tri_count(objs):
    return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)


def meshes():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def bounds(objs):
    bpy.context.view_layer.update()   # bound_box is cached until the scene updates
    mn = mathutils.Vector((1e9,) * 3); mx = mathutils.Vector((-1e9,) * 3)
    for o in objs:
        for v in o.bound_box:
            w = o.matrix_world @ mathutils.Vector(v)
            mn = mathutils.Vector(map(min, mn, w)); mx = mathutils.Vector(map(max, mx, w))
    return mn, mx


def select_only(objs, active=None):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or (objs[0] if objs else None)


def has_normal_map(mat):
    if not mat or not mat.use_nodes:
        return False
    return any(n.type == "NORMAL_MAP" for n in mat.node_tree.nodes)


def plain_material(kind):
    m = bpy.data.materials.new("GL_" + kind)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (0.62, 0.64, 0.66, 1.0)
    p.inputs["Metallic"].default_value = 0.85
    p.inputs["Roughness"].default_value = 0.45
    return m


def process(src, out, slug, cfg):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    # Bake transforms into the meshes so scale/rotation from the source root are real geometry.
    # Authors sometimes upload Blender's untouched default cube along with the model: drop it.
    for o in list(meshes()):
        # glTF splits a cube's vertices at UV seams (8 -> 24), so match on size as well as count.
        if re.match(r"^Cube(\.\d+)?$", o.name) and len(o.data.vertices) <= 24 and \
                all(abs(d - 2.0) < 0.01 for d in o.dimensions):
            bpy.data.objects.remove(o, do_unlink=True)
    objs = meshes()
    # Drop junk geometry larger than the limit (e.g. ground planes).
    if "drop_over" in cfg:
        for o in list(objs):
            mn, mx = bounds([o])
            if max(mx - mn) > cfg["drop_over"]:
                bpy.data.objects.remove(o, do_unlink=True)
        objs = meshes()
    before = tri_count(objs)
    for o in list(bpy.context.scene.objects):
        if o.type not in ("MESH", "EMPTY"):
            bpy.data.objects.remove(o, do_unlink=True)
    select_only(objs)
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    for o in list(bpy.context.scene.objects):
        if o.type == "EMPTY":
            bpy.data.objects.remove(o, do_unlink=True)
    objs = meshes()
    select_only(objs)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if len(objs) > 1:
        select_only(objs)
        bpy.ops.object.join()
    hi = meshes()[0]
    hi.name = slug
    if cfg.get("scale", 1.0) != 1.0:
        s = cfg["scale"]
        hi.data.transform(mathutils.Matrix.Scale(s, 4))
    if cfg.get("plain") and not any(s.material and s.material.use_nodes and any(n.type == "TEX_IMAGE" for n in s.material.node_tree.nodes) for s in hi.material_slots):
        m = plain_material(cfg["plain"])
        hi.data.materials.clear()
        hi.data.materials.append(m)

    # Decimate a copy (low) and keep the original (high) for the bake.
    lo = hi.copy(); lo.data = hi.data.copy(); lo.name = slug
    bpy.context.scene.collection.objects.link(lo)
    hi.name = slug + "_hi"
    cur = tri_count([lo])
    if cur > cfg["tris"]:
        mod = lo.modifiers.new("dec", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = max(cfg["tris"] / cur, 0.001)
        select_only([lo])
        bpy.ops.object.modifier_apply(modifier="dec")

    baked = False
    if cfg.get("bake") and lo.data.uv_layers and not any(has_normal_map(s.material) for s in lo.material_slots):
        sc = bpy.context.scene
        sc.render.engine = "CYCLES"; sc.cycles.device = "CPU"; sc.cycles.samples = 1
        img = bpy.data.images.new(slug + "_normal", cfg["tex"], cfg["tex"], alpha=False)
        img.colorspace_settings.name = "Non-Color"
        # The low mesh gets its own copy of each material, with the bake target as the active node.
        for slot in lo.material_slots:
            if not slot.material:
                continue
            m = slot.material.copy(); slot.material = m
            nt = m.node_tree
            tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = img; tex.name = "baked_normal"
            nt.nodes.active = tex
        select_only([hi, lo], active=lo)
        size = max(bounds([lo])[1] - bounds([lo])[0])
        sc.render.bake.use_selected_to_active = True
        sc.render.bake.cage_extrusion = 0.005 * size
        sc.render.bake.max_ray_distance = 0.015 * size
        bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT")
        # Wire the baked map into each low material's normal input.
        for slot in lo.material_slots:
            m = slot.material
            if not m:
                continue
            nt = m.node_tree
            tex = nt.nodes.get("baked_normal")
            bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if tex and bsdf:
                nm = nt.nodes.new("ShaderNodeNormalMap")
                nt.links.new(tex.outputs["Color"], nm.inputs["Color"])
                nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
        img.pack()
        baked = True
    bpy.data.objects.remove(hi, do_unlink=True)

    # Cap texture size.
    for im in bpy.data.images:
        if im.size[0] > cfg["tex"] or im.size[1] > cfg["tex"]:
            k = cfg["tex"] / max(im.size[0], im.size[1])
            im.scale(max(1, int(im.size[0] * k)), max(1, int(im.size[1] * k)))
    # Sit on the ground, centred in X/Y.
    mn, mx = bounds([lo])
    c = (mn + mx) / 2
    lo.data.transform(mathutils.Matrix.Translation((-c.x, -c.y, -mn.z)))
    mn, mx = bounds([lo])
    os.makedirs(os.path.dirname(out), exist_ok=True)
    select_only([lo])
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True,
                              export_image_format="JPEG", export_jpeg_quality=88)
    d = mx - mn
    print("ASSET %s before=%d after=%d baked=%s dims=%.2fx%.2fx%.2f m" % (slug, before, tri_count([lo]), baked, d.x, d.y, d.z), flush=True)


argv = sys.argv[sys.argv.index("--") + 1:]
src_dir, out_dir, only = argv[0], argv[1], set(argv[2:])
for slug, cfg in CFG.items():
    if only and slug not in only:
        continue
    src = os.path.join(src_dir, slug + ".glb")
    if not os.path.exists(src):
        print("MISSING", slug, flush=True)
        continue
    try:
        process(src, os.path.join(out_dir, slug, slug + ".glb"), slug, cfg)
    except Exception as e:
        print("FAILED", slug, str(e)[:200], flush=True)
