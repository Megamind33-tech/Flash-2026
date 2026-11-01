"""Resurface a cracked asphalt scan (Poly Haven asphalt_02, CC0) for a race venue.
Cracks are found at low frequency: after a 2.5 px blur the asphalt's pores wash out but the long cracks stay
darker than a 17 px grey-scale closing of the blurred image. Inside that mask the crack's darkening (closing - blur)
is added back, so the aggregate grain continues through the repaired line instead of a smooth patch; height gets
the same lift, the normal map is flattened along the crack, roughness is evened. 10 % of each crack is kept.
usage: resurf.py <src_prefix> <dst_prefix>"""
import sys
from PIL import Image, ImageFilter, ImageChops
src, dst = sys.argv[1], sys.argv[2]


def depth_of(L, k=17, r=2.5):
    B = L.filter(ImageFilter.GaussianBlur(r))
    return ImageChops.subtract(B.filter(ImageFilter.MaxFilter(k)).filter(ImageFilter.MinFilter(k)), B)


import os
for k, r, tag in ((17, 2.5, "a"), (33, 4.0, "b")):
    src_p = src if tag == "a" else dst + "_tmp"
    dst_p = dst + "_tmp" if tag == "a" else dst
    alb = Image.open(src_p + "_albedo.jpg").convert("RGB")
    d = depth_of(alb.convert("L"), k, r)
    mask = d.point(lambda v: 0 if v < 13 else min(255, (v - 13) * 14)).filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(1.5))
    keep = 0.9
    lift = Image.composite(d, Image.new("L", d.size, 0), mask).point(lambda v: int(v * keep * 1.15))
    cov = sum(1 for v in mask.get_flattened_data() if v > 128) / (mask.size[0] * mask.size[1])
    print(f"crack coverage {cov*100:.1f}%")
    Image.merge("RGB", [ImageChops.add(b, lift) for b in alb.split()]).save(dst_p + "_albedo.jpg", quality=93)
    h = Image.open(src_p + "_height.jpg").convert("L")
    hl = Image.composite(depth_of(h, k, r), Image.new("L", h.size, 0), mask).point(lambda v: int(v * keep))
    ImageChops.add(h, hl).save(dst_p + "_height.jpg", quality=93)
    r = Image.open(src_p + "_rough.jpg").convert("L")
    Image.composite(r.filter(ImageFilter.GaussianBlur(4)), r, mask).save(dst_p + "_rough.jpg", quality=93)
    n = Image.open(src_p + "_normal.jpg").convert("RGB")
    calm = ImageChops.blend(n.filter(ImageFilter.GaussianBlur(4)), Image.new("RGB", n.size, (128, 128, 255)), 0.6)
    Image.composite(calm, n, mask).save(dst_p + "_normal.jpg", quality=93)
for k in ("albedo", "height", "rough", "normal"):
    os.remove(f"{dst}_tmp_{k}.jpg")
