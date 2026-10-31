"""Microsoft Rocketbox avatars (MIT) -> posed, mobile-ready people for GRIDLINE (spectators, pedestrians, drivers).

  blender -b --python tools/people/build_people.py -- <rocketbox_repo> [avatar ...]

For each avatar it:
1. imports the avatar FBX and drives its skeleton with Rocketbox animation clips (same 'Bip01' rig);
2. bakes one static mesh per pose: cheer, clap, idle, seated driver;
3. decimates to the §4 pedestrian budget (<= 2,000 triangles) and keeps the UVs;
4. downsizes textures to 512 px (body, head, hair/eyelash opacity) and exports
   godot/assets/people/<avatar>_<pose>.glb with embedded textures.
Static posed meshes are cheaper than skinned characters on phones (MultiMesh-instanced in Godot).
"""
import bpy, os, sys, glob, math

args = sys.argv[sys.argv.index("--") + 1:]
RB = args[0]
ONLY = set(args[1:])
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "godot", "assets", "people")
TEX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_tex_portrait" if os.environ.get("PORTRAIT") == "1" else "_tex")   # intermediate, git-ignored
ANIM = os.path.join(RB, "Assets", "Animations", "all_animations_max_motextr_static")
POSES = {"cheer": ("cheer_01", 0.12), "clap": ("claphands_01", 0.5), "idle": ("idle_breathe_01", 0.2), "seated": ("sit_chair_breathe_01", 0.2)}
BUDGET = 2000
# PORTRAIT=1: one idle pose per avatar at full detail (lips and eyes intact) with 1024 px textures, written to
# godot/assets/people/portrait_src/ for tools/render_cards.gd only (not shipped; delete after rendering).
PORTRAIT = os.environ.get("PORTRAIT") == "1"
if PORTRAIT:
    POSES = {"idle": POSES["idle"]}
    BUDGET = 60000
    OUT = os.path.join(OUT, "portrait_src")
TEX_SIZE = 1024 if PORTRAIT else 512


def avatars():
    out = []
    for p in sorted(glob.glob(os.path.join(RB, "Assets", "Avatars", "*", "*", "Export", "*.fbx"))):
        name = os.path.basename(p)[:-4]
        if name.endswith("_facial") or (ONLY and name not in ONLY):
            continue
        out.append((name, p, os.path.dirname(os.path.dirname(p))))
    return out


def small_textures(name, folder):
    """512 px copies: body/head colour as JPG, opacity (hair, lashes) as RGBA PNG."""
    from PIL import Image  # Blender's Python has PIL? fall back to bpy images if not
    os.makedirs(TEX, exist_ok=True)
    res = {}
    for t in glob.glob(os.path.join(folder, "Textures", "*.tga")):
        b = os.path.basename(t).lower()
        key = "body" if "body_color" in b else "head" if "head_color" in b else "opacity" if "opacity_color" in b else None
        if key:
            im = Image.open(t)
            im = im.convert("RGBA" if key == "opacity" else "RGB").resize((TEX_SIZE, TEX_SIZE))
            dst = os.path.join(TEX, f"{name}_{key}.{'png' if key == 'opacity' else 'jpg'}")
            im.save(dst, quality=88) if key != "opacity" else im.save(dst)
            res[key] = dst
    return res


def make_mat(name, img, alpha=False):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(img)
    nt.links.new(tex.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = 0.75
    if alpha:
        nt.links.new(tex.outputs["Alpha"], p.inputs["Alpha"])
        m.blend_method = "CLIP"
        m.alpha_threshold = 0.5
    return m


def tris(me):
    return sum(len(p.vertices) - 2 for p in me.polygons)


def build(name, path, folder):
    tex = small_textures(name, folder)
    female = name.lower().startswith(("female", "f_")) or "_female_" in name.lower()
    for pose, (clip, at) in POSES.items():
        if pose == "seated":
            clip = "sit_chair_breathe_01"
            anim_file = os.path.join(ANIM, "m_" + clip + ".max.fbx")   # only a male seated clip exists; same rig
        else:
            anim_file = os.path.join(ANIM, ("f_" if female else "m_") + clip + ".max.fbx")
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.fbx(filepath=path)
        arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
        meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
        before = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=anim_file)
        new = [o for o in bpy.data.objects if o not in before]
        src = next((o for o in new if o.type == "ARMATURE" and o.animation_data and o.animation_data.action), None)
        if src is None:
            print("NOANIM", name, pose)
            continue
        act = src.animation_data.action
        # Rest poses differ between the avatar and the clip's skeleton, so drive every avatar bone from the
        # clip's bone in world space (constraints) instead of copying raw local channels.
        for pb in arm.pose.bones:
            if pb.name in src.pose.bones:
                c = pb.constraints.new("COPY_ROTATION")
                c.target, c.subtarget = src, pb.name
                if pb.name.endswith("Pelvis") or pb.parent is None:
                    c2 = pb.constraints.new("COPY_LOCATION")
                    c2.target, c2.subtarget = src, pb.name
        f0, f1 = act.frame_range
        bpy.context.scene.frame_set(int(f0 + (f1 - f0) * at))
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        baked = []
        for o in meshes:
            me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), depsgraph=dg)
            me.transform(o.matrix_world)
            for i, slot in enumerate(o.material_slots):
                n = (slot.material.name if slot.material else "").lower()
                key = "opacity" if "opacity" in n or "hair" in n or "lash" in n else "head" if "head" in n else "body"
                key = key if key in tex else "body"
                mname = f"{name}_{key}"
                me.materials[i] = bpy.data.materials.get(mname) or make_mat(mname, tex[key], key == "opacity")
            ob = bpy.data.objects.new(o.name + "_b", me)
            bpy.context.scene.collection.objects.link(ob)
            baked.append(ob)
        bpy.data.objects.remove(arm, do_unlink=True)
        for o in new:
            bpy.data.objects.remove(o, do_unlink=True)
        for o in meshes:
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.ops.object.select_all(action="DESELECT")
        for o in baked:
            o.select_set(True)
        bpy.context.view_layer.objects.active = baked[0]
        bpy.ops.object.join()
        body = bpy.context.view_layer.objects.active
        # Rocketbox is in centimetres: scale to metres, feet on the floor, centred.
        pts = [body.matrix_world @ v.co for v in body.data.vertices]
        h = max(p.z for p in pts) - min(p.z for p in pts)
        s = 0.01 if h > 50 else 1.0
        body.data.transform(__import__("mathutils").Matrix.Scale(s, 4))
        pts = [v.co for v in body.data.vertices]
        cx = (max(p.x for p in pts) + min(p.x for p in pts)) / 2
        cy = (max(p.y for p in pts) + min(p.y for p in pts)) / 2
        body.data.transform(__import__("mathutils").Matrix.Translation((-cx, -cy, -min(p.z for p in pts))))
        n0 = tris(body.data)
        if n0 > BUDGET:
            d = body.modifiers.new("dec", "DECIMATE")
            d.ratio = BUDGET * 0.95 / n0
            bpy.ops.object.modifier_apply(modifier="dec")
        os.makedirs(OUT, exist_ok=True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, f"{name}_{pose}.glb"), export_format="GLB",
                                  use_selection=True, export_image_format="AUTO", export_yup=True)
        hgt = max(v.co.z for v in body.data.vertices)
        print(f"PERSON {name}_{pose}: {n0} -> {tris(body.data)} tris, height {hgt:.2f} m", flush=True)


for a in avatars():
    build(*a)
