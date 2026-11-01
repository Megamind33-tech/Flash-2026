# Usage: python3 tools/cars/glb_strip_uv.py <car>.glb  (then re-import in Godot)
"""Remove TEXCOORD_n (n >= 1) and COLOR_n attributes from every primitive of a GLB, in place.
Accessors become unused; the binary chunk is left as is."""
import json, struct, sys
p = sys.argv[1]
d = open(p, "rb").read()
magic, ver, total = struct.unpack("<III", d[:12])
jlen, jtype = struct.unpack("<II", d[12:20])
gj = json.loads(d[20:20 + jlen])
rest = d[20 + jlen:]
n = 0
for m in gj["meshes"]:
    for pr in m["primitives"]:
        for k in list(pr["attributes"]):
            if (k.startswith("TEXCOORD_") and k != "TEXCOORD_0") or k.startswith("COLOR_"):
                del pr["attributes"][k]; n += 1
js = json.dumps(gj, separators=(",", ":")).encode()
js += b" " * ((4 - len(js) % 4) % 4)
out = struct.pack("<III", magic, ver, 12 + 8 + len(js) + len(rest)) + struct.pack("<II", len(js), jtype) + js + rest
open(p, "wb").write(out)
print("removed", n, "attributes from", p)
