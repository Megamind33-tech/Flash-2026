# Image clarity: measured sources and fixes

Method (`/home/user/scratch/clarity.sh`, metric in `clarity_metric.py`, both reproduced here): Lusaka, clear day,
Quality preset, fixed driver's-eye cameras at 1000 m (straight) and 240 m (turn 1); each view rendered twice with the
camera moved 5 cm. **grain** = mean |Laplacian| (pixel-scale speckle); **shimmer** = mean |high-pass(A) - high-pass(B)|
for the 5 cm move (aliased, unfiltered texture detail flickers; filtered detail barely changes). Lower is cleaner.

| Step (straight view) | road near grain / shimmer | road far grain / shimmer | buildings grain / shimmer |
|---|---|---|---|
| Before | 19.25 / 11.14 | 19.39 / 8.95 | 16.01 / 7.40 |
| 1. Mipmaps + VRAM compression on 274 3D textures | 13.46 / 8.12 | 6.74 / 1.46 | 11.40 / 4.62 |
| 2. Road shader: speckle soften, roughness floor, gentler normals, crack fade | 8.58 / 5.26 | 6.78 / 1.61 | 11.36 / 4.62 |
| 3. Blended catch fence, mip bias >= 0, anisotropy >= 2x (final) | 8.58 / 5.26 | 6.78 / 1.61 | 11.33 / 4.86 |
| Final with post-processing off | 8.75 / 5.36 | 6.89 / 1.63 | 11.56 / 4.84 |
| Final with post-processing at Ultra | 8.58 / 5.26 | 6.78 / 1.61 | 11.37 / 4.77 |

Findings
- **Main cause:** 274 of 585 textures used in 3D (road, walls, ground, fences, props) were imported without mipmaps
  (road textures also uncompressed). Unfiltered minification = sparkling asphalt, grainy walls, shimmer at speed;
  anisotropic filtering could not work. Fixed by `tools/assets/fix_texture_imports.py` (`--check` audits).
- **Asphalt:** the scan's bright aggregate and low pixel roughness sparkled under the sun; cracks too dark.
- **Catch fence:** cut-out wire texture without mipmaps broke into random dots over the buildings behind it.
- **Post-processing is not a grain source** (off vs Ultra within 3 %).
- Software renderer (lavapipe) on CPU: images are representative of filtering and shading; motion over many frames
  and device GPUs still need the on-device benchmark.
