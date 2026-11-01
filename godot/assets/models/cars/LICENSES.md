# Car models: asset manifest and licence record

All twelve race cars are Sketchfab downloads with a commercial-use licence: CC BY 4.0, "author must be credited;
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
| Kaze R4 GT (JDM GT) | `kaze_r4.glb` | "Nissan Skyline R34 GT-R" https://sketchfab.com/3d-models/nissan-skyline-r34-gt-r-ff8fb2251dfa4bb9979e7022c5a6666c | Lexyc16 (https://sketchfab.com/Lexyc16) | CC BY 4.0 |
| Kaze Rotor 7 (JDM) | `kaze_rotor.glb` | "Mazda RX-7 FD" https://sketchfab.com/3d-models/mazda-rx-7-fd-d35ff630df614771b82e7b2f59035b1e | Lexyc16 (https://sketchfab.com/Lexyc16) | CC BY 4.0 |
| Hikari NS-1 (Classic) | `hikari_ns1.glb` | "Honda NSX 1990" https://sketchfab.com/3d-models/honda-nsx-1990-1cc15628a00a4739a6b6c01128927c8d | Lexyc16 (https://sketchfab.com/Lexyc16) | CC BY 4.0 |
| Alba Integra Evo (Rally) | `alba_integra.glb` | "FREE Lancia Delta HF Integrale evo 2" https://sketchfab.com/3d-models/free-lancia-delta-hf-integrale-evo-2-85614131e0dc4613a948472aaa935fc7 | TARANTULA (https://sketchfab.com/begemot.988888) | CC BY 4.0 |
| Ravenna Quaranta (Classic supercar) | `ravenna_quaranta.glb` | "Ferrari f40" https://sketchfab.com/3d-models/ferrari-f40-52a66c41cfcd4f999fb1b1c49bf24d70 | Black Snow (https://sketchfab.com/BlackSnow02) | CC BY 4.0 |
| Kaze GT-35 Wide (GT) | `kaze_gt35.glb` | "Nissan Skyline GTR r35" https://sketchfab.com/3d-models/nissan-skyline-gtr-r35-7b142ea3376e4811a326256c59bbc7a2 | Black Snow (https://sketchfab.com/BlackSnow02) | CC BY 4.0 |
| Arden GT12 (Grand tourer) | `arden_gt12.glb` | "Aston Martin db11" https://sketchfab.com/3d-models/aston-martin-db11-0ce56f01b1ff40b3a4e36bc56873dbc7 | Black Snow (https://sketchfab.com/BlackSnow02) | CC BY 4.0 |

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
- Textures limited to 1024 px. Only the first UV set is kept (no material used the others).
- Hand-made distance LODs (`Body_LOD1` / `Body_LOD2`); Godot's automatic LODs are off for the cars.

## Triangle counts (LOD0, hero car)

| Car | Body | Wheels (4) | Total |
|---|---|---|---|
| Solano GT-LM | 32.7k | 11.2k | 43.9k |
| Ravenna Ibrido | 45.8k | 11.1k | 56.9k |
| Vesta Evo II | 67.2k | 10.5k | 77.7k |
| Arden CS Coupé | 65.4k | 12.6k | 77.9k |
| Arden GT3 R | 88.7k | 11.4k | 100.1k |
| Kaze Rotor 7 | 24.0k | 10.4k | 34.4k |
| Arden GT12 | 26.0k | 11.9k | 37.8k |
| Hikari NS-1 | 33.0k | 10.7k | 43.7k |
| Kaze R4 GT | 37.3k | 10.4k | 47.7k |
| Kaze GT-35 Wide | 55.1k | 11.8k | 66.9k |
| Alba Integra Evo | 74.3k | 10.7k | 85.0k |
| Ravenna Quaranta | 87.7k | 10.5k | 98.2k |

Opponents use the hand-made hull LODs (`CarBuilder.enable_lods`: full model to 30 m, hull to 90 m, reduced hull beyond).

## Second batch: brand removal

- Badge and lettering parts and materials were dropped: maker badge sheets, model scripts, cobra badges, the F40
  logo sheet, the AMR / sticker sheets, GT-R / NISMO lettering, and the rally car's shield, number plate,
  "delta integrale" badge, club sticker and sun-strip.
- Tyre sidewalls: the Bridgestone lettering annulus was repainted as plain rubber (R4, Rotor 7, NS-1), and the Toyo
  lettering inpainted (Integra).
- NS-1: the rear-panel photo had its plate script and maker emblem removed.
- GT-35: the tuner lettering on the rim was inpainted and the steering-wheel badge blacked out.
- Integra Evo: the maker roundel on the trim sheet and the wheel maker's name around the rim were inpainted.
- GT-35: the maker name on the centre screen and the tuner lettering on the tachometer face were inpainted.
- NS-1: the number plate shares the rear-lamp material; it is now plain black, so it no longer glows under braking.
- Scrubbed textures are written back into each `.glb` (`tools/cars/glb_replace_image.py`), so a re-import keeps them.

All seven are recognisable real designs. The same trademark caveat applies (see below).

## Held back (converted, not in the game)

- **Ridgeway SV8**, from "Ford Mustang Shelby GT500" by Jiaxing (https://sketchfab.com/saitoyang), CC BY 4.0,
  https://sketchfab.com/3d-models/ford-mustang-shelby-gt500-0eaa7a16796540f29461ddae05ecdeb3.
  - The maker and tuner names are modelled into the front bumper: "SHELBY" on the splitter and the grille emblem.
  - The bumper is unconnected triangle soup, so the letters cannot be separated from the panel without holes.
  - The converted files are in `tools/cars/staging_batch2/held/`. Needs a hand edit in Blender before it can ship.

## Rejected candidates (for the record)

- **Toyota GR Supra GT300 (vecarz, CC BY 4.0).** The exterior is built from stacked textured layers carrying the
  real Toyota, Denso, Bosch and Shell livery. It cannot be reduced below about 200k triangles without the layers
  tearing.
- **BMW M4 Adro kit:** broken export scale.
- **"Goblin":** baked onto a ground plane.
- **Anything licensed NonCommercial, NoDerivatives or Editorial:** rejected at search time.

## Trademark and design risk (must clear before commercial release)

The CC BY licences cover the 3D files only. They grant no trademark or design rights. All twelve are recognisable
reproductions of real, protected car designs:
- BMW M4 CSL (Arden CS).
- Porsche 911 GT3 RS (Arden GT3 R).
- McLaren P1 (Ravenna).
- Ford GT (Solano).
- BMW E30 M3 (Vesta).
- Nissan Skyline R34 GT-R (Kaze R4), Mazda RX-7 FD (Kaze Rotor 7), Honda NSX (Hikari NS-1), Lancia Delta HF
  Integrale (Alba Integra Evo), Ferrari F40 (Ravenna Quaranta), Nissan GT-R R35 (Kaze GT-35), Aston Martin DB11
  (Arden GT12).

GRIDLINE removes every badge and uses only fictional names. Even so, car makers do enforce body-shape (trade dress
and design) rights against games; the M4's kidney grille is the clearest case. **Treat these as development assets
until legal review, a licence, or restyling clears them for a paid release.**
