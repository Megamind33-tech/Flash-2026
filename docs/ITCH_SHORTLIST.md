# itch.io asset shortlist — realistic road, surface and vehicle packs

_2026-10-31 · checked from each pack's own page · licence wording is quoted from the author's text. itch.io has no
standard licence field for free packs, so every pack needs its licence read on the page before import._

## Download status

- Pages and licences were read directly. Stylised, pixel-art and PSX packs were excluded at the search stage.
- **Automated download of the zero-price packs is blocked.** The free path goes Purchase → "No thanks, just take me to
  the downloads" → `/download/<token>`. In a headless browser the token page returns **404**. The claim appears to need
  the email step, and I did not script around it.
- **Needed from you:** download the packs marked ✅ in a normal browser and place them in
  `/home/user/deps/itch/`, or upload them here. I will then hash them, record licences, and run the budget check.

## Shortlist

| Pack | Author | Licence (quoted) | Realism value | Verdict |
|---|---|---|---|---|
| **Texture Pack: Asphalt 01** — 9 PBR materials, 4K, 165 MB — https://juliovii.itch.io/ftp-asphalt-01 | JulioVII | "This pack is licensed CC-BY" · "Any commercial application is allowed, except reselling." | **High**: PBR asphalt for the road shader (G4); Godot-compatible, Unity/Unreal listed | ✅ Download. Credit JulioVII |
| **100 Diffuse Textures II** (205 MB) — https://epicmcdude.itch.io/100-diffuse-textures-ii | Luis Guilherme Bento | "CC0 license — free for commercial use … no attribution required" | Medium–high if it includes asphalt, concrete or ground. Contents not yet confirmed | ✅ Download. Check contents |
| **100 Diffuse Textures** (first pack) — https://epicmcdude.itch.io/100-diffuse-textures | same | same CC0 wording | Same as above | ✅ Download if II lacks road surfaces |
| **OutoTex PhotoBased Seamless Texture Pack 1024px** — https://reactorcore.itch.io/outotex-photobased-seamless-texture-pack-1024px | Reactorcore | "License: CC0 / Public Domain" | Photo-based seamless: ground, wall and pavement detail. 1024 px only | ✅ Download. Use as detail layer |
| **Traffic Road Assets** — https://milkandbanana.itch.io/traffic-road-assets (author jamesdev) | jamesdev | Code: Unlicense · Asset: "Creative Commons Zero v1.0" | Low. Low-poly road and traffic pieces. Useful only as a traffic placeholder | ✅ Download only if the traffic system needs placeholders |
| **Free CC0 Industrial 3D Models** — https://3dmodelscc0.itch.io/free-cc0-industrial-3d-models | 3dmodelscc0 | "Public Domain Industrial 3D Models" | Low–medium: 12 industrial props, for facades and yards | ✅ Download. Check triangles against §4 of the plan |
| Ultimate Low-Poly Barrier & Fences Pack (250+ models) — https://rehandev.itch.io/ultimate-3d-barrier-and-fences-pack | RehanDev | "allowed to use this pack in commercial and private projects" (no named licence) | Low-poly. Barrier and fence placeholders within budget | Hold. Licence is not standard; ask the author if it's used |
| Modern City Game Kit — https://mimakuma.itch.io/modern-city-game-kit | mimakuma | "commercial and noncommercial projects … credit me" | Unclear, likely stylised. Check the model style first | Hold until style is checked |

### Excluded

| Pack | Reason |
|---|---|
| Fukushima Exclusion Zone Texture Pack 1 — https://exclusion-zone-textures.itch.io/fukushima-exclusion-zone-texture-pack-1 | Photo-real and relevant, but **no licence is stated** on the page. Ask the author before use |
| Homemade PBR Materials Collection Vol. 1 — https://rpatterson-smokeworks.itch.io/homemade-pbr-materials-collection-vol-1 | PBR, but **no licence is stated** |
| Road Terrain Pack (RebelZodiac) | Permission to reupload or modify is not granted. Usable only as-is, so it does not suit the pipeline |
| Free Low-Poly Modular Road Pack (Seano4D), Medieval/half-timbered houses, PSX buildings and cars, pixel-art city packs | Stylised or off-genre |

## Next actions (for the heavier model, once the packs are on disk)

1. Hash each file with SHA-256 and record it in `docs/DEPENDENCIES.md`, with the quoted licence and the page URL.
2. Import the Asphalt 01 PBR set into `godot/assets/textures/road/`, with a credit line in `THIRD_PARTY_NOTICES.md`
   and the in-game Credits screen.
3. Check the two CC0 texture packs for asphalt, concrete and ground. Keep only what the road shader and kerbs need.
4. Run `tools/assets/budget_check.py` (gate G2) on any imported model before it enters `godot/assets/`.
