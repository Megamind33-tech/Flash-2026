"""Bake GRIDLINE's shared tyre material (no brand marks): albedo, tangent-space normal (OpenGL, +Y) and ORM
(R = ambient occlusion, G = roughness, B = metallic) PNGs, from one procedural height field.

  python3 tools/cars/make_tyre_textures.py   ->  godot/assets/models/cars/tyre_{albedo,normal,orm}.png

UV layout (matches the lathed tyre made by tools/cars/export_sketchfab_car.py):
  v: across the section, bead (0) -> sidewall -> shoulder -> tread -> shoulder -> sidewall -> bead (1)
  u: tread and shoulders (0.30 < v < 0.70): one texture width = TILE_M metres of tread (4 shoulder blocks), tiled;
     sidewalls: one texture width = once around the tyre, so the raised lettering (our own fictional mark, twice per
     side) appears like on a real tyre instead of every 20 cm.
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

N = 1024          # v (across the section)
NU = 2048         # u (around): the sidewall lettering needs the width
FONT = os.path.join(os.path.dirname(__file__), '..', '..', 'godot', 'assets', 'fonts', 'BarlowCondensed-ExtraBold.ttf')
TILE_M = 0.20
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "godot", "assets", "models", "cars")

# v landmarks (must match PROFILE in export_sketchfab_car.py)
BEAD = 0.06          # 0 .. BEAD: bead seat and rim protector
SIDE_END = 0.30      # sidewall
SHOULDER_END = 0.38  # shoulder blocks; tread is SHOULDER_END .. 1 - SHOULDER_END
GROOVES = [0.415, 0.47, 0.53, 0.585]
GROOVE_W = 0.011
BLOCKS = 4           # shoulder blocks per tile

u = (np.arange(NU) + 0.5) / NU
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
    acc = np.zeros((N, NU))
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


h = np.zeros((N, NU))
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
h -= lat_groove * reach * 0.5
# sidewall: smooth, a rim protector rib near the bead and two thin decorative rings; fine radial texture
h += side * (0.35 + 0.08 * np.sin((Vs - BEAD) / (SIDE_END - BEAD) * np.pi))
h += band(Vs, 0.085, 0.012, 0.012) * 0.12
h += band(Vs, 0.26, 0.003, 0.004) * 0.04
# bead seat
h += bead * (0.15 + 0.2 * smoothstep(0.0, BEAD, Vs))
# rubber grain everywhere
grain = tile_noise(96, 3)
# (no rubber grain in the height: under the race renderer's sharpening it glittered as speckle)

# raised sidewall lettering: GRIDLINE's own mark, twice per side. Image rows 0.70-0.94 are one sidewall (glTF flips
# v), rows 0.06-0.30 the other (drawn rotated 180 degrees: outward points the other way there). Letters are drawn at
# physical proportions for a ~2.1 m circumference and a ~7 cm sidewall.
def lettering():
    """Sidewall markings in band rows (row 0 = outer edge by the shoulder, last row = the bead). Physical sizes for a
    ~2.1 m circumference and ~7.5 cm of lettering band. Everything is GRIDLINE's own fictional marking."""
    W, H = NU, int(N * 0.24)
    CIRC, BAND = 2.1, 0.075
    img = Image.new("L", (W, H), 0)
    font = ImageFont.truetype(FONT, 300)
    def put(text, u0, r0, height_m, scale_x=1.0):
        bb = font.getbbox(text)
        t = Image.new("L", (bb[2] - bb[0] + 16, bb[3] - bb[1] + 16), 0)
        ImageDraw.Draw(t).text((8 - bb[0], 8 - bb[1]), text, fill=255, font=font)
        hpx = max(4, int(height_m / BAND * H))
        wpx = max(4, int(t.width / t.height * height_m / CIRC * W * scale_x))
        t = t.resize((wpx, hpx), Image.LANCZOS)
        img.paste(t, (int(u0 * W) % W, int(r0 * H)), t)
        return u0 + wpx / W
    def arrow(u0, r0, length_m, height_m):   # rotation arrow
        x0, y0 = int(u0 * W), int(r0 * H)
        l, hh = int(length_m / CIRC * W), int(height_m / BAND * H)
        d = ImageDraw.Draw(img)
        d.rectangle([x0, y0 + hh * 0.35, x0 + l * 0.75, y0 + hh * 0.65], fill=255)
        d.polygon([(x0 + l * 0.7, y0), (x0 + l, y0 + hh / 2), (x0 + l * 0.7, y0 + hh)], fill=255)
    for k in (0.0, 0.5):
        # outer row (by the shoulder): grades, construction
        put("TREADWEAR 280   TRACTION AA   TEMPERATURE A", 0.02 + k, 0.05, 0.0095)
        put("TUBELESS  RADIAL", 0.30 + k, 0.05, 0.0095)
        # main row: brand, model, size
        e = put("GRIDLINE", 0.03 + k, 0.24, 0.032)
        e = put("PRO R", e + 0.025, 0.33, 0.022)
        put("255/35 ZR19  96Y", e + 0.03, 0.38, 0.016)
        # inner row (by the bead): load / pressure, code, rotation
        put("MAX LOAD 710 KG (1565 LBS)   MAX PRESS 350 kPa (51 PSI)", 0.03 + k, 0.73, 0.009)
        put("DOT  GL27 XR4 2726", 0.27 + k, 0.73, 0.009)
        put("ROTATION", 0.37 + k, 0.73, 0.008)
        arrow(0.41 + k, 0.73, 0.06, 0.009)
    a = np.asarray(img, dtype=float) / 255.0
    # knurled ring just outside the rim protector: fine radial serrations, once around
    rows = np.arange(H) / H
    ring = ((rows > 0.88) & (rows < 0.94)).astype(float)[:, None]
    serr = (np.sin(np.arange(W) / W * 2 * np.pi * 720) > 0.2).astype(float)[None, :]
    a = np.maximum(a, ring * serr * 0.45)
    return a
L = lettering()
band = L.shape[0]
r_a = int(N * 0.70)                     # rows 0.70 .. 0.94: letters upright
LET = np.zeros((N, NU))   # letter mask, also used for albedo and roughness below
LET[r_a:r_a + band, :] = L
r_b = int(N * 0.06)                     # rows 0.06 .. 0.30: rotated 180 degrees
LET[r_b:r_b + band, :] = L[::-1, ::-1]
h += LET * 0.5

# normal map (OpenGL convention): slope scale tuned so grooves read at car-card distance without aliasing
dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
dy[0, :] = dy[1, :]; dy[-1, :] = dy[-2, :]
k = 5.0   # gentle: grooves read, the sidewall stays smooth (stronger read as crumpled rubber)
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
rough += (blur - h > 0.15) * 0.05 + (grain - 0.5) * 0.03
rough -= LET * 0.22   # raised letters are smoother (moulded, not worn): they catch the light
rough = np.clip(rough, 0.45, 1.0)

# albedo (sRGB): black rubber, tread lighter from wear and road dust, grooves darker
base = 34 * side + 33 * bead + 40 * shoulder + 43 * tread
base += (grain - 0.5) * 3
base *= 0.85 + 0.15 * ao
base += LET * 10
alb = np.clip(np.stack([base, base, base * 1.03], -1), 0, 255)

os.makedirs(OUT, exist_ok=True)
Image.fromarray(alb.astype(np.uint8)).save(os.path.join(OUT, "tyre_albedo.png"))
Image.fromarray((normal * 255).round().astype(np.uint8)).save(os.path.join(OUT, "tyre_normal.png"))
orm = np.stack([ao, rough, np.zeros_like(ao)], -1)
Image.fromarray((orm * 255).round().astype(np.uint8)).save(os.path.join(OUT, "tyre_orm.png"))
print("wrote tyre_albedo / tyre_normal / tyre_orm (%d px, %.2f m per tile)" % (N, TILE_M))
