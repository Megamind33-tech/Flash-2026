# Quality correction — evidence

## 1. Paint artifacts (root cause)
Speckle on the paint came from the metallic-flake normal map imported **without mipmaps** (sub-pixel flakes alias
into noise). Fix: `mipmaps/generate=true` on `assets/models/cars/paint_flake_normal.png`, clear-coat roughness
0.02 → 0.05 (specular aliasing on the dense body mesh). Measured on the same bonnet crop of the same hero shot
(mean absolute Laplacian, `tools`-free script in the session): **7.11 → 4.69 (−34 %)**. `paint_noise_before_after.jpg`.

## 2. Main menu
`home_before.png` vs `home_after_<res>.png` at 16:9 (1280x720), 20:9 (1600x720) and 4:3 (1024x768). The hub is now
built from containers; the camera aims at the free band between the text column and the menu (yaw offset from the
band's on-screen position and the FOV) and pulls back when the band is narrow, so the whole car is visible on every
aspect. The garage wall says TEAM GARAGE (the UI already carries the GRIDLINE wordmark); the version label is hidden
on the home screen.
