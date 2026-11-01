"""Lusaka venue upgrade: reshape the circuit inside its real streets and re-plan the generated frontage.

  python3 -I tools/cities/lusaka_venue.py

Input: tools/cities/base/lusaka.json (the OSM-derived city as build_cities.py wrote it; copied there on first run).
Output: godot/data/cities/lusaka.json.

1. Layout. The OSM route is eight near-90-degree corners joined by long straights (936 m without a corner). Street
   circuits fix this with temporary chicanes and re-profiled corners inside the existing carriageway. Edits:
   - two chicanes on the 936 m straight (a fast left-right flick and a slower bus-stop),
   - a sweeping kink on the 430 m straight after turn 1,
   - a chicane before the final corner onto the start straight.
   Each edit is a smooth lateral offset of the centreline. A site is used only if no OSM building comes within
   SAFE metres of the moved road; generated blocks are re-planned around the new line anyway.
2. Frontage. build_cities.py filled every gap with blocks at one fixed setback (11.5 m from the centreline on both
   sides, almost the whole lap): a corridor. The generated blocks are re-planned with Lusaka's real mix:
   one- and two-storey shops with verandas (kind "shop"), offices and flats (3-7 storeys, "office"), the odd tower,
   forecourts (petrol station, parking, kind "forecourt") with the building set far back, alleys and empty plots.
   Setbacks vary, so the street wall steps in and out. OSM buildings are never moved.
Deterministic (seeded). Prints the before/after measures used in docs/evidence/lusaka.
"""
import json, math, os, random, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.join(HERE, "base", "lusaka.json")
OUT = os.path.join(HERE, "..", "..", "godot", "data", "cities", "lusaka.json")
HW = 6.5
EDGE = HW + 0.6 + 4.8          # barrier + pavement outer edge from the centreline (city_world.gd)
SAFE = EDGE + 0.6              # nothing built closer than this to the (moved) centreline
STEP = 4.0

# (start metres along the lap, length, lateral amplitude m (+ = left of travel), shape)
EDITS = [
    (330.0, 230.0, 4.5, "sweep"),        # long sweeping kink after turn 1
    (930.0, 95.0, 6.0, "chicane"),       # fast flick on the 936 m straight
    (1380.0, 70.0, 6.5, "chicane"),      # slower bus-stop before the far corner (bends toward the open side)
    (2850.0, 80.0, 5.5, "chicane"),      # tightens the run onto the start straight
]


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def shape(kind, u):
    if kind == "sweep":
        return math.sin(math.pi * u) ** 2
    return smoothstep(0.0, 0.33, u) * (1.0 - smoothstep(0.67, 1.0, u))


def resample(pts, step):
    out = [pts[0]]
    carry = 0.0
    n = len(pts)
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        seg = math.dist(a, b)
        d = step - carry
        while d <= seg:
            t = d / seg
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
            d += step
        carry = seg - (d - step)
    return out[:-1] if math.dist(out[-1], out[0]) < step * 0.5 else out


def cum(pts):
    c = [0.0]
    for i in range(1, len(pts)):
        c.append(c[-1] + math.dist(pts[i - 1], pts[i]))
    return c


def normal(pts, i):
    a, b = pts[i - 1], pts[(i + 1) % len(pts)]
    tx, ty = b[0] - a[0], b[1] - a[1]
    l = math.hypot(tx, ty) or 1.0
    return (-ty / l, tx / l), (tx / l, ty / l)


def poly_of(flat):
    return [(flat[k], flat[k + 1]) for k in range(0, len(flat), 2)]


def seg_dist(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    l2 = dx * dx + dy * dy
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2))
    return math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy)


def point_in_poly(p, poly):
    x, y = p
    inside = False
    for i in range(len(poly)):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % len(poly)]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1 + 1e-12) + x1:
            inside = not inside
    return inside


class Grid:
    def __init__(self, pts, cell=25.0):
        self.cell, self.g = cell, {}
        for p in pts:
            self.g.setdefault((int(p[0] // cell), int(p[1] // cell)), []).append(p)

    def dist(self, q):
        gx, gy = int(q[0] // self.cell), int(q[1] // self.cell)
        best = 1e9
        for dx in (-2, -1, 0, 1, 2):
            for dy in (-2, -1, 0, 1, 2):
                for p in self.g.get((gx + dx, gy + dy), ()):
                    best = min(best, math.dist(p, q))
        return best


def turn_profile(pts):
    """Corners (> 6 degrees over 3 samples) and the longest straight, for the before/after report."""
    c = cum(pts)
    heads = [math.atan2(pts[(i + 1) % len(pts)][1] - pts[i][1], pts[(i + 1) % len(pts)][0] - pts[i][0]) for i in range(len(pts))]
    turning, last, longest = [], 0.0, 0.0
    for i in range(1, len(pts)):
        dh = math.degrees((heads[i] - heads[i - 3 if i >= 3 else 0] + math.pi) % (2 * math.pi) - math.pi)
        if abs(dh) > 6.0:
            longest = max(longest, c[i] - last)
            last = c[i]
            turning.append(c[i])
    longest = max(longest, c[-1] - last)
    return len(turning), longest


def main():
    if not os.path.exists(BASE):
        os.makedirs(os.path.dirname(BASE), exist_ok=True)
        shutil.copy(OUT, BASE)
    d = json.load(open(BASE))
    flat = d["circuit"]
    pts = resample([(flat[k], flat[k + 1]) for k in range(0, len(flat), 2)], STEP)
    osm = [poly_of(b[1]) for b in d["buildings"][: d["osm_buildings"]]]
    n0, long0 = turn_profile(pts)

    # 1. layout edits, each checked against the OSM footprints
    c = cum(pts)
    moved = list(pts)
    applied = []
    for s0, length, amp, kind in EDITS:
        trial = list(moved)
        for i, p in enumerate(pts):
            u = (c[i] - s0) / length
            if 0.0 <= u <= 1.0:
                (nx, ny), _ = normal(pts, i)
                off = amp * shape(kind, u)
                trial[i] = (moved[i][0] + nx * off, moved[i][1] + ny * off)
        seg = [trial[i] for i in range(len(pts)) if s0 - 20 <= c[i] <= s0 + length + 20]
        clear = min(min(seg_dist(q, poly[k], poly[(k + 1) % len(poly)]) for poly in osm for k in range(len(poly)) if abs(poly[0][0] - q[0]) < 200) for q in seg)
        if clear >= SAFE:
            moved = trial
            applied.append((s0, length, amp, kind, round(clear, 1)))
        else:
            print(f"skip {kind} at {s0:.0f} m: OSM building {clear:.1f} m from the moved road (needs {SAFE:.1f})")
    pts = moved
    n1, long1 = turn_profile(pts)
    track = Grid(pts)

    # 2. frontage: keep OSM buildings that still clear the moved road, re-plan the generated ones
    kept = []
    base_track = Grid(resample([(flat[k], flat[k + 1]) for k in range(0, len(flat), 2)], STEP))
    for b in d["buildings"][: d["osm_buildings"]]:
        poly = poly_of(b[1])
        was = min(base_track.dist(q) for q in poly)   # OSM buildings stay unless an edit moved the road toward them
        if min(track.dist(q) for q in poly) >= min(was, SAFE) - 0.3 and not any(point_in_poly(q, poly) for q in pts[::8]):
            kept.append([b[0], b[1], "osm"])
    occupied_polys = [poly_of(b[1]) for b in kept]
    open_polys = [poly_of(p) for p in d.get("parks", []) + d.get("water", [])]
    bgrid = {}

    def index(poly, bi):
        for q in poly:
            bgrid.setdefault((int(q[0] // 40), int(q[1] // 40)), set()).add(bi)

    for bi, poly in enumerate(occupied_polys):
        index(poly, bi)

    def occupied(q):
        gx, gy = int(q[0] // 40), int(q[1] // 40)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for bi in bgrid.get((gx + dx, gy + dy), ()):
                    if point_in_poly(q, occupied_polys[bi]):
                        return True
        return False

    def open_space(q):
        return any(point_in_poly(q, op) for op in open_polys if abs(op[0][0] - q[0]) < 900)

    # Event zones beside the start straight (lap distance 0 is the start line): the paddock (pit garages, race
    # control) on one side, a covered grandstand on the other. Generated blocks keep out; OSM buildings already
    # inside a zone stay and the engine shortens the structure around them.
    cl = cum(pts)
    lap = cl[-1] + math.dist(pts[-1], pts[0])
    PADDOCK = (-150.0, 70.0, 1)      # metres along the lap (wrapping), side (+1 left of travel)
    STAND = (-110.0, 40.0, -1)

    def in_zone(i, side):
        s_ = cl[i] if cl[i] < lap / 2 else cl[i] - lap
        return any(z[0] <= s_ <= z[1] and side == z[2] for z in (PADDOCK, STAND))

    rng = random.Random("lusaka-venue-2")
    generated = []
    kinds = {"shop": 0, "office": 0, "tower": 0, "forecourt": 0, "plot": 0}
    n = len(pts)
    for side in (1, -1):
        i = 0
        while i < n:
            if in_zone(i, side) or in_zone(min(n - 1, i + 6), side):
                i += 1
                continue
            a, b = pts[i], pts[(i + 4) % n]
            tx, ty = b[0] - a[0], b[1] - a[1]
            tl = math.hypot(tx, ty) or 1.0
            tx, ty = tx / tl, ty / tl
            nx, ny = -ty * side, tx * side
            r = rng.random()
            if r < 0.07:   # empty plot / car park: leave a gap
                kinds["plot"] += 1
                i += int(rng.uniform(16, 32) / STEP)
                continue
            if r < 0.17:
                kind, set_extra, width, depth, lv = "forecourt", rng.uniform(9, 16), rng.uniform(14, 26), rng.uniform(10, 16), 1
            elif r < 0.55:
                kind, set_extra, width, depth, lv = "shop", rng.choice([0.0, 0.0, 1.5, 3.0]), rng.uniform(7, 16), rng.uniform(9, 14), rng.choice([1, 1, 2, 2, 3])
            elif r < 0.94:
                kind, set_extra, width, depth, lv = "office", rng.choice([0.0, 2.0, 4.0, 6.0]), rng.uniform(12, 24), rng.uniform(12, 20), rng.randint(3, 7)
            else:
                kind, set_extra, width, depth, lv = "tower", rng.uniform(4, 10), rng.uniform(16, 24), rng.uniform(16, 24), rng.randint(10, 20)
            setback = SAFE + 0.2 + set_extra
            corners = [(a[0] + nx * setback, a[1] + ny * setback),
                       (a[0] + nx * setback + tx * width, a[1] + ny * setback + ty * width),
                       (a[0] + nx * (setback + depth) + tx * width, a[1] + ny * (setback + depth) + ty * width),
                       (a[0] + nx * (setback + depth), a[1] + ny * (setback + depth))]
            probe = (a[0] + nx * (setback + depth * 0.5) + tx * width * 0.5, a[1] + ny * (setback + depth * 0.5) + ty * width * 0.5)
            if not occupied(probe) and not open_space(probe) and all(track.dist(q) > SAFE for q in corners) and not any(occupied(q) for q in corners):
                h = round(lv * 3.2 + (1.4 if kind == "shop" else 1.0), 1)
                generated.append([h, [round(v, 1) for q in corners for v in q], kind])
                kinds[kind] += 1
                occupied_polys.append(corners)
                index(corners, len(occupied_polys) - 1)
                i += max(2, int(width / STEP)) + int(rng.choice([0.5, 1, 1, 2]) * 1.0)   # alleys 2-8 m
            else:
                i += 1

    # report: how far the street wall sits from the road, before and after
    def setbacks(blds):
        out = []
        for b in blds:
            poly = poly_of(b[1])
            out.append(min(track.dist(q) for q in poly))
        return out

    before = [11.5] * (len(d["buildings"]) - d["osm_buildings"])
    after = setbacks(generated)
    spread = lambda xs: (min(xs), sum(xs) / len(xs), max(xs)) if xs else (0, 0, 0)

    out = dict(d)
    out["circuit"] = [round(v, 1) for q in pts for v in q]
    out["length"] = round(cum(pts)[-1] + math.dist(pts[-1], pts[0]), 1)
    out["buildings"] = kept + generated
    out["osm_buildings"] = len(kept)
    out["layout"] = 2
    out["venue"] = {"edits": [list(e) for e in applied], "frontage": kinds, "paddock": list(PADDOCK), "grandstand": list(STAND)}
    json.dump(out, open(OUT, "w"), separators=(",", ":"))
    print(f"layout: {len(applied)}/{len(EDITS)} edits applied {applied}")
    print(f"corners (heading change > 6 deg / 12 m): {n0} -> {n1}; longest straight {long0:.0f} m -> {long1:.0f} m; lap {d['length']:.0f} m -> {out['length']:.0f} m")
    print(f"buildings: OSM kept {len(kept)}/{d['osm_buildings']}; generated {len(d['buildings']) - d['osm_buildings']} -> {len(generated)} {kinds}")
    print("generated setback min/mean/max m: before %.1f/%.1f/%.1f after %.1f/%.1f/%.1f" % (*spread(before), *spread(after)))


if __name__ == "__main__":
    main()
