"""Image clarity metrics for a pair of renders 5 cm apart (same view).
grain   = mean |Laplacian| (fine-detail energy) in a region: lower = less speckle/grain
shimmer = mean |high-pass(a) - high-pass(b)| in a region: how much fine detail changes for a 5 cm camera move
          (aliased, unfiltered textures flicker; filtered ones barely change). Lower is more stable."""
import sys
from PIL import Image, ImageFilter, ImageChops, ImageStat
def load(p): return Image.open(p).convert('L')
def hp(im): return ImageChops.subtract(im, im.filter(ImageFilter.GaussianBlur(2)), 1, 128)
def lap(im): return im.filter(ImageFilter.Kernel((3,3),[0,1,0,1,-4,1,0,1,0],1,128))
regions = {"road_near": (380, 470, 900, 720), "road_far": (480, 370, 800, 470), "buildings": (0, 60, 1280, 360)}
tag = sys.argv[1]; base = sys.argv[2]
for view in ["", "t1"]:
    a = load(f"{base}/{tag}_{view or 'a'}.png"); b = load(f"{base}/{tag}_{(view + 'b') if view else 'b'}.png")
    for name, box in regions.items():
        A, B = a.crop(box), b.crop(box)
        g = ImageStat.Stat(ImageChops.difference(lap(A), Image.new('L', A.size, 128))).mean[0]
        s = ImageStat.Stat(ImageChops.difference(hp(A), hp(B))).mean[0]
        print(f"{tag:8s} {view or 'straight':8s} {name:10s} grain={g:5.2f} shimmer={s:5.2f}")
