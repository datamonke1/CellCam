from PIL import Image, ImageDraw
import math, random

S = 1024
img = Image.new("RGB", (S, S), (16, 24, 34))  # dark workbench background
d = ImageDraw.Draw(img, "RGBA")
# soft vignette glow
for r in range(720, 0, -24):
    t = 1 - r / 720
    d.ellipse([512-r, 470-r, 512+r, 470+r],
              fill=(int(16+12*t), int(24+18*t), int(34+22*t)))

# --- magnifying glass handle (behind the lens), going down-right ---
hx0, hy0 = 742, 716          # at the rim
hx1, hy1 = 968, 942          # handle end
d.line([hx0, hy0, hx1, hy1], fill=(70, 74, 82, 255), width=118)
d.line([hx0, hy0, hx1, hy1], fill=(104, 110, 122, 255), width=88)
d.line([hx0+16, hy0-10, hx1+10, hy1-16], fill=(168, 176, 188, 255), width=20)
d.ellipse([hx1-56, hy1-56, hx1+56, hy1+56], fill=(104, 110, 122, 255))

# --- lens interior: light magnifier glass ---
lens_c = (452, 452)
lens_r = 372
d.ellipse([lens_c[0]-lens_r, lens_c[1]-lens_r, lens_c[0]+lens_r, lens_c[1]+lens_r],
          fill=(196, 222, 228))

# --- the blob (yellow slime mould) inside the lens ---
random.seed(11)
cx, cy = 452, 500
body_mask = Image.new("L", (S, S), 0)
bd = ImageDraw.Draw(body_mask)
pts = []
R = 238
for i in range(80):
    a = 2 * math.pi * i / 80
    wob = 1 + 0.055*math.sin(a*3+0.7) + 0.04*math.sin(a*6+2.0) + 0.025*math.cos(a*9)
    pts.append((cx + R*wob*math.cos(a), cy + 26 + R*0.92*wob*math.sin(a)))
bd.polygon(pts, fill=255)
bd.ellipse([cx+10, cy+70, cx+288, cy+292], fill=255)   # growth lobe right
bd.ellipse([cx-292, cy+52, cx-40, cy+268], fill=255)   # growth lobe left

blob = Image.new("RGBA", (S, S), (0, 0, 0, 0))
bl = ImageDraw.Draw(blob)
bl.polygon(pts, fill=(250, 197, 38, 255))
bl.ellipse([cx+10, cy+70, cx+288, cy+292], fill=(250, 197, 38, 255))
bl.ellipse([cx-292, cy+52, cx-40, cy+268], fill=(250, 197, 38, 255))
# vein network, clipped inside the body (subtle, like the real plasmodium)
veins = Image.new("RGBA", (S, S), (0, 0, 0, 0))
vd = ImageDraw.Draw(veins)
random.seed(23)
def branch(x, y, angle, length, width, depth):
    if depth == 0 or length < 9 or width < 0.8:
        return
    x2, y2 = x + length*math.cos(angle), y + length*math.sin(angle)
    vd.line([x, y, x2, y2], fill=(255, 240, 165, 170), width=max(1, int(width)))
    for _ in range(2 if random.random() < 0.85 else 3):
        branch(x2, y2, angle + random.uniform(-0.6, 0.6),
               length*random.uniform(0.68, 0.82), width*0.68, depth-1)
hub = (cx - 10, cy + 110)
for i in range(13):
    branch(hub[0], hub[1], i*(2*math.pi/13) + random.uniform(-0.1, 0.1),
           random.uniform(88, 124), 6, 5)
veins.putalpha(Image.composite(veins.getchannel("A"), Image.new("L", (S, S), 0), body_mask))
blob.alpha_composite(veins)
# clip blob to the lens
lens_mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(lens_mask).ellipse(
    [lens_c[0]-lens_r, lens_c[1]-lens_r, lens_c[0]+lens_r, lens_c[1]+lens_r], fill=255)
img.paste(Image.alpha_composite(img.convert("RGBA"), blob).convert("RGB"), (0, 0), lens_mask)
img = img.convert("RGBA")
d = ImageDraw.Draw(img, "RGBA")

# face — eyes looking down-right at the oat flake
for ex in (cx - 82, cx + 80):
    d.ellipse([ex-42, cy-104, ex+42, cy-6], fill=(255, 255, 255, 255))
    d.ellipse([ex-16, cy-78, ex+30, cy-22], fill=(24, 28, 20, 255))
    d.ellipse([ex+2, cy-72, ex+16, cy-56], fill=(255, 255, 255, 255))
# cheeks
d.ellipse([cx-196, cy-14, cx-112, cy+34], fill=(255, 140, 90, 70))
d.ellipse([cx+122, cy-14, cx+206, cy+34], fill=(255, 140, 90, 70))

# open mouth, eating an oat flake
mx, my = cx + 26, cy + 62
d.ellipse([mx-72, my-44, mx+80, my+68], fill=(94, 46, 8, 255))        # open mouth (big)
d.ellipse([mx-48, my+26, mx+56, my+62], fill=(196, 84, 74, 255))      # tongue
# oat flake sticking out of the mouth (bitten)
flake = Image.new("RGBA", (210, 128), (0, 0, 0, 0))
fd = ImageDraw.Draw(flake)
fd.ellipse([6, 12, 204, 116], fill=(233, 188, 106, 255), outline=(176, 126, 60, 255), width=5)
fd.line([26, 66, 184, 58], fill=(176, 126, 60, 170), width=5)
fd.arc([150, 20, 214, 104], start=300, end=70, fill=(250, 197, 38, 255), width=16)  # bite mark edge
flake = flake.rotate(-14, expand=True, resample=Image.BICUBIC)
img.alpha_composite(flake, (int(mx - 96), int(my - 58)))  # flake centred in the mouth
d = ImageDraw.Draw(img, "RGBA")
# bite taken out of the flake + lips closed over it, so it sits IN the mouth
d.ellipse([mx-104, my-64, mx-52, my-22], fill=(250, 197, 38, 255))    # bite (blob-yellow)
d.arc([mx-72, my-44, mx+80, my+68], start=180, end=360, fill=(120, 70, 10, 255), width=9)   # upper lip over the flake
d.arc([mx-72, my-44, mx+80, my+68], start=0, end=180, fill=(120, 70, 10, 255), width=7)     # lower lip under the flake

# --- magnifier rim on top of everything ---
d.ellipse([lens_c[0]-lens_r, lens_c[1]-lens_r, lens_c[0]+lens_r, lens_c[1]+lens_r],
          outline=(88, 94, 106, 255), width=44)
d.ellipse([lens_c[0]-lens_r, lens_c[1]-lens_r, lens_c[0]+lens_r, lens_c[1]+lens_r],
          outline=(190, 198, 208, 255), width=10)
# rim screw where the handle joins
d.ellipse([730, 692, 792, 754], fill=(150, 158, 170, 255), outline=(80, 86, 98, 255), width=5)
d.ellipse([754, 716, 768, 730], fill=(80, 86, 98, 255))

out = "/home/strebeli/Documents/Mario/MisterBlob/Sources/BlobCam/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
img.convert("RGB").save(out)
print("saved", out)
