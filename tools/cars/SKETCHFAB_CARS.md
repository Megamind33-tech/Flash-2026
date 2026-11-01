# Sketchfab race cars: how they were made

1. **Source.** Download through the Sketchfab API (glTF), CC BY 4.0 only. Downloads are kept outside the repo,
   in `/home/user/deps/sketchfab/cars/<name>`.
2. **Texture scrub.** Work on a copy of each model. Paint the brand marks out of the textures:
   - Solano: sidewall lettering inpainted (white letters on rubber); "FORD GT" dash text blacked out.
   - Vesta: "Firestone" / "TZ700" sidewall bands flattened in the tyre normal map; rim centre-cap roundel blanked
     in the base colour, metal/roughness and normal maps.
   - Arden GT3 R: crest textures (`ID06_stitch`, `headlight_1`) blanked.
   - Ravenna: speedmark on the cockpit decal sheet blacked out.
3. **Convert.**
   `blender -b --python tools/cars/export_sketchfab_car.py -- <car_id> <working copy> <out dir>`
   This produces a GLB (Body, Body_LOD1, Body_LOD2, Wheel_FL/FR/RL/RR) and a spec JSON. Copy them to
   `godot/assets/models/cars/` and `tools/cars/specs/`, then run `tools/cars/gen_specs.py`.
4. **Import.** In each car's `.glb.import`, set `meshes/generate_lods=false`. Godot's automatic LODs tear these
   layered paint panels, so the cars use their own LODs instead (`CarBuilder.enable_lods`).
5. **Verify.**
   - `godot --path godot res://tools/render_cards.tscn -- --cars-only` to render the dealership cards.
   - `tests/drive_controls_test`, `ride_height_test` and `stability_test` must pass.
   - Look at every extracted texture for logos: in this batch that pass found two crest textures that the first
     pass had missed.

Hard-won rules (each one cost a broken result):
- Never decimate the painted shell, or anything lying within about 12 mm of it.
- Never pass the body through a BMesh round trip. It drops the author's custom normals, and the paint dents.
- Godot automatic LODs are off for the same reason.
