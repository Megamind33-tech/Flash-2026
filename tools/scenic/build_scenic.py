"""Procedural scenic circuits away from the cities: mountain passes, forest roads and a highway.

  python3 tools/scenic/build_scenic.py

Each track is a closed, star-shaped loop that cannot cross itself, laid over value-noise terrain. The road is
graded smoothly: its height is the terrain smoothed along the lap and clamped to a maximum gradient. The
terrain is cut and filled to the road, with banks beside it and mountains rising with distance. The script
also writes forest and scrub tree positions and roadside billboard sites to godot/data/scenic/<id>.json,
plus a preview image.
"""
import json, math, os, random
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "godot", "data", "scenic")

TRACKS = {
    "kafue_forest": dict(name="Kafue Forest Road", country="Zambia", kind="forest", R=520, amp=[0.18, 0.10, 0.07, 0.05, 0.035, 0.025],
                         relief=18, mountains=60, trees=0.9, hw=6.0, grade=0.05, seed=11),
    "rift_escarpment": dict(name="Rift Valley Escarpment", country="Kenya", kind="mountain", R=600, amp=[0.22, 0.14, 0.09, 0.06, 0.04, 0.03],
                            relief=55, mountains=260, trees=0.35, hw=6.0, grade=0.075, seed=23),
    "alpine_pass": dict(name="Schwarzwald Pass", country="Germany", kind="mountain", R=560, amp=[0.20, 0.15, 0.10, 0.07, 0.045, 0.03],
                        relief=60, mountains=320, trees=1.0, hw=5.8, grade=0.08, seed=37),
    "great_north_highway": dict(name="Great North Highway", country="Zambia", kind="highway", R=1050, amp=[0.30, 0.05, 0.03, 0.0, 0.0, 0.0],
                                relief=10, mountains=40, trees=0.25, hw=8.5, grade=0.03, seed=5),
}
CELL = 14.0
MARGIN = 700.0


def noise2(seed):
    rnd = random.Random(seed)
    waves = [(rnd.uniform(0.0008, 0.004) * (2 ** (k // 3)), rnd.uniform(0, math.tau), rnd.uniform(0, math.tau), 1.0 / (1 + k // 3))
             for k in range(9)]

    def h(x, y):
        s = 0.0
        for f, a, p, w in waves:
            s += w * math.sin((x * math.cos(a) + y * math.sin(a)) * f + p)
        return s / 3.0
    return h


def build(tid):
    cfg = TRACKS[tid]
    rnd = random.Random(cfg["seed"])
    ph = [rnd.uniform(0, math.tau) for _ in cfg["amp"]]
    pts = []
    n = 720
    for i in range(n):
        th = math.tau * i / n
        r = cfg["R"] * (1 + sum(a * math.sin((k + 2) * th + ph[k]) for k, a in enumerate(cfg["amp"])))
        if cfg["kind"] == "highway":   # stretched into a long fast oval
            pts.append((r * 1.9 * math.cos(th), r * 0.55 * math.sin(th)))
        else:
            pts.append((r * math.cos(th), r * math.sin(th)))
    # resample to 6 m
    res, acc = [pts[0]], 0.0
    for a, b in zip(pts, pts[1:] + pts[:1]):
        seg = math.dist(a, b)
        t = 6.0 - acc
        while t <= seg:
            res.append((a[0] + (b[0] - a[0]) * t / seg, a[1] + (b[1] - a[1]) * t / seg))
            t += 6.0
        acc = (acc + seg) % 6.0
    pts = res[:-1]
    L = sum(math.dist(a, b) for a, b in zip(pts, pts[1:] + pts[:1]))
    terr = noise2(cfg["seed"] * 7 + 1)
    # road heights: terrain sampled along the lap, smoothed, gradient-limited (both directions)
    h = [terr(x, y) * cfg["relief"] for x, y in pts]
    m = len(h)
    for _ in range(40):
        h = [(h[i - 2] + h[i - 1] + h[i] + h[(i + 1) % m] + h[(i + 2) % m]) / 5 for i in range(m)]
    step = 6.0 * cfg["grade"]
    for _ in range(4):
        for i in range(1, m * 2):
            a, b = (i - 1) % m, i % m
            h[b] = min(max(h[b], h[a] - step), h[a] + step)
        for i in range(m * 2, 0, -1):
            a, b = i % m, (i - 1) % m
            h[b] = min(max(h[b], h[a] - step), h[a] + step)
    # start line on the straightest stretch: lowest heading change over 240 m
    head = [math.atan2(pts[(i + 1) % m][1] - pts[i][1], pts[(i + 1) % m][0] - pts[i][0]) for i in range(m)]
    turn = [abs(math.remainder(head[(i + 1) % m] - head[i], math.tau)) for i in range(m)]
    best = min(range(m), key=lambda i: sum(turn[(i + k) % m] for k in range(40)))
    s = (best + 30) % m
    pts, h = pts[s:] + pts[:s], h[s:] + h[:s]
    # terrain grid with cut/fill toward the road and mountains rising with distance
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    x0, y0 = min(xs) - MARGIN, min(ys) - MARGIN
    nx, ny = int((max(xs) - x0 + MARGIN) / CELL) + 1, int((max(ys) - y0 + MARGIN) / CELL) + 1
    grid = {}
    for i, p in enumerate(pts):
        grid.setdefault((int(p[0] // 60), int(p[1] // 60)), []).append(i)

    def nearest(x, y):
        gx, gy = int(x // 60), int(y // 60)
        bd, bi = 1e9, -1
        for r in range(0, 12):
            for dx in range(-r, r + 1):
                for dy in range(-r, r + 1):
                    if max(abs(dx), abs(dy)) != r:
                        continue
                    for i in grid.get((gx + dx, gy + dy), ()):
                        d = math.dist(pts[i], (x, y))
                        if d < bd:
                            bd, bi = d, i
            if bi >= 0 and bd < (r - 1) * 60:
                break
        return bd, bi

    hw = cfg["hw"]
    hgrid = []
    dist = []
    for j in range(ny):
        for i in range(nx):
            x, y = x0 + i * CELL, y0 + j * CELL
            d, k = nearest(x, y)
            d = min(d, 1100.0)
            natural = terr(x, y) * cfg["relief"] + cfg["mountains"] * max(0.0, (d - 150) / 900.0) ** 1.4 * (0.6 + 0.4 * terr(y * 1.7, x * 1.3) + 0.4)
            road = h[k] - 0.35
            bank = min(1.0, max(0.0, (d - (hw + 3.0)) / 70.0))
            bank = bank * bank * (3 - 2 * bank)
            hgrid.append(round(road + (natural - road) * bank, 2))
            dist.append(d)
    # trees: forest away from the road, sparse scrub on mountains; never on the road or its verge
    trees = []
    density = cfg["trees"]
    for j in range(ny):
        for i in range(nx):
            d = dist[j * nx + i]
            if d < hw + 9 or d > 1100:
                continue
            p = density * (0.75 if d < 400 else 0.35) * (0.5 + 0.5 * (terr(i * 31.0, j * 17.0) + 1) / 2)
            if cfg["kind"] == "mountain":
                p *= max(0.0, 1.0 - (hgrid[j * nx + i] - min(h)) / 220.0)
            if rnd.random() < p:
                x, y = x0 + i * CELL + rnd.uniform(-6, 6), y0 + j * CELL + rnd.uniform(-6, 6)
                trees.append([round(x, 1), round(y, 1), hgrid[j * nx + i]])
    rnd.shuffle(trees)
    trees = trees[:9000]
    # billboards on the straights, facing the track, every ~350 m
    boards = []
    d_acc = 0.0
    for i in range(m):
        d_acc += 6.0
        if d_acc > 350 and turn[i] < 0.02:
            d_acc = 0.0
            a, b = pts[i], pts[(i + 1) % m]
            tx, ty = (b[0] - a[0]) / 6.0, (b[1] - a[1]) / 6.0
            side = 1 if (i // 7) % 2 else -1
            boards.append([round(a[0] - ty * side * (hw + 14), 1), round(a[1] + tx * side * (hw + 14), 1), round(h[i], 2),
                           round(math.atan2(-tx * side, ty * side), 3), (len(boards) * 5 + 3) % 16])
    data = dict(id=tid, kind="scenic", scenery=cfg["kind"], name=cfg["name"], country=cfg["country"], half_width=hw,
                length=round(L, 1), circuit=[round(c, 2) for k in range(0, m, 2) for c in (pts[k][0], pts[k][1], h[k])],
                terrain=dict(x0=x0, y0=y0, cell=CELL, nx=nx, ny=ny, h=hgrid), trees=trees, billboards=boards,
                climb=round(max(h) - min(h), 1))
    os.makedirs(OUT, exist_ok=True)
    json.dump(data, open(os.path.join(OUT, tid + ".json"), "w"), separators=(",", ":"))
    img = Image.new("RGB", (nx, ny))
    lo, hi = min(hgrid), max(hgrid)
    img.putdata([(int(60 + 150 * (v - lo) / (hi - lo + 1e-6)),) * 3 for v in hgrid])
    img = img.transpose(Image.FLIP_TOP_BOTTOM).resize((500, int(500 * ny / nx)))
    dr = ImageDraw.Draw(img)
    f = lambda x, y: ((x - x0) / CELL * 500 / nx, (1 - (y - y0) / CELL / ny) * 500 * ny / nx)
    for t in trees[:3000]:
        dr.point(f(t[0], t[1]), fill=(40, 120, 40))
    dr.line([f(*p) for p in pts] + [f(*pts[0])], fill=(230, 40, 40), width=3)
    dr.text((6, 6), f"{cfg['name']} {L:.0f} m climb {max(h) - min(h):.0f} m", fill=(255, 255, 0))
    os.makedirs(os.path.join(HERE, "previews"), exist_ok=True)
    img.save(os.path.join(HERE, "previews", tid + ".png"))
    print(f"{tid}: {L:.0f} m, climb {max(h) - min(h):.0f} m, terrain {nx}x{ny}, trees {len(trees)}, billboards {len(boards)}", flush=True)


if __name__ == "__main__":
    for t in TRACKS:
        build(t)
