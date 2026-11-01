# Usage: python3 tools/cars/glb_replace_image.py <car>.glb <image name> <new.png> [<image name> <new.png> ...]
"""Replace embedded images of a GLB (matched by glTF image name), so a scrubbed texture survives re-import.
Godot extracts embedded images as <glb stem>_<image name>.png; edit that PNG, then write it back with this.
Rebuilds the single binary buffer by re-packing every bufferView (4-byte aligned)."""
import json, struct, sys
path, pairs = sys.argv[1], sys.argv[2:]
repl = {pairs[i]: open(pairs[i + 1], "rb").read() for i in range(0, len(pairs), 2)}
d = open(path, "rb").read()
jlen = struct.unpack("<I", d[12:16])[0]
gj = json.loads(d[20:20 + jlen])
blen = struct.unpack("<I", d[20 + jlen:24 + jlen])[0]
binc = d[28 + jlen:28 + jlen + blen]
new_bytes = {}
for img in gj["images"]:
    if img.get("name") in repl:
        new_bytes[img["bufferView"]] = repl.pop(img["name"])
        img["mimeType"] = "image/png"
if repl:
    sys.exit(f"images not found: {sorted(repl)}; available: {[i.get('name') for i in gj['images']]}")
out = bytearray()
for i, bv in enumerate(gj["bufferViews"]):
    data = new_bytes.get(i, binc[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]])
    out += b"\0" * ((4 - len(out) % 4) % 4)
    bv["byteOffset"] = len(out)
    bv["byteLength"] = len(data)
    out += data
out += b"\0" * ((4 - len(out) % 4) % 4)
gj["buffers"][0]["byteLength"] = len(out)
js = json.dumps(gj, separators=(",", ":")).encode()
js += b" " * ((4 - len(js) % 4) % 4)
total = 12 + 8 + len(js) + 8 + len(out)
open(path, "wb").write(struct.pack("<III", 0x46546C67, 2, total) + struct.pack("<II", len(js), 0x4E4F534A) + js
                       + struct.pack("<II", len(out), 0x004E4942) + bytes(out))
print("replaced", len(new_bytes), "images in", path)
