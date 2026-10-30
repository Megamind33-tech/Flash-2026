# Car models: licence record

The owner supplied all five source models on 2026-10-30 as BlendSwap downloads; the zip SHA-256 hashes are in
`tools/cars/licences/SOURCE_ZIPS.sha256`. The original licence files are kept in `tools/cars/licences/`.

`tools/cars/export_car.py` converted each model headlessly with Blender 4.0.2. The conversion did not
remodel anything. It made these changes:
- Removed the studio, ground, light and camera objects.
- Removed every manufacturer badge and piece of lettering: Audi rings and R8 script, number plates and a hood crest.
- Capped subdivision and decimated detail parts for mobile.
- Replaced materials with GRIDLINE's canonical `GL_*` set.
- Split the wheels out, oriented the cars with the front at +Z and scaled them to real lengths.
- Ravenna only: narrowed the body to 88 % width, because the author's model is about 2.4 m wide.

| In game | File | Source (BlendSwap) | Author | Licence | What it requires |
|---|---|---|---|---|---|
| Arden V8 Coupé | `arden_v8.glb` | #17183 "Audi R8 V8 cycles (Version 0.95)" | Neubi | CC0 1.0 | Nothing |
| Arden GT3 R | `arden_gt3.glb` | #91200 "Audi R8 LMS" | Uploader of #91200 (the licence file gives no name) | CC0 1.0 | Nothing |
| Ravenna Hybrid | `ravenna_hybrid.glb` | #74782 "La ferrari 2013 concept restyled" | zenox3d | CC BY-SA 3.0 | Credit zenox3d. This converted .glb is a derivative and stays CC BY-SA 3.0 |
| Solano Concept | `solano_concept.glb` | #74332 "Yellow sports car concept" | zenox3d | CC BY-SA 3.0 | Credit zenox3d. This converted .glb is a derivative and stays CC BY-SA 3.0 |
| Elektra E-GT | `elektra_egt.glb` | #86736 "Porsche Mission E – Legacy Edition" | Lee Rosario (from the .blend file name; confirm on the BlendSwap page) | CC BY 3.0 | Credit the author |

The in-game credits are at Settings → Credits, which satisfies the BY/BY-SA attribution requirement inside the app.
The store listing should also carry the same credit lines.

## Trademark and design risk (must clear before commercial release)

The copyright licences cover the 3D files only. They do not grant any trademark or design rights. Three of the
five source models are recognisable reproductions of real, protected car designs:
- Audi R8 and R8 LMS (Arden V8 and Arden GT3).
- Ferrari LaFerrari (Ravenna).
- Porsche Mission E (Elektra).

Solano was cut down from the author's Corvette C7 model.

GRIDLINE removes every badge and uses only fictional names. Even so, car makers do enforce body-shape
(trade dress / design) rights against games. **Treat these five as development assets until legal review, a
licence, or restyling clears them for a paid release.**
