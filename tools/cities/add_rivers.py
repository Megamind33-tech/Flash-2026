"""Add rivers the OSM tile parse missed (big rivers are multipolygon relations, not closed ways) and place real
landmarks at fixed sites.

  python3 tools/cities/add_rivers.py

London: the River Thames, from its OSM centreline (Overpass, waterway=river name="River Thames", ODbL) buffered to
its real width (about 230 m through Westminster), clipped to the map. Buildings, trees and parks inside the river are
removed. Writes `features` into the city JSON: Big Ben at its true position beside Westminster Bridge, and Tower
Bridge brought up-river into view of the start straight (the real bridge is 3.4 km east, outside the map; open-world
racers compress geography the same way).
"""
import json, math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "..", "godot", "data", "cities")
LINE = sys.argv[1] if len(sys.argv) > 1 else "/home/user/scratch/thames/thames_line.json"


def offset_polygon(line, half):
    left, right = [], []
    for i, p in enumerate(line):
        a = line[max(0, i - 1)]
        b = line[min(len(line) - 1, i + 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        n = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / n, dx / n
        left.append((p[0] + nx * half, p[1] + ny * half))
        right.append((p[0] - nx * half, p[1] - ny * half))
    return left + right[::-1]


def inside(p, poly):
    x, y = p
    c = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi:
            c = not c
        j = i
    return c


def segdist(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    t = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy + 1e-9)))
    return math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy)


def simplify(line, step):
    out = [line[0]]
    for p in line[1:]:
        if math.dist(p, out[-1]) >= step:
            out.append(p)
    return out


path = os.path.join(DATA, "london.json")
d = json.load(open(path))
raw = json.load(open(LINE))
line = [tuple(p) for p in raw if math.hypot(*p) < 1900.0]
line = simplify(line, 25.0)
half = 115.0
river = offset_polygon(line, half)
circuit = list(zip(d["circuit"][0::2], d["circuit"][1::2]))
gap = min(min(segdist(c, line[i], line[i + 1]) for i in range(len(line) - 1)) for c in circuit) - half - d["half_width"]
print(f"river: {len(river)} pts, nearest road edge to the water {gap:.0f} m")
assert gap > 6.0, "river would cover the circuit"


def centroid(flat):
    xs, ys = flat[0::2], flat[1::2]
    return (sum(xs) / len(xs), sum(ys) / len(ys))


nb = len(d["buildings"])
d["buildings"] = [b for b in d["buildings"] if not inside(centroid(b[1]), river)]
d["trees"] = [t for t in d["trees"] if not inside((t[0], t[1]), river)]
d["parks"] = [p for p in d["parks"] if not inside(centroid(p), river)]
print(f"removed {nb - len(d['buildings'])} buildings inside the river")
d["water"] = [w for w in d["water"] if not inside(centroid(w), river)]
d["water"].append([round(c, 1) for q in river for c in q])

# Tower Bridge: the river point best lined up with the start straight, 450-1100 m out, spanning the river.
s0, s1 = circuit[0], circuit[min(6, len(circuit) - 1)]
fwd = math.atan2(s1[1] - s0[1], s1[0] - s0[0])
best = None
for i in range(1, len(line) - 1):
    p = line[i]
    dist = math.dist(p, s0)
    if not 450.0 < dist < 1100.0:
        continue
    bearing = abs((math.atan2(p[1] - s0[1], p[0] - s0[0]) - fwd + math.pi) % (2 * math.pi) - math.pi)
    score = bearing + abs(dist - 700.0) / 2000.0
    if best is None or score < best[0]:
        best = (score, i, dist, math.degrees(bearing))
_, i, dist, bearing = best
a, b = line[i - 1], line[i + 1]
river_dir = math.atan2(b[1] - a[1], b[0] - a[0])
tb = line[i]
print(f"tower bridge at {tb[0]:.0f},{tb[1]:.0f}: {dist:.0f} m from the start, {bearing:.0f} deg off the straight")
d["features"] = [
    {"id": "big_ben", "pos": [28.0, -472.0], "yaw": 0.0, "clear": 14.0},
    {"id": "tower_bridge", "pos": [round(tb[0], 1), round(tb[1], 1)], "yaw": round(river_dir + math.pi / 2, 4), "clear": 0.0},
]
d["attribution"] = d["attribution"].rstrip(".") + "; River Thames centreline (c) OpenStreetMap contributors, ODbL 1.0"
json.dump(d, open(path, "w"), separators=(",", ":"))
print("wrote", path)
