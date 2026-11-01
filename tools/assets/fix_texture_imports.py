"""Texture import audit/fix for every texture used in 3D (not the 2D UI):
  - mipmaps on: without them, minified textures alias: sparkling asphalt, grainy walls and shimmer at speed, and
    anisotropic filtering has nothing to work with;
  - VRAM compression (ETC2/ASTC on Android, S3TC/BPTC on desktop) instead of lossless: 4-8x less GPU memory;
  - normal maps flagged as normal maps (correct compression for the two channels that matter).
  python3 -I tools/assets/fix_texture_imports.py [--check]     (--check: report only, exit 1 if anything is wrong)
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "..", "..", "godot", "assets")
SKIP_DIRS = ("ui", "fonts")          # 2D: no mipmaps needed, lossless keeps text and icons crisp
NORMAL = re.compile(r"(_normal|_nor(_gl)?|_nrm|normalgl|_n)\.(png|jpg|jpeg|webp)$", re.I)
# Largest dimension kept per texture: road, cars, adverts and the graffiti atlas keep 2048 (seen up close or carrying
# text); walls, ground, props and buildings, tiled every few metres, keep 1024 (no visible loss on a 720p-1080p phone,
# a quarter of the memory).
KEEP_2K = ("road/", "models/", "ads/", "world/graffiti", "ui/cars/")
# Real-building models are always seen from 12 m+ across the barriers; garage props are secondary detail: 768.
SMALL = ("buildings/real/", "garage/models/")
changed, ok, problems = 0, 0, []
check = "--check" in sys.argv
for root, dirs, files in os.walk(ASSETS):
    rel = os.path.relpath(root, ASSETS)
    if rel.split(os.sep)[0] in SKIP_DIRS:
        continue
    for f in files:
        if not f.endswith(".import") or f.endswith(".hdr.import") or f.endswith(".exr.import"):
            continue
        p = os.path.join(root, f)
        s = open(p).read()
        if 'importer="texture"' not in s:
            continue
        src = f[:-len(".import")]
        relp = os.path.relpath(p, ASSETS).replace(os.sep, "/")
        want = {"mipmaps/generate": "true", "compress/mode": "2",
                "process/size_limit": "768" if relp.startswith(SMALL) else ("2048" if relp.startswith(KEEP_2K) else "1024")}
        if NORMAL.search(src):
            want["compress/normal_map"] = "1"
        new = s
        for k, v in want.items():
            m = re.search(r"^%s=(.*)$" % re.escape(k), new, re.M)
            if m and m.group(1) != v:
                if k == "compress/mode" and m.group(1) in ("2", "3"):
                    continue   # already VRAM (2) or Basis (3)
                new = new[:m.start(1)] + v + new[m.end(1):]
        if new != s:
            problems.append(os.path.relpath(p, ASSETS))
            if not check:
                open(p, "w").write(new)
                changed += 1
        else:
            ok += 1
print(f"textures: {ok} already right, {len(problems)} {'need fixing' if check else 'fixed'}")
for x in problems[:12]:
    print("  ", x)
sys.exit(1 if check and problems else 0)
