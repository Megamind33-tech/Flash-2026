"""Bake GRIDLINE's shared tyre material (no brand marks): albedo, tangent-space normal (OpenGL, +Y) and ORM
(R = ambient occlusion, G = roughness, B = metallic) PNGs, from one procedural height field.

  python3 tools/cars/make_tyre_textures.py   ->  godot/assets/models/cars/tyre_{albedo,normal,orm}.png

UV layout (matches the lathed tyre made by tools/cars/export_sketchfab_car.py):
  u: around the circumference, one texture width = TILE_M metres of tread (4 shoulder blocks)
  v: across the section, bead (0) -> sidewall -> shoulder -> tread -> shoulder -> sidewall -> bead (1)
"""
import os
import numpy as np
from PIL import Image

N = 1024
TILE_M = 0.20
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "godot", "assets", "models", "cars")

# v landmarks (must match PROFILE in export_sketchfab_car.py)
BEAD = 0.06          # 0 .. BEAD: bead seat and rim protector
SIDE_END = 0.30      # sidewall
SHOULDER_END = 0.38  # shoulder blocks; tread is SHOULDER_END .. 1 - SHOULDER_END
GROOVES = [0.415, 0.47, 0.53, 0.585]
GROOVE_W = 0.011
BLOCKS = 4           # shoulder blocks per tile

u = (np.arange(N) + 0.5) / N
v = (np.arange(N) + 0.5) / N
U, V = np.meshgrid(u, v)          # rows = v, cols = u
Vs = np.minimum(V, 1.0 - V)       # symmetric section: distance from the nearer bead
rng = np.random.default_rng(27)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def band(x, centre, half, soft):
    """1 inside |x - centre| < half, soft edges."""
    d = np.abs(x - centre)
    return 1.0 - smoothstep(half, half + soft, d)


def tile_noise(scale, octaves=3):
    """Tileable value noise in u (wraps), smooth in v."""
    acc = np.zeros((N, N))
    amp = 1.0
    for o in range(octaves):
        cells = scale * 2 ** o
        g = rng.random((cells + 1, cells + 1))
        g[:, -1] = g[:, 0]
        x = U * cells
        y = V * cells
        xi, yi = np.floor(x).astype(int), np.floor(y).astype(int)
        xf, yf = x - xi, y - yi
        xf, yf = xf * xf * (3 - 2 * xf), yf * yf * (3 - 2 * yf)
        a, b = g[yi, xi], g[yi, (xi + 1) % (cells + 1)]
        c, d = g[(yi + 1) % (cells + 1), xi], g[(yi + 1) % (cells + 1), (xi + 1) % (cells + 1)]
        acc += amp * ((a * (1 - xf) + b * xf) * (1 - yf) + (c * (1 - xf) + d * xf) * yf)
        amp *= 0.5
    return acc / (2 - 2 ** (1 - octaves))


h = np.zeros((N, N))
tread = (Vs >= SHOULDER_END).astype(float)
shoulder = ((Vs >= SIDE_END) & (Vs < SHOULDER_END)).astype(float)
side = ((Vs >= BEAD) & (Vs < SIDE_END)).astype(float)
bead = (Vs < BEAD).astype(float)

# tread: flat crown cut by four straight circumferential grooves, slanted sipes between the inner grooves
h += tread * 1.0
for g in GROOVES:
    h -= band(V, g, GROOVE_W, 0.004) * 0.9
sipe_phase = (U * BLOCKS * 3 + (V - 0.5) * 2.2) % 1.0
sipes = band(sipe_phase, 0.5, 0.035, 0.02) * ((np.abs(V - 0.5) < 0.025) | ((np.abs(V - 0.5) > 0.045) & (np.abs(V - 0.5) < 0.11)))
h -= tread * sipes * 0.35
# shoulder: blocks separated by lateral grooves that open towards the sidewall
lat = (U * BLOCKS + 0.15 * smoothstep(SIDE_END, SHOULDER_END + 0.04, Vs)) % 1.0
lat_groove = band(lat, 0.5, 0.06, 0.025)
reach = smoothstep(SIDE_END - 0.01, SHOULDER_END + 0.035, Vs) * (Vs < SHOULDER_END + 0.04)
h += shoulder * (0.9 - 0.25 * smoothstep(SHOULDER_END - 0.02, SIDE_END, Vs))
h -= lat_groove * reach * 0.75
# sidewall: smooth, a rim protector rib near the bead and two thin decorative rings; fine radial texture
h += side * (0.35 + 0.08 * np.sin((Vs - BEAD) / (SIDE_END - BEAD) * np.pi))
h += band(Vs, 0.085, 0.012, 0.006) * 0.25
h += band(Vs, 0.235, 0.0025, 0.002) * 0.08 + band(Vs, 0.26, 0.0025, 0.002) * 0.08
h += side * (tile_noise(64, 2) - 0.5) * 0.02
# bead seat
h += bead * (0.15 + 0.2 * smoothstep(0.0, BEAD, Vs))
# rubber grain everywhere
grain = tile_noise(96, 3)
h += (grain - 0.5) * 0.025

# normal map (OpenGL convention): slope scale tuned so grooves read at car-card distance without aliasing
dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
dy[0, :] = dy[1, :]; dy[-1, :] = dy[-2, :]
k = 9.0
nx, ny, nz = -dx * k, dy * k, np.ones_like(h)
ln = np.sqrt(nx * nx + ny * ny + nz * nz)
normal = np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5

# ambient occlusion: cavities (below the local mean height) darken
blur = h.copy()
for _ in range(6):
    blur = (blur + np.roll(blur, 3, 0) + np.roll(blur, -3, 0) + np.roll(blur, 3, 1) + np.roll(blur, -3, 1)) / 5
ao = np.clip(1.0 - np.maximum(blur - h, 0) * 2.2, 0.45, 1.0)

# roughness: worn tread matte, sidewall satin, grooves dusty
rough = 0.72 * side + 0.8 * bead + 0.86 * shoulder + 0.9 * tread
rough += (blur - h > 0.15) * 0.06 + (grain - 0.5) * 0.06
rough = np.clip(rough, 0.55, 1.0)

# albedo (sRGB): black rubber, tread lighter from wear and road dust, grooves darker
base = 34 * side + 33 * bead + 40 * shoulder + 43 * tread
base += (grain - 0.5) * 6
base *= 0.75 + 0.25 * ao
alb = np.clip(np.stack([base, base, base * 1.03], -1), 0, 255)

os.makedirs(OUT, exist_ok=True)
Image.fromarray(alb.astype(np.uint8)).save(os.path.join(OUT, "tyre_albedo.png"))
Image.fromarray((normal * 255).round().astype(np.uint8)).save(os.path.join(OUT, "tyre_normal.png"))
orm = np.stack([ao, rough, np.zeros_like(ao)], -1)
Image.fromarray((orm * 255).round().astype(np.uint8)).save(os.path.join(OUT, "tyre_orm.png"))
print("wrote tyre_albedo / tyre_normal / tyre_orm (%d px, %.2f m per tile)" % (N, TILE_M))
