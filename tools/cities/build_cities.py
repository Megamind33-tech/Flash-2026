"""Build GRIDLINE street circuits from real OpenStreetMap data (ODbL, (c) OpenStreetMap contributors).

  python3 tools/cities/build_cities.py [city ...]

For each city it:
1. Downloads the OSM map tiles (API 0.6) around the centre into tools/cities/osm_cache/. The cache is
   git-ignored and reused on later runs.
2. Finds a closed street circuit on the real road network: shortest paths through waypoints around the
   centre, preferring major roads and never reusing a street.
3. Rounds the corners to raceable radii and rejects layouts that touch themselves.
4. Keeps the real building footprints along the route and fills empty frontage with generated blocks in
   the city's height range.
5. Writes godot/data/cities/<id>.json and a top-down preview PNG to tools/cities/previews/.
"""
import heapq, json, math, os, random, sys, time, urllib.error, urllib.request
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "godot", "data", "cities")
CACHE = os.path.join(HERE, "osm_cache")
PREV = os.path.join(HERE, "previews")
UA = {"User-Agent": "GRIDLINE-racing-game-builder/0.5 (offline asset build)"}

# id: centre lat/lon, levels range for unknown buildings, tower share, target circuit length (m)
CITIES = {
    "lusaka":    dict(name="Lusaka", country="Zambia", ll=(-15.4180, 28.2830), levels=(1, 5), towers=0.04, target=2600),
    "kitwe":     dict(name="Kitwe", country="Zambia", ll=(-12.8100, 28.2130), levels=(1, 3), towers=0.0, target=2400),
    "nairobi":   dict(name="Nairobi", country="Kenya", ll=(-1.2850, 36.8200), levels=(3, 10), towers=0.18, target=2600),
    "cairo":     dict(name="Cairo", country="Egypt", ll=(30.0470, 31.2390), levels=(5, 11), towers=0.06, target=2800),
    "mogadishu": dict(name="Mogadishu", country="Somalia", ll=(2.0400, 45.3350), levels=(1, 4), towers=0.0, target=2400),
    "london":    dict(name="London", country="United Kingdom", ll=(51.5050, -0.1250), levels=(4, 7), towers=0.05, target=2600),
    "berlin":    dict(name="Berlin", country="Germany", ll=(52.5160, 13.3850), levels=(4, 6), towers=0.03, target=2800),
}
CLASS_COST = {"motorway": 3.0, "trunk": 1.0, "primary": 1.0, "secondary": 1.15, "tertiary": 1.4,
              "unclassified": 2.2, "residential": 2.6, "living_street": 6.0, "service": 8.0}
ROAD_WIDTH = {"motorway": 16, "trunk": 14, "primary": 12, "secondary": 10, "tertiary": 9, "unclassified": 7,
              "residential": 7, "living_street": 5, "service": 4.5, "pedestrian": 6}
HW = 6.5           # circuit half width (m)
SIDEWALK = 4.5     # barrier + pavement between road edge and building line
TILE = 0.0055      # deg per OSM tile request


def fetch(cid, lat0, lon0, n=3):
    os.makedirs(CACHE, exist_ok=True)
    paths = []
    for i in range(n):
        for j in range(n):
            la = lat0 + (i - (n - 1) / 2) * TILE
            lo = lon0 + (j - (n - 1) / 2) * TILE / max(0.3, math.cos(math.radians(lat0)))
            dlo = TILE / max(0.3, math.cos(math.radians(lat0)))
            p = os.path.join(CACHE, f"{cid}_{i}{j}.osm")
            if not os.path.exists(p):
                time.sleep(2.0)   # be gentle with the public OSM API (it returns 509 when hammered)
                bbox = f"{lo - dlo / 2:.5f},{la - TILE / 2:.5f},{lo + dlo / 2:.5f},{la + TILE / 2:.5f}"
                for attempt in range(6):
                    try:
                        data = urllib.request.urlopen(urllib.request.Request(
                            "https://api.openstreetmap.org/api/0.6/map?bbox=" + bbox, headers=UA), timeout=180).read()
                        break
                    except urllib.error.HTTPError as e:
                        if e.code != 509 or attempt == 5:
                            raise
                        time.sleep(30 * (attempt + 1))
                open(p, "wb").write(data)
            paths.append(p)
    return paths


def parse(paths, lat0, lon0):
    kx = math.cos(math.radians(lat0)) * 111320.0
    ky = 110540.0
    nodes, ways, trees = {}, {}, []
    for p in paths:
        for _, el in ET.iterparse(p):
            if el.tag == "node":
                nid = int(el.get("id"))
                xy = ((float(el.get("lon")) - lon0) * kx, (float(el.get("lat")) - lat0) * ky)
                nodes[nid] = xy
                if any(t.get("k") == "natural" and t.get("v") == "tree" for t in el.findall("tag")):
                    trees.append(xy)
                el.clear()
            elif el.tag == "way":
                wid = int(el.get("id"))
                if wid not in ways:
                    ways[wid] = ([int(nd.get("ref")) for nd in el.findall("nd")], {t.get("k"): t.get("v") for t in el.findall("tag")})
                el.clear()
    return nodes, ways, trees


def dijkstra(adj, src, dst, banned, cost_mult):
    dist = {src: 0.0}
    prev = {}
    pq = [(0.0, src)]
    while pq:
        d, u = heapq.heappop(pq)
        if u == dst:
            break
        if d > dist.get(u, 1e18):
            continue
        for v, w, eid in adj.get(u, ()):
            if v in banned and v != dst:
                continue
            nd = d + w * cost_mult.get(eid, 1.0)
            if nd < dist.get(v, 1e18):
                dist[v] = nd
                prev[v] = (u, eid)
                heapq.heappush(pq, (nd, v))
    if dst not in dist:
        return None
    path, edges = [dst], []
    while path[-1] != src:
        u, eid = prev[path[-1]]
        edges.append(eid)
        path.append(u)
    return path[::-1], edges[::-1]


def resample(pts, step):
    out = [pts[0]]
    acc = 0.0
    for a, b in zip(pts, pts[1:] + pts[:1]):
        seg = math.dist(a, b)
        t = step - acc
        while t <= seg:
            out.append((a[0] + (b[0] - a[0]) * t / seg, a[1] + (b[1] - a[1]) * t / seg))
            t += step
        acc = (acc + seg) % step if seg > 0 else acc
    return out[:-1] if math.dist(out[0], out[-1]) < step * 0.5 else out


def smooth(pts, passes, k=3):
    n = len(pts)
    for _ in range(passes):
        pts = [(sum(pts[(i + j) % n][0] for j in range(-k, k + 1)) / (2 * k + 1),
                sum(pts[(i + j) % n][1] for j in range(-k, k + 1)) / (2 * k + 1)) for i in range(n)]
    return pts


def length(pts):
    return sum(math.dist(a, b) for a, b in zip(pts, pts[1:] + pts[:1]))


def self_clear(pts, step, min_gap):
    """True if no two parts of the loop more than 70 m apart along the track come closer than min_gap."""
    n = len(pts)
    grid = {}
    for i, p in enumerate(pts):
        grid.setdefault((int(p[0] // 30), int(p[1] // 30)), []).append(i)
    sep = int(70 / step)
    for i, p in enumerate(pts):
        gx, gy = int(p[0] // 30), int(p[1] // 30)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for j in grid.get((gx + dx, gy + dy), ()):
                    d = abs(i - j)
                    if min(d, n - d) > sep and math.dist(p, pts[j]) < min_gap:
                        return False
    return True


def min_radius(pts, span=3):
    n = len(pts)
    best = 1e9
    for i in range(n):
        a, b, c = pts[i - span], pts[i], pts[(i + span) % n]
        ab, bc, ac = math.dist(a, b), math.dist(b, c), math.dist(a, c)
        cross = abs((b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]))
        if cross > 1e-6:
            best = min(best, ab * bc * ac / (2 * cross))
    return best


def find_circuit(cfg, nodes, ways):
    adj, eclass, major_nodes, emid = {}, {}, set(), {}
    eid = 0
    for wid, (nds, tags) in ways.items():
        hw = tags.get("highway")
        if hw not in CLASS_COST or tags.get("area") == "yes":
            continue
        for a, b in zip(nds, nds[1:]):
            if a not in nodes or b not in nodes:
                continue
            w = math.dist(nodes[a], nodes[b]) * CLASS_COST[hw]
            adj.setdefault(a, []).append((b, w, eid))
            adj.setdefault(b, []).append((a, w, eid))
            eclass[eid] = hw
            emid[eid] = ((nodes[a][0] + nodes[b][0]) / 2, (nodes[a][1] + nodes[b][1]) / 2)
            eid += 1
            if hw in ("trunk", "primary", "secondary", "tertiary"):
                major_nodes.update((a, b))
    cand = [n for n in major_nodes if len(adj.get(n, ())) >= 2] or list(adj)
    egrid = {}
    for e, m in emid.items():
        egrid.setdefault((int(m[0] // 40), int(m[1] // 40)), []).append(e)

    def near_edges(path):
        """Edges within 40 m of a used path (parallel carriageways, service roads) - avoid running back alongside."""
        out = set()
        for n in path:
            x, y = nodes[n]
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    for e in egrid.get((int(x // 40) + dx, int(y // 40) + dy), ()):
                        if math.dist(emid[e], (x, y)) < 40:
                            out.add(e)
        return out

    best = None
    for K in (3, 4, 5, 6):
        for R in (cfg["target"] / 8.0, cfg["target"] / 7.0, cfg["target"] / 6.0, cfg["target"] / 5.2, cfg["target"] / 4.6):
            for rot in range(0, 90, 15):
                wps = []
                for k in range(K):
                    ang = math.radians(rot + k * 360.0 / K)
                    tgt = (R * math.cos(ang), R * math.sin(ang))
                    wps.append(min(cand, key=lambda n: math.dist(nodes[n], tgt)))
                if len(set(wps)) < K:
                    continue
                banned, mult, route, used = set(), {}, [wps[0]], []
                ok = True
                for a, b in zip(wps, wps[1:] + wps[:1]):
                    r = dijkstra(adj, a, b, banned - {b, wps[0]}, mult)
                    if r is None:
                        ok = False
                        break
                    path, edges = r
                    route += path[1:]
                    used += edges
                    banned.update(path[1:-1])
                    for e in near_edges(path):
                        mult[e] = max(mult.get(e, 1.0), 25.0)
                    for e in edges:
                        mult[e] = 60.0
                if not ok or route[-1] != route[0]:
                    continue
                route = route[:-1]
                if len(set(route)) != len(route):
                    continue
                raw = [nodes[n] for n in route]
                L = length(raw)
                if not (0.6 * cfg["target"] < L < 1.6 * cfg["target"]):
                    continue
                pts = smooth(resample(raw, 4.0), 6, 3)
                pts = resample(pts, 4.0)
                if not self_clear(pts, 4.0, 2 * HW + 3):
                    continue
                rad = min_radius(pts)
                major = sum(1 for e in used if eclass[e] in ("trunk", "primary", "secondary")) / max(1, len(used))
                score = abs(length(pts) - cfg["target"]) / 1000.0 + (1.0 - major) * 1.5 + (0.8 if rad < 12 else 0.0)
                if best is None or score < best[0]:
                    best = (score, pts, route, major, rad)
    if best is None:
        raise RuntimeError("no valid circuit found")
    return best


def start_index(pts):
    """Start line 75 % along the straightest 300 m stretch, so the grid sits on a straight."""
    n = len(pts)
    span = 75   # 300 m at 4 m spacing
    heading = [math.atan2(pts[(i + 1) % n][1] - pts[i][1], pts[(i + 1) % n][0] - pts[i][0]) for i in range(n)]
    def turn(i):
        return abs(math.remainder(heading[(i + 1) % n] - heading[i], math.tau))
    best_i, best_t = 0, 1e9
    for i in range(n):
        t = sum(turn((i + k) % n) for k in range(span))
        if t < best_t:
            best_i, best_t = i, t
    return (best_i + int(span * 0.75)) % n


def point_in_poly(p, poly):
    x, y = p
    inside = False
    for (x1, y1), (x2, y2) in zip(poly, poly[1:] + poly[:1]):
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / ((y2 - y1) or 1e-9) + x1:
            inside = not inside
    return inside


def build(cid):
    cfg = CITIES[cid]
    lat0, lon0 = cfg["ll"]
    nodes, ways, trees = parse(fetch(cid, lat0, lon0), lat0, lon0)
    score, pts, route, major, rad = find_circuit(cfg, nodes, ways)
    s = start_index(pts)
    pts = pts[s:] + pts[:s]
    rng = random.Random(cid)
    # spatial index of the circuit for distance queries
    grid = {}
    for i, p in enumerate(pts):
        grid.setdefault((int(p[0] // 25), int(p[1] // 25)), []).append(p)

    def dist_track(q):
        gx, gy = int(q[0] // 25), int(q[1] // 25)
        best = 1e9
        for dx in (-2, -1, 0, 1, 2):
            for dy in (-2, -1, 0, 1, 2):
                for p in grid.get((gx + dx, gy + dy), ()):
                    best = min(best, math.dist(p, q))
        return best

    route_set = set(route)
    buildings, roads, parks, water = [], [], [], []
    lo, hi = cfg["levels"]
    for wid, (nds, tags) in ways.items():
        poly = [nodes[n] for n in nds if n in nodes]
        if len(poly) < 3:
            continue
        if "building" in tags and nds[0] == nds[-1]:
            poly = poly[:-1]
            dmin = min(dist_track(q) for q in poly)
            if dmin < HW + SIDEWALK - 0.5 or dmin > 320:
                continue
            if any(point_in_poly(q, poly) for q in pts[::10]):
                continue
            h = None
            try:
                h = float(tags.get("height", "").replace("m", "").strip())
            except ValueError:
                pass
            if not h:
                try:
                    h = float(tags.get("building:levels", "")) * 3.2 + 1.0
                except ValueError:
                    h = None
            if not h:
                lv = rng.randint(lo, hi)
                if rng.random() < cfg["towers"]:
                    lv = rng.randint(12, 28)
                h = lv * 3.2 + 1.0
            buildings.append([round(dmin, 1), round(h, 1), [round(c, 1) for q in poly for c in q]])
        elif tags.get("highway") in ROAD_WIDTH and not set(nds) <= route_set:
            if min(dist_track(q) for q in poly) < 450:
                roads.append([ROAD_WIDTH[tags["highway"]], [round(c, 1) for q in poly for c in q]])
        elif (tags.get("leisure") in ("park", "garden") or tags.get("landuse") in ("grass", "recreation_ground", "village_green")) and nds[0] == nds[-1]:
            parks.append([round(c, 1) for q in poly[:-1] for c in q])
        elif (tags.get("natural") == "water" or tags.get("waterway") == "riverbank" or tags.get("water")) and nds[0] == nds[-1]:
            water.append([round(c, 1) for q in poly[:-1] for c in q])
    buildings.sort(key=lambda b: b[0])
    buildings = buildings[:1600]
    real = len(buildings)
    # Generated frontage where OSM has no buildings: blocks set back behind the pavement, each side.
    polys = [[(b[2][k], b[2][k + 1]) for k in range(0, len(b[2]), 2)] for b in buildings]
    bgrid = {}
    for bi, poly in enumerate(polys):
        for q in poly:
            bgrid.setdefault((int(q[0] // 40), int(q[1] // 40)), set()).add(bi)

    def occupied(q):
        gx, gy = int(q[0] // 40), int(q[1] // 40)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for bi in bgrid.get((gx + dx, gy + dy), ()):
                    if point_in_poly(q, polys[bi]):
                        return True
        return False

    open_polys = [[(p[k], p[k + 1]) for k in range(0, len(p), 2)] for p in parks + water]

    def open_space(q):
        return any(point_in_poly(q, op) for op in open_polys if abs(op[0][0] - q[0]) < 900)

    n = len(pts)
    for side in (1, -1):
        i = 0
        while i < n:
            a, b = pts[i], pts[(i + 3) % n]
            tx, ty = b[0] - a[0], b[1] - a[1]
            tl = math.hypot(tx, ty) or 1
            tx, ty = tx / tl, ty / tl
            nx, ny = -ty * side, tx * side
            setback = HW + SIDEWALK + 0.5
            probe = (a[0] + nx * (setback + 6), a[1] + ny * (setback + 6))
            width = rng.uniform(9, 22)
            depth = rng.uniform(10, 18)
            corners = [(a[0] + nx * setback, a[1] + ny * setback),
                       (a[0] + nx * setback + tx * width, a[1] + ny * setback + ty * width),
                       (a[0] + nx * (setback + depth) + tx * width, a[1] + ny * (setback + depth) + ty * width),
                       (a[0] + nx * (setback + depth), a[1] + ny * (setback + depth))]
            step = max(2, int(width / 4.0))
            if not occupied(probe) and not open_space(probe) and all(dist_track(c) > setback - 0.6 for c in corners) and \
                    not any(occupied(c) for c in corners):
                lv = rng.randint(lo, hi)
                if rng.random() < cfg["towers"] * 0.5:
                    lv = rng.randint(10, 22)
                buildings.append([round(setback, 1), round(lv * 3.2 + 1.0, 1), [round(c, 1) for q in corners for c in q]])
                polys.append(corners)
                for q in corners:
                    bgrid.setdefault((int(q[0] // 40), int(q[1] // 40)), set()).add(len(polys) - 1)
                i += step + 1   # 1 sample (4 m) alley between generated blocks
            else:
                i += 1
    data = dict(id=cid, name=cfg["name"], country=cfg["country"], centre=list(cfg["ll"]), half_width=HW,
                length=round(length(pts), 1), min_radius=round(rad, 1), major_share=round(major, 2),
                circuit=[round(c, 1) for q in pts[::3] for c in q], buildings=[b[1:] for b in buildings],
                osm_buildings=real, roads=roads, parks=parks, water=water,
                trees=[[round(t[0], 1), round(t[1], 1)] for t in trees if dist_track(t) > HW + 3 and dist_track(t) < 300],
                attribution="Street layout and buildings (c) OpenStreetMap contributors, ODbL 1.0")
    os.makedirs(OUT, exist_ok=True)
    json.dump(data, open(os.path.join(OUT, cid + ".json"), "w"), separators=(",", ":"))
    preview(data)
    print(f"{cid}: circuit {data['length']:.0f} m, min radius {rad:.0f} m, major roads {major:.0%}, "
          f"buildings {real} OSM + {len(buildings) - real} generated, roads {len(roads)}, parks {len(parks)}, water {len(water)}", flush=True)


def preview(d):
    os.makedirs(PREV, exist_ok=True)
    S, R = 700, 900.0
    img = Image.new("RGB", (S, S), (40, 42, 40))
    dr = ImageDraw.Draw(img)
    f = lambda x, y: (S / 2 + x / R * S / 2, S / 2 - y / R * S / 2)
    for w in d["water"]:
        dr.polygon([f(w[k], w[k + 1]) for k in range(0, len(w), 2)], fill=(40, 70, 110))
    for p in d["parks"]:
        dr.polygon([f(p[k], p[k + 1]) for k in range(0, len(p), 2)], fill=(50, 90, 50))
    for wdt, r in d["roads"]:
        dr.line([f(r[k], r[k + 1]) for k in range(0, len(r), 2)], fill=(90, 90, 90), width=max(1, int(wdt / R * S / 2)))
    for i, (h, b) in enumerate(d["buildings"]):
        dr.polygon([f(b[k], b[k + 1]) for k in range(0, len(b), 2)], fill=(170, 160, 150) if i < d["osm_buildings"] else (200, 140, 90))
    c = d["circuit"]
    dr.line([f(c[k], c[k + 1]) for k in range(0, len(c), 2)] + [f(c[0], c[1])], fill=(230, 40, 40), width=4)
    dr.ellipse([f(c[0], c[1])[0] - 6, f(c[0], c[1])[1] - 6, f(c[0], c[1])[0] + 6, f(c[0], c[1])[1] + 6], fill=(255, 255, 255))
    dr.text((8, 8), f"{d['name']}, {d['country']}  {d['length']:.0f} m", fill=(255, 255, 255))
    img.save(os.path.join(PREV, d["id"] + ".png"))


if __name__ == "__main__":
    for cid in (sys.argv[1:] or CITIES):
        try:
            build(cid)
        except Exception as e:
            print(f"{cid}: FAILED {e}", flush=True)
