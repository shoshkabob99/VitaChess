#!/usr/bin/env python3
"""Make the title-screen emblem and the LiveArea images (needs Pillow).

  assets/art/title.png                               main menu emblem, drawn 1:1 (sharp)
  assets/sce_sys/icon0.png                           128x128 bubble icon
  assets/sce_sys/livearea/contents/bg.png            840x500 LiveArea background
  assets/sce_sys/livearea/contents/startup.png       280x158 Start gate image
The Vita needs the sce_sys PNGs as 8-bit palette images; this script handles that.
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = lambda *p: os.path.join(ROOT, "assets", *p)
SYMBOLS = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"     # chess symbols (change on Windows/macOS)
INTER = A("fonts", "Inter-Regular.ttf")
INTER_BOLD = A("fonts", "Inter-Bold.ttf")
AUTHOR = "shoshkabob"
GOLD, WHITE, BG = (255, 200, 90), (240, 240, 240), (28, 30, 36)
OUTLINE = {"K": "\u2654", "Q": "\u2655", "N": "\u2658"}
FILLED = {"K": "\u265A", "Q": "\u265B", "N": "\u265E"}


def piece(kind, white, size):
    """A classic-style piece rendered at 4x and shrunk, so it's sharp at any size."""
    S = size * 4
    font = ImageFont.truetype(SYMBOLS, int(S * 0.875))
    def mask(ch):
        m = Image.new("L", (S, S), 0)
        ImageDraw.Draw(m).text((S // 2, int(S * 0.53)), ch, font=font, fill=255, anchor="mm")
        return m
    filled, outline = mask(FILLED[kind]), mask(OUTLINE[kind])
    hard = filled.point(lambda v: 255 if v > 100 else 0)
    ImageDraw.floodfill(hard, (0, 0), 128)
    sil = hard.point(lambda v: 0 if v == 128 else 255).filter(ImageFilter.MaxFilter(5))
    def layer(color, alpha):
        l = Image.new("RGBA", (S, S), color + (255,)); l.putalpha(alpha); return l
    shadow = sil.filter(ImageFilter.GaussianBlur(S // 40)).point(lambda v: int(v * 0.45))
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    img = Image.alpha_composite(img, layer((0, 0, 0), ImageChops.offset(shadow, S // 64, S // 40)))
    if white:
        img = Image.alpha_composite(img, layer((250, 248, 240), sil))
        img = Image.alpha_composite(img, layer((30, 30, 30), outline))
    else:
        detail = ImageChops.subtract(sil.filter(ImageFilter.MinFilter(5)), filled).filter(ImageFilter.MinFilter(5))
        img = Image.alpha_composite(img, layer((36, 36, 42), sil))
        img = Image.alpha_composite(img, layer((205, 205, 212), detail))
    return img.resize((size, size), Image.LANCZOS)


def palette(img, path):
    img.convert("RGB").quantize(colors=256, method=Image.MEDIANCUT).save(path, optimize=True)


def checker(w, h, sq, alpha):
    img = Image.new("RGB", (w, h), BG)              # RGB, so the faint squares blend in
    d = ImageDraw.Draw(img, "RGBA")
    for r in range(h // sq + 1):
        for f in range(w // sq + 1):
            if (r + f) % 2 == 0:
                d.rectangle([f * sq, r * sq, f * sq + sq - 1, r * sq + sq - 1], fill=(238, 216, 181, alpha))
    return img.convert("RGBA")


def fit(text, path, size, max_w):
    while size > 8:
        f = ImageFont.truetype(path, size)
        if f.getlength(text) <= max_w:
            return f
        size -= 1
    return ImageFont.truetype(path, size)


# The game logo: assets/art/logo-source.png is black artwork on white. Its darkness becomes
# opacity, so it can be drawn in white on the dark backgrounds (the glossy highlights in
# the original become see-through cut-outs).
os.makedirs(A("art"), exist_ok=True)
_src = Image.open(A("art", "logo-source.png")).convert("L")
LOGO_ALPHA = _src.point(lambda v: max(0, min(255, int((235 - v) * 1.25))))


def logo(width, color=(245, 245, 250)):
    img = Image.new("RGBA", LOGO_ALPHA.size, color + (255,))
    img.putalpha(LOGO_ALPHA)
    return img.resize((width, round(LOGO_ALPHA.size[1] * width / LOGO_ALPHA.size[0])), Image.LANCZOS)


def with_shadow(base, img, pos, blur=6, off=(4, 6)):
    sh = Image.new("RGBA", img.size, (0, 0, 0, 255))
    sh.putalpha(img.getchannel("A").filter(ImageFilter.GaussianBlur(blur)).point(lambda v: v // 2))
    base.alpha_composite(sh, (pos[0] + off[0], pos[1] + off[1]))
    base.alpha_composite(img, pos)


# Main menu logo (drawn 1:1), with its shadow baked in
title = Image.new("RGBA", (318, 280), (0, 0, 0, 0))
with_shadow(title, logo(300), (2, 2))
title.save(A("art", "title.png"))

# LiveArea background (840x500). The Start gate covers about x 270-570, y 130-305,
# and the system's round icons sit along the top middle, so the art stays on the sides.
# the Floating pieces blue, with a scatter of soft light specks
bg = Image.new("RGB", (840, 500))
_d = ImageDraw.Draw(bg)
for _y in range(500):
    _t = _y / 499
    _d.line([(0, _y), (839, _y)], fill=(int(14 - 6 * _t), int(40 + 34 * _t), int(82 + 10 * _t)))
bg = bg.convert("RGBA")
import random as _random
_random.seed(3)
_specks = Image.new("RGBA", (840, 500), (0, 0, 0, 0))
_sd = ImageDraw.Draw(_specks)
for _ in range(34):
    _x, _y, _r = _random.randint(0, 839), _random.randint(0, 499), _random.randint(2, 4)
    _sd.ellipse([_x - _r, _y - _r, _x + _r, _y + _r], fill=(220, 245, 255, 70))
bg.alpha_composite(_specks.filter(ImageFilter.GaussianBlur(1.5)))
d = ImageDraw.Draw(bg)
title = fit("CHESS", INTER_BOLD, 76, 225)
d.text((42, 150), "VITA", font=title, fill=GOLD)
d.text((42, 150 + int(title.size * 1.05)), "CHESS", font=title, fill=WHITE)
d.text((44, 330), "Play  \u00b7  Puzzles  \u00b7  Learn", font=fit("Play  \u00b7  Puzzles  \u00b7  Learn", INTER, 22, 220),
       fill=(190, 194, 205))
d.text((44, 452), "by " + AUTHOR, font=ImageFont.truetype(INTER, 19), fill=(150, 156, 170))
with_shadow(bg, logo(250), (575, 170))
palette(bg, A("sce_sys", "livearea", "contents", "bg.png"))

# Start gate (280x158)
gate = Image.new("RGBA", (280, 158), BG + (255,))
with_shadow(gate, logo(130), (8, 24), blur=3, off=(2, 3))
gd = ImageDraw.Draw(gate)
gf = fit("CHESS", INTER_BOLD, 36, 118)
gd.text((150, 40), "VITA", font=gf, fill=GOLD)
gd.text((150, 40 + int(gf.size * 1.05)), "CHESS", font=gf, fill=WHITE)
palette(gate, A("sce_sys", "livearea", "contents", "startup.png"))

# Controller button icons for on-screen hints (assets/art/buttons/), drawn at 4x and shrunk
BTN = 26
os.makedirs(A("art", "buttons"), exist_ok=True)


def button(name, draw_symbol, w=BTN):
    S = 4
    img = Image.new("RGBA", (w * S, BTN * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if w == BTN:
        d.ellipse([S, S, (w - 1) * S, (BTN - 1) * S], fill=(46, 49, 58, 255), outline=(110, 116, 130, 255), width=S)
    else:
        d.rounded_rectangle([S, 3 * S, (w - 1) * S, (BTN - 3) * S], radius=8 * S, fill=(46, 49, 58, 255),
                            outline=(110, 116, 130, 255), width=S)
    draw_symbol(d, w * S, BTN * S)
    img.resize((w, BTN), Image.LANCZOS).save(A("art", "buttons", name + ".png"))


def cross(d, W, H):
    c, r, t = W / 2, W * 0.24, W * 0.075
    d.line([c - r, c - r, c + r, c + r], fill=(110, 170, 255), width=int(t * 1.6))
    d.line([c - r, c + r, c + r, c - r], fill=(110, 170, 255), width=int(t * 1.6))


def circle(d, W, H):
    c, r = W / 2, W * 0.25
    d.ellipse([c - r, c - r, c + r, c + r], outline=(255, 105, 110), width=int(W * 0.11))


def triangle(d, W, H):
    c, r = W / 2, W * 0.3
    pts = [(c, c - r), (c + r * 0.95, c + r * 0.62), (c - r * 0.95, c + r * 0.62)]
    d.polygon(pts, outline=(90, 220, 160), width=int(W * 0.1))


def square(d, W, H):
    c, r = W / 2, W * 0.22
    d.rectangle([c - r, c - r, c + r, c + r], outline=(255, 130, 200), width=int(W * 0.1))


def dpad(highlight):
    def draw(d, W, H):
        c, a, t = W / 2, W * 0.3, W * 0.13
        for arm, box in (("up", [c - t, c - a, c + t, c]), ("down", [c - t, c, c + t, c + a]),
                         ("left", [c - a, c - t, c, c + t]), ("right", [c, c - t, c + a, c + t])):
            d.rectangle(box, fill=(235, 235, 240) if arm in highlight else (120, 126, 140))
    return draw


def label(text):
    def draw(d, W, H):
        f = ImageFont.truetype(INTER_BOLD, int(H * 0.36))
        d.text((W / 2, H / 2), text, font=f, fill=(225, 228, 235), anchor="mm")
    return draw


button("cross", cross)
button("circle", circle)
button("triangle", triangle)
button("square", square)
button("dpad", dpad(("up", "down", "left", "right")))
button("updown", dpad(("up", "down")))
button("leftright", dpad(("left", "right")))
button("l", label("L"), w=36)
button("r", label("R"), w=36)
button("start", label("START"), w=58)
button("select", label("SELECT"), w=62)

# Trophy icons (32px), gold for unlocked and grey with a lock for locked
def trophy(color, locked):
    Z = 4 * 32
    img = Image.new("RGBA", (Z, Z), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.pieslice([24, 8, 104, 88], 0, 180, fill=color)                 # cup
    d.rectangle([24, 8, 104, 48], fill=color)
    d.arc([6, 18, 40, 58], 90, 270, fill=color, width=8)             # handles
    d.arc([88, 18, 122, 58], 270, 90, fill=color, width=8)
    d.rectangle([56, 86, 72, 102], fill=color)                       # stem
    d.rectangle([36, 102, 92, 116], fill=color)                      # base
    if locked:
        d.rectangle([44, 40, 84, 72], fill=(60, 64, 76))
        d.arc([50, 22, 78, 52], 180, 360, fill=(60, 64, 76), width=6)
    img.resize((32, 32), Image.LANCZOS).save(A("art", "trophy" + ("-locked" if locked else "") + ".png"))


trophy((255, 200, 80), False)
trophy((120, 126, 140), True)

# Hint arrow pieces (white, coloured when drawn): a body segment and a head pointing right
body = Image.new("RGBA", (16, 16), (255, 255, 255, 255))
body.save(A("art", "arrow-body.png"))
head = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
ImageDraw.Draw(head).polygon([(4, 4), (124, 64), (4, 124)], fill=(255, 255, 255, 255))
head.resize((32, 32), Image.LANCZOS).save(A("art", "arrow-head.png"))

# Animated menu backgrounds (assets/art/menubg/): the pieces are drawn here, the motion in ui.lua
MB = A("art", "menubg")
os.makedirs(MB, exist_ok=True)


def vgradient(c1, c2, w=960, h=544):
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / (h - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(c1[k] + (c2[k] - c1[k]) * t) for k in range(3)))
    return img


vgradient((14, 40, 82), (8, 74, 92)).save(os.path.join(MB, "floating.png"))
vgradient((12, 30, 92), (44, 12, 72)).save(os.path.join(MB, "waves.png"))

# Floating pieces: 6 pieces x 3 depths. Far ones are small, faint and soft.
for depth, (size, alpha, blur) in enumerate([(90, 0.13, 3.0), (150, 0.17, 1.6), (220, 0.21, 0.6)]):
    for kind, ch in zip("KQRBNP", "\u265A\u265B\u265C\u265D\u265E\u265F"):
        S = size + 24
        m = Image.new("L", (S * 2, S * 2), 0)
        ImageDraw.Draw(m).text((S, int(S * 1.06)), ch, font=ImageFont.truetype(SYMBOLS, size * 2), fill=255, anchor="mm")
        m = m.resize((S, S), Image.LANCZOS)
        if blur:
            m = m.filter(ImageFilter.GaussianBlur(blur))
        sprite = Image.new("RGBA", (S, S), (190, 232, 255, 0))
        sprite.putalpha(m.point(lambda v: int(v * alpha)))
        sprite.save(os.path.join(MB, "piece%d%s.png" % (depth, kind)))

# A soft speck of light
dot = Image.new("L", (24, 24), 0)
ImageDraw.Draw(dot).ellipse([6, 6, 18, 18], fill=255)
speck = Image.new("RGBA", (24, 24), (220, 245, 255, 0))
speck.putalpha(dot.filter(ImageFilter.GaussianBlur(3)).point(lambda v: int(v * 0.5)))
speck.save(os.path.join(MB, "speck.png"))

# One column of a glowing wave ribbon (white; coloured when drawn): a bright crest that fades downward
band = Image.new("RGBA", (4, 140), (255, 255, 255, 0))
alpha = []
for y in range(140):
    if y < 6:
        a = 40 + y * 22           # soft rise to the crest
    elif y < 14:
        a = 170 - (y - 6) * 14
    else:
        a = int(60 * (1 - (y - 14) / 126) ** 1.6)
    alpha.append(max(0, min(255, a)))
col = Image.new("L", (1, 140)); col.putdata(alpha)
band.putalpha(col.resize((4, 140)))
band.save(os.path.join(MB, "ribbon.png"))

# Bubble icon: the white logo on the Floating pieces blue
icon = Image.new("RGB", (128, 128))
_d = ImageDraw.Draw(icon)
for _y in range(128):
    _t = _y / 127
    _d.line([(0, _y), (127, _y)], fill=(int(14 - 6 * _t), int(40 + 34 * _t), int(82 + 10 * _t)))
icon = icon.convert("RGBA")
_l = logo(108)
with_shadow(icon, _l, ((128 - _l.size[0]) // 2, (128 - _l.size[1]) // 2 + 3), blur=3, off=(2, 3))
palette(icon, A("sce_sys", "icon0.png"))
print("Art written.")
