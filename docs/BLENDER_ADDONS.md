# Blender add-ons and tooling — inventory for a complete game

_2026-10-31 · answer: **no, not yet.** The pipeline runs, one add-on is verified, and a curated set is ready to install
but the install step is awaiting permission._

## 1. Blender version — the blocker

| | Blender 4.0.2 (current pin) | Blender 5.2.2 LTS (recommended) |
|---|---|---|
| Bundled add-ons | ~110 | 13 (incl. `node_wrangler`, `io_scene_gltf2`, `rigify`) |
| `bpy` scripts in `tools/` | run | **run, identical output** (ad hardware: four GLBs, same triangle counts) |
| Catalogue add-ons we want | most need ≥ 4.2; several need 5.0–5.3 | all curated add-ons satisfy ≥ 5.2 except the two marked 5.3 below |

Verified in this session: `tools/ads/build_ad_hardware.py` (run with its output path redirected to a scratch folder) generates
identical GLBs on both versions, with triangle counts 38 / 280 / 26 / 38 for the four pieces. Not yet verified: `tools/cars/export_car.py` on 5.2.2. It needs a BlendSwap source `.blend`
that is not in the repo (only the zip hashes), so **the car pipeline is untested on 5.2.2**. That's a gate before switching.

Recommendation: move to **5.2.2 LTS** after the car export test passes. Keep 4.0.2 only until then.

## 2. What is verified

| Item | Status | Evidence |
|---|---|---|
| Blender 4.0.2 (headless) | ✅ | `--version` |
| Blender 5.2.2 LTS | ✅ | `--version`, both bpy scripts run |
| Extension install from extensions.blender.org | ✅ | Gorani 0.3.7 downloaded, SHA-verified by the archive, installed |
| Extension enable on 5.2.2 | ✅ | `addon_enable('bl_ext.user_default.gorani')` → `(True, True)` |
| Ad hardware reproduces on 5.2.2 | ✅ | identical GLB triangle counts |
| Car export on 5.2.2 | ❌ not tested | no source `.blend` in repo |

## 3. Curated add-on set (ready, not installed)

All are in the official catalogue, with SHA-256 checked against the catalogue. The installer is
`tools/deps/fetch_blender_addons.py`. **It was blocked by the permission classifier when I tried to run it, so nothing
from this table is installed except Gorani.**

| Add-on (id) | Version | Licence | Min Blender | Use in GRIDLINE |
|---|---|---|---|---|
| LODGen (`lod_gen`) | 0.0.5 | GPL-3.0 | 4.5 | LOD chains (gates G2/G3) |
| PROTO Game Asset Tools (`proto_game_asset_tools`) | 2.5.0 | GPL-3.0 | 4.2 (max 5.3) | Game-ready export and naming for Godot |
| OMI Physics Body glTF (`omi_physics_body_gltf_extension`) | 1.6.5 | GPL-3.0 | 5.0 | Collision shapes in glTF for Godot |
| The Better Baker (`thebetterbaker`) | 5.1.1 | GPL-3.0 | 5.1 | PBR baking for facades, props, car paint |
| Bake Preflight (`bake_preflight`) | 0.1.0 | GPL-3.0 | 4.5 | Catch bake mistakes early |
| Gorani (`gorani`) | 0.3.7 | GPL-3.0 + BSD-2 | 4.2 | Urban site context, buildings, roads, terrain (gate G7). **Installed** |
| PTerrain (`pterrain`) | 1.0.5 | GPL-3.0 | 4.2.21 | Real-world terrain for scenic venues |
| SRTM Terrain Importer (`srtm_terrain_importer`) | 1.0.5 | GPL-3.0 | 4.2 | Elevation for scenic venues |
| PolyQuilt (`PolyQuilt_Fork`) | 1.46.8 | GPL-3.0 | 4.5 | Retopology for cars and kit |
| Hardflow (`hardflow`) | 1.22.0 | GPL-3.0 | 4.2 | Hard-surface modelling for cars and kit |
| Bagapie (`Bagapie`) | 11.0.12 | GPL-3.0 | 5.0 | Scatter, ivy, architecture helpers |
| AmbientCG Material Importer (`ambientcg_material_importer`) | 1.5.0 | GPL-3.0 | 4.2 | Import CC0 ambientCG PBR sets |

Legacy add-ons that used to be bundled, now in the catalogue for ≥ 4.2: **LoopTools** (4.7.7), **Magic UV** (6.7.1),
**Extra Mesh Objects** (0.4.1), **Archimesh** (1.2.5), **Scatter Objects** (0.2.0), **Real Snow** (1.3.2), **Sun Position**
(4.4.0). Add them only if the kit needs them.

**Excluded on version grounds:** `poly_haven` Lite and `ambientCG` Lite (CC0, but min Blender 5.3). Our Poly Haven and
ambientCG downloads use `tools/assets/fetch_polyhaven.py` and do not need the add-on.

## 4. Not available from this environment

| Need | Status | Reason | Route |
|---|---|---|---|
| **BlenderKit** add-on | ❌ | Not in the official catalogue. `blenderkit.com/addon` returns 404, GitHub is blocked | Install from blenderkit.com in your own Blender, or allow `codeload.github.com` |
| **BlenderKit** assets | ⚠️ search works, download does not | Search API returns results (848 free "asphalt" materials). Each asset carries `license: royalty_free`, not CC0. Downloads need a BlenderKit login | You log in; I then read each asset's licence page before use |
| **BlenderGIS** (OSM and DEM import for Blender) | ❌ | Not in the catalogue; GitHub blocked | Install the zip from GitHub in your browser, or allow `codeload.github.com` |

**BlenderKit licence caution:** "royalty_free" is BlenderKit's own term, not a standard licence. I will not ship a BlenderKit
asset without reading the asset's own terms.

## 5. What add-ons do not give us

Add-ons don't supply content. The gaps in `docs/PRODUCTION_PLAN.md` §5 still stand: licensed cars (decision A),
audio (C), Megascans (D), and the in-house water, pothole, traffic and pedestrian systems. No add-on in the catalogue
covers those.

Licences of the tools: the add-ons are GPL and are used only to make assets. Their code is not shipped, so the GPL does
not reach the game.

## 6. Decisions and next steps

1. **Approve the install** of the curated set into Blender 5.2.2 (`fetch_blender_addons.py`). It downloads about 12 zips from
   extensions.blender.org, each SHA-checked, and installs them into Blender's user repository. Nothing else.
2. **Run the car export test on 5.2.2** when the BlendSwap `.blend` sources are provided. Switch the pin only if it passes.
3. **BlenderKit and BlenderGIS:** install them yourself, or allow the GitHub download, then tell me.
