"""Reference-based clarity metrics: is a render genuinely better filtered, or merely softer?

The reference is the same camera position rendered at 2x the resolution (2560x1440, full 3D resolution,
MSAA 4x, 8x anisotropic, no mip bias) and downsampled with a Lanczos filter to 1280x720: an anti-aliased,
properly filtered image of what the scene really contains. Each variant at 1280x720 is compared with it:

  error    mean |variant - reference| (0-255). Lower = closer to the true image.
  detail   fine-detail energy (|image - Gaussian blur r=1|) relative to the reference's. 1.00 = as much real
           detail as the reference; < 1 = softer than the truth (detail lost to blur); > 1 = extra energy the
           true image does not have (aliasing, grain, sharpening halos).
  edges    gradient strength on the reference's strongest edges (lane markings, kerbs, building outlines),
           relative to the reference. < 1 = edges smeared.
  shimmer  mean |high-pass(view) - high-pass(view 5 cm further)|: how much fine detail flickers when the
           camera moves 5 cm (the reference's own value is the floor for a stable image).
usage: python3 clarity_ref.py <dir> [--ref <name>] <variant> [<variant> ...]   (reference default "ref")"""
import sys
from PIL import Image, ImageFilter, ImageChops, ImageStat

REGIONS = {"road_near": (380, 470, 900, 720), "road_far": (480, 370, 800, 470), "buildings": (0, 60, 1280, 360)}


def load(p, size=None):
    im = Image.open(p).convert("L")
    return im.resize(size, Image.LANCZOS) if size and im.size != size else im


def mean(im):
    return ImageStat.Stat(im).mean[0]


def detail(im):
    return mean(ImageChops.difference(im, im.filter(ImageFilter.GaussianBlur(1))))


def hp(im):
    return ImageChops.subtract(im, im.filter(ImageFilter.GaussianBlur(2)), 1, 128)


def grad(im):
    return ImageChops.add(im.filter(ImageFilter.Kernel((3, 3), [-1, 0, 1, -2, 0, 2, -1, 0, 1], 1, 128)).point(lambda v: abs(v - 128) * 2),
                          im.filter(ImageFilter.Kernel((3, 3), [-1, -2, -1, 0, 0, 0, 1, 2, 1], 1, 128)).point(lambda v: abs(v - 128) * 2))


def edge_strength(im, mask):
    return ImageStat.Stat(grad(im), mask).mean[0]


def top_mask(g, frac=0.04):
    h = g.histogram()
    total = sum(h)
    acc = 0
    thr = 255
    for v in range(255, -1, -1):
        acc += h[v]
        if acc >= total * frac:
            thr = v
            break
    return g.point(lambda v: 255 if v >= thr else 0)


def main():
    d = sys.argv[1]
    args = sys.argv[2:]
    ref = "ref"
    if "--ref" in args:
        i = args.index("--ref")
        ref = args[i + 1]
        args = args[:i] + args[i + 2:]
    ref_a = load(f"{d}/{ref}_a.png", (1280, 720))
    ref_b = load(f"{d}/{ref}_b.png", (1280, 720))
    print(f"{'variant':10s} {'region':10s} {'error':>6s} {'detail':>7s} {'edges':>6s} {'shimmer':>8s}")
    for name, box in REGIONS.items():
        ra, rb = ref_a.crop(box), ref_b.crop(box)
        rd = detail(ra)
        mask = top_mask(grad(ra))
        re = edge_strength(ra, mask)
        rs = mean(ImageChops.difference(hp(ra), hp(rb)))
        print(f"{'reference':10s} {name:10s} {0.0:6.2f} {1.0:7.2f} {1.0:6.2f} {rs:8.2f}")
        for v in args:
            va, vb = load(f"{d}/{v}_a.png").crop(box), load(f"{d}/{v}_b.png").crop(box)
            err = mean(ImageChops.difference(va, ra))
            print(f"{v:10s} {name:10s} {err:6.2f} {detail(va) / rd:7.2f} {edge_strength(va, mask) / re:6.2f} {mean(ImageChops.difference(hp(va), hp(vb))):8.2f}")


main()
