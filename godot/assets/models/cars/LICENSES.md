# Car models: asset manifest and licence record

All five race cars are Sketchfab downloads with a commercial-use licence: CC BY 4.0, "author must be credited;
commercial use is allowed". They were downloaded on 2026-11-01 through the Sketchfab download API in glTF format.
The original licence files are in `tools/cars/licences/sketchfab/`.

## Source and attribution

| In game | File | Source model (title, URL) | Author | Licence |
|---|---|---|---|---|
| Arden CS Coupé (GT4) | `arden_v8.glb` | "BMW m4 CSL 2023" https://sketchfab.com/3d-models/bmw-m4-csl-2023-26d05968e63b4fc28205cbb9abb0ea41 | Black Snow (https://sketchfab.com/BlackSnow02) | CC BY 4.0 |
| Arden GT3 R (GT3) | `arden_gt3.glb` | "Porsche GT3 RS" https://sketchfab.com/3d-models/porsche-gt3-rs-e738eae819c34d19a31dd066c45e0f3d | Black Snow (https://sketchfab.com/BlackSnow02) | CC BY 4.0 |
| Ravenna Ibrido (Hypercar) | `ravenna_hybrid.glb` | "Mclaren P1 \| www.vecarz.com" https://sketchfab.com/3d-models/mclaren-p1-wwwvecarzcom-adae2edc721e4ce7b31c1d06a581e30a | vecarz (https://sketchfab.com/heynic) | CC BY 4.0 |
| Solano GT-LM (GT1) | `solano_concept.glb` | "2006 \| Ford GT LM Spec ll Test Car" https://sketchfab.com/3d-models/2006-ford-gt-lm-spec-ll-test-car-dd6c3effdb1e43ecadace447ccbda68d | kevin (ケビン) (https://sketchfab.com/sohyalebret) | CC BY 4.0 |
| Vesta Evo II (Touring) | `elektra_egt.glb` | "[FREE] BMW M3 E30" https://sketchfab.com/3d-models/free-bmw-m3-e30-ac3c7013434e403e8faff87948caf422 | Martin Trafas (https://sketchfab.com/Bexxie) | CC BY 4.0 |

**Required credit line** (in-game at Settings → Credits, and to be repeated in the store listing): *"<title>" by
<author>, licensed under CC BY 4.0, modified for GRIDLINE.*

## Changes made (CC BY requires stating them)

Each model was converted by `tools/cars/export_sketchfab_car.py` (headless Blender 4.0.2). Before conversion, the
textures were scrubbed in a working copy; the downloads themselves are kept unmodified.

**Brand and identity removal**
- Removed maker badges, crests, roundels, scripts and model lettering, both as geometry and as decal materials:
  - Arden CS: roundel material.
  - Arden GT3 R: crest and side-skirt lettering (the "symbols" decal sheets).
  - Ravenna: script and model badges ("Details").
  - Solano: oval badge sheet and sill lettering.
  - Vesta: emblems and caliper logo plates.
- Real sponsor liveries replaced by GRIDLINE's own paint: Solano's racing livery sheet. The Supra GT300 candidate's
  livery was the same situation; that model was rejected, see below.
- Tyre-sidewall brand lettering removed:
  - Solano: inpainted.
  - Vesta: the normal-map lettering bands flattened.
- Vesta: the rim centre-cap roundel blanked.

**Paint, glass and lamps**
- The body colour, glass and brake lamps are mapped to GRIDLINE's runtime slots (`GL_paint`, `GL_glass`,
  `GL_tail`). On a shared lamp material, the front half becomes `GL_amber`, so the front indicators never light up
  as brake lamps.
- Every other material keeps the author's textures (`KEEP_*`): tyre tread and sidewall normal maps, rims, brake
  discs, light lenses, carbon and interior.

**Geometry**
- Oriented with the front at Godot +Z and scaled to real lengths.
- Tyre contact patch at y = 0; the four wheels split out with hub pivots. Brake calipers stay on the body, so they
  don't spin.
- Radio masts removed.

**Mobile reduction**
- The painted shell and everything lying against it is kept at full detail. Decimating these layered body panels
  tore the paint into blotches, so it is never done.
- Hidden parts (interior, engine bay, underbody, suspension) are decimated.
- Textures limited to 1024 px. Godot generates the lower LODs on import.

## Triangle counts (LOD0, hero car)

| Car | Body | Wheels (4) | Total |
|---|---|---|---|
| Solano GT-LM | 32.7k | 11.2k | 43.9k |
| Ravenna Ibrido | 45.8k | 11.1k | 56.9k |
| Vesta Evo II | 67.2k | 10.5k | 77.7k |
| Arden CS Coupé | 65.4k | 12.6k | 77.9k |
| Arden GT3 R | 88.7k | 11.4k | 100.1k |

Opponents use Godot's automatic mesh LODs with a stronger LOD bias (`race.gd`: `lod_bias = 0.35`).

## Rejected candidates (for the record)

- **Toyota GR Supra GT300 (vecarz, CC BY 4.0).** The exterior is built from stacked textured layers carrying the
  real Toyota, Denso, Bosch and Shell livery. It cannot be reduced below about 200k triangles without the layers
  tearing.
- **BMW M4 Adro kit:** broken export scale.
- **"Goblin":** baked onto a ground plane.
- **Anything licensed NonCommercial, NoDerivatives or Editorial:** rejected at search time.

## Trademark and design risk (must clear before commercial release)

The CC BY licences cover the 3D files only. They grant no trademark or design rights. All five are recognisable
reproductions of real, protected car designs:
- BMW M4 CSL (Arden CS).
- Porsche 911 GT3 RS (Arden GT3 R).
- McLaren P1 (Ravenna).
- Ford GT (Solano).
- BMW E30 M3 (Vesta).

GRIDLINE removes every badge and uses only fictional names. Even so, car makers do enforce body-shape (trade dress
and design) rights against games; the M4's kidney grille is the clearest case. **Treat these as development assets
until legal review, a licence, or restyling clears them for a paid release.**
