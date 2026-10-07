#!/usr/bin/env python3
"""Generate the piece sprite sets in assets/pieces/ (needs Pillow)."""
import os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Fonts containing the Unicode chess symbols (change these paths on Windows/macOS).
DEJAVU = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"        # DejaVu Sans
FREESERIF = "/usr/share/fonts/truetype/freefont/FreeSerif.ttf"    # GNU FreeFont
UNIFONT = "/usr/share/fonts/opentype/unifont/unifont.otf"         # GNU Unifont
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops
OUTG = {"K":"\u2654","Q":"\u2655","R":"\u2656","B":"\u2657","N":"\u2658","P":"\u2659"}
FILG = {"K":"\u265A","Q":"\u265B","R":"\u265C","B":"\u265D","N":"\u265E","P":"\u265F"}
S = 256
def render(fontpath, size, ch, canvas=S, offset=None):
    font = ImageFont.truetype(fontpath, size)
    if offset is None:
        m = Image.new("L", (canvas*2, canvas*2), 0)
        ImageDraw.Draw(m).text((canvas//2, canvas//2), FILG[ch], font=font, fill=255)
        x0,y0,x1,y1 = m.getbbox(); w,h = x1-x0, y1-y0
        offset = (canvas//2 - x0 + (canvas-w)//2, canvas//2 - y0 + (canvas-h)//2 + canvas//64)
    f = Image.new("L",(canvas,canvas),0); ImageDraw.Draw(f).text(offset, FILG[ch], font=font, fill=255)
    o = Image.new("L",(canvas,canvas),0); ImageDraw.Draw(o).text(offset, OUTG[ch], font=font, fill=255)
    return f, o
def sil(mask, thr=100):
    hard = mask.point(lambda v: 255 if v > thr else 0)
    ImageDraw.floodfill(hard, (0,0), 128)
    return hard.point(lambda v: 0 if v == 128 else 255)
def layer(color, alpha):
    l = Image.new("RGBA", alpha.size, color+(255,)); l.putalpha(alpha); return l
def shadow_of(s, k=6, dx=4, dy=6, strength=0.35):
    sh = s.filter(ImageFilter.GaussianBlur(k)).point(lambda v: int(v*strength))
    return layer((0,0,0), ImageChops.offset(sh, dx, dy))
def comp(*layers):
    im = Image.new("RGBA", layers[0].size, (0,0,0,0))
    for l in layers: im = Image.alpha_composite(im, l)
    return im

def classic(fontpath, size, ch, side):
    f, o = render(fontpath, size, ch)
    s = sil(f).filter(ImageFilter.MaxFilter(3))
    if side == "w":
        return comp(shadow_of(s), layer((250,248,240), s), layer((30,30,30), o))
    det = ImageChops.subtract(sil(f), f).filter(ImageFilter.MinFilter(3))
    return comp(shadow_of(s), layer((32,32,36), s), layer((200,200,205), det))

def flat(ch, side):
    f, o = render(DEJAVU, 224, ch)
    s = sil(f)
    edge = ImageChops.subtract(s.filter(ImageFilter.MaxFilter(11)), s)
    det = ImageChops.subtract(s, f).filter(ImageFilter.MinFilter(3))
    if side == "w":
        return comp(layer((80,70,62), edge), layer((246,241,231), s), layer((185,172,158), det))
    return comp(layer((235,235,240), edge.point(lambda v: v//2)), layer((52,56,66), s), layer((110,118,134), det))

def neon(ch, side):
    f, o = render(DEJAVU, 224, ch)
    s = sil(f).filter(ImageFilter.MaxFilter(3))
    col = (90,230,255) if side == "w" else (255,80,200)
    body = (16,28,40) if side == "w" else (36,12,34)
    glow = o.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(7))
    return comp(layer(col, glow.point(lambda v: min(255,int(v*1.4)))), layer(body, s.point(lambda v: int(v*0.92))), layer(col, o), layer((255,255,255), o.filter(ImageFilter.MinFilter(3)).point(lambda v: v//2)))

def pixel(ch, side):
    font = ImageFont.truetype(UNIFONT, 16)
    def r(g):
        m = Image.new("L",(16,16),0); ImageDraw.Draw(m).text((0,0), g, font=font, fill=255)
        return m.point(lambda v: 255 if v>127 else 0)
    f, o = r(FILG[ch]), r(OUTG[ch])
    bb = f.getbbox(); dx = (16-(bb[2]-bb[0]))//2 - bb[0]; dy = (16-(bb[3]-bb[1]))//2 - bb[1] + 0
    f, o = ImageChops.offset(f,dx,dy), ImageChops.offset(o,dx,dy)
    s = f.copy(); ImageDraw.floodfill(s,(0,0),128); s = s.point(lambda v: 0 if v==128 else 255)
    if side == "w":
        im = comp(layer((248,244,232), s), layer((24,24,30), o))
        ol = ImageChops.subtract(s, f)  # interior
    else:
        det = ImageChops.subtract(s, f)
        im = comp(layer((30,30,38), s), layer((150,150,165), det))
    # 1px drop shadow
    sh = layer((0,0,0), ImageChops.offset(s,1,1).point(lambda v: v//3))
    im = comp(sh, im)
    return im.resize((64,64), Image.NEAREST)

SETS = {
 "classic":  lambda ch, sd: classic(DEJAVU, 224, ch, sd),
 "staunton": lambda ch, sd: classic(FREESERIF, 268, ch, sd),
 "flat": flat, "neon": neon, "pixel": pixel,
}
for name, fn in SETS.items():
    os.makedirs(os.path.join(ROOT, "assets", "pieces", name), exist_ok=True)
    for ch in "KQRBNP":
        for sd in "wb":
            im = fn(ch, sd)
            if im.size != (64,64): im = im.resize((64,64), Image.LANCZOS)
            im.save(os.path.join(ROOT, "assets", "pieces", name, f"{sd}{ch}.png"))
# preview
os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
sheet = Image.new("RGB",(64*12, 64*len(SETS)))
for j,name in enumerate(SETS):
    for i,ch in enumerate("KQRBNP"):
        for k,sd in enumerate("wb"):
            x = (i*2+k)*64; col = (238,216,181) if (i*2+k+j)%2==0 else (118,150,86)
            bg = Image.new("RGBA",(64,64),col+(255,))
            sheet.paste(Image.alpha_composite(bg, Image.open(os.path.join(ROOT, "assets", "pieces", name, f"{sd}{ch}.png"))).convert("RGB"), (x, j*64))
sheet.save(os.path.join(ROOT, "build", "pieces_preview.png"))
