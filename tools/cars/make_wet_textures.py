"""Bake the rain textures for cars (no external assets): tileable tangent-space normal maps (OpenGL, +Y) of water on a
surface, used as the detail layer of the paint, glass and tyre materials when it rains (CarBuilder.wetness).

  python3 tools/cars/make_wet_textures.py  ->  godot/assets/models/cars/wet_beads_normal.png   (beaded drops on wax)
                                               godot/assets/models/cars/wet_glass_normal.png   (drops + run-off streaks)

Each drop is a spherical cap: its normal tilts towards its rim, so it refracts and catches the sky like real water.
"""
import os
import numpy as np
from PIL import Image

N = 1024
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "godot", "assets", "models", "cars")
rng = np.random.default_rng(2027)


def caps(count, rmin, rmax, h=None, stretch=1.0):
    """Height field of `count` round drops (radius in px), tileable; overlapping drops merge (max)."""
    h = np.zeros((N, N)) if h is None else h
    for _ in range(count):
        r = rng.uniform(rmin, rmax) * (1.0 + rng.normal(0, 0.08))
        cx, cy = rng.uniform(0, N), rng.uniform(0, N)
        ry = r * stretch
        x0, x1 = int(cx - r) - 1, int(cx + r) + 2
        y0, y1 = int(cy - ry) - 1, int(cy + ry) + 2
        xs = np.arange(x0, x1); ys = np.arange(y0, y1)
        X, Y = np.meshgrid(xs, ys)
        d2 = ((X - cx) / r) ** 2 + ((Y - cy) / ry) ** 2
        cap = np.sqrt(np.clip(1.0 - d2, 0.0, 1.0)) * r * 0.55   # a bead sits high on a waxed coat
        h[np.ix_(ys % N, xs % N)] = np.maximum(h[np.ix_(ys % N, xs % N)], cap)
    return h


def streaks(count, h):
    """Run-off: thin vertical trails with a drop at the head (glass)."""
    for _ in range(count):
        x = rng.uniform(0, N); y = rng.uniform(0, N)
        length = rng.uniform(60, 260); w = rng.uniform(1.2, 2.6)
        ys = np.arange(int(y), int(y + length))
        wob = np.cumsum(rng.normal(0, 0.25, len(ys)))
        for i, yy in enumerate(ys):
            xx = x + wob[i]
            for dx in range(-3, 4):
                v = max(0.0, 1.0 - ((dx + (xx % 1)) / w) ** 2)
                if v > 0:
                    h[yy % N, int(xx + dx) % N] = max(h[yy % N, int(xx + dx) % N], v * w * 0.5)
        caps(1, 5, 9, h)   # (random head position: keeps the field tileable and natural)
    return h


def to_normal(h, k):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    nx, ny, nz = -dx * k, dy * k, np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return (np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5)


beads = caps(1100, 1.8, 4.0)
beads = caps(520, 4.0, 9.0, beads)
beads = caps(90, 9.0, 16.0, beads)
glass = caps(1800, 1.2, 3.5)
glass = caps(300, 3.5, 8.0, glass)
glass = streaks(140, glass)
os.makedirs(OUT, exist_ok=True)
Image.fromarray((to_normal(beads, 0.7) * 255).round().astype(np.uint8)).save(os.path.join(OUT, "wet_beads_normal.png"))
Image.fromarray((to_normal(glass, 0.9) * 255).round().astype(np.uint8)).save(os.path.join(OUT, "wet_glass_normal.png"))
print("wrote wet_beads_normal.png, wet_glass_normal.png (%d px)" % N)
