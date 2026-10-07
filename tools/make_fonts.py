#!/usr/bin/env python3
"""Pre-render the game's font into crisp bitmap atlases (needs Pillow).

The Vita's built-in TrueType renderer drew some letters wrongly (ghostly
c and k, t without a crossbar) and looked soft at small sizes. Instead, every
letter is rendered here on the PC at each exact pixel size the game uses, and
the Vita just copies those pixels to the screen.

Writes assets/fonts/bitmap/<r|b><size>.png (white letters, coloured at draw time)
and a matching .fnt text file with each letter's position and spacing.
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONTS = {"r": "Inter-Regular.ttf", "b": "Inter-Bold.ttf"}
# Must match config.FONT_SIZES in src/config.lua
SIZES = [14, 15, 16, 17, 18, 20, 21, 22, 23, 26, 31, 32, 47, 54]
CHARS = [chr(c) for c in range(32, 127)]
OUT = os.path.join(ROOT, "assets", "fonts", "bitmap")
os.makedirs(OUT, exist_ok=True)

for weight, file in FONTS.items():
    for px in SIZES:
        font = ImageFont.truetype(os.path.join(ROOT, "assets", "fonts", file), px)
        ascent, descent = font.getmetrics()
        glyphs = []
        for ch in CHARS:
            box = font.getbbox(ch, anchor="ls")          # relative to the baseline
            w, h = max(0, box[2] - box[0]), max(0, box[3] - box[1])
            glyphs.append((ch, box, w, h, font.getlength(ch)))
        # shelf-pack into a 512-wide sheet with 1px gaps
        width, x, y, row_h, placed = 512, 1, 1, 0, []
        for ch, box, w, h, adv in glyphs:
            if x + w + 1 > width:
                x, y, row_h = 1, y + row_h + 1, 0
            placed.append((ch, x, y, box, w, h, adv))
            x += w + 1
            row_h = max(row_h, h)
        height = y + row_h + 1
        sheet = Image.new("L", (width, height), 0)
        draw = ImageDraw.Draw(sheet)
        lines = ["%d %d" % (ascent + descent, ascent)]
        for ch, gx, gy, box, w, h, adv in placed:
            if w and h:
                draw.text((gx - box[0], gy - box[1]), ch, font=font, fill=255, anchor="ls")
            # code  atlas x y w h  offset from (pen x, line top)  advance
            lines.append("%d %d %d %d %d %d %d %.3f" % (ord(ch), gx, gy, w, h, box[0], ascent + box[1], adv))
        rgba = Image.new("RGBA", sheet.size, (255, 255, 255, 0))
        rgba.putalpha(sheet)
        name = "%s%d" % (weight, px)
        rgba.save(os.path.join(OUT, name + ".png"))
        with open(os.path.join(OUT, name + ".fnt"), "w") as f:
            f.write("\n".join(lines) + "\n")
print("Bitmap fonts written to assets/fonts/bitmap/")
