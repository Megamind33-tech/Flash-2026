# Advertising assets: source records

| Asset | Source | Creator | Licence | Geometry | Texture | Use |
|---|---|---|---|---|---|---|
| `hardware/led_trackside_board.glb` | `tools/ads/build_ad_hardware.py` (Blender 4.0, headless) | GRIDLINE project | Project-owned | 4 boxes + 1 quad, under 100 tris | none; PBR material params | 6 × 1 m LED board on legs |
| `hardware/sponsor_barrier.glb` | same script | GRIDLINE project | Project-owned | 2 boxes + 1 quad | none | 3 m precast block with sponsor panel |
| `hardware/overhead_ad_gantry.glb` | same script | GRIDLINE project | Project-owned | truss of 22 boxes + 2 quads, under 300 tris | none | 17.5 m span, 7.5 m columns, 10 × 1.6 m double-sided screen |
| `hardware/urban_digital_billboard.glb` | same script | GRIDLINE project | Project-owned | 4 boxes + 1 quad | none | 8 × 4.5 m wall-mounted screen |
| `ads_atlas.png` (16 creatives) | `tools/scenic/make_ads.py` (PIL + OFL fonts already in assets/fonts) | GRIDLINE project | Project-owned art; Bebas Neue / Barlow fonts are OFL | — | 2048 × 1024 PNG, one shared texture | fictional sponsors only |

- **No third-party 3D models are used.** I didn't search Poly Haven, ambientCG, Kenney, OpenGameArt, itch.io,
  Sketchfab or BlenderKit for ad hardware; I built simple modular housings in Blender instead, which the brief
  allows when suitable assets are missing. The Sketchfab connector is unauthenticated here and BlendSwap still
  rejects its key.
- **Sponsors are invented.** I checked them against well-known regional brands and renamed two that collided
  with real ones (Tusker, Mosi). No real logos are used.
- **Monetisation is not integrated.** `AdProvider` is the seam for a future sponsor backend. No ad SDK is
  included, and none will be without approval.
