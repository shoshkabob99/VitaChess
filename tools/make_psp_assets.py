#!/usr/bin/env python3
"""Make the PSP versions of the assets in assets/psp/ (needs Pillow and numpy).

  pieces/<set>/*.png  32x32 sprites shrunk from assets/pieces (the PSP board uses 32px squares)
  sounds/*.wav        the sound effects resampled to 44.1 kHz
  ICON0.PNG           the 144x80 XMB icon
"""
import os
import wave
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC, OUT = os.path.join(ROOT, "assets"), os.path.join(ROOT, "assets", "psp")
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"   # change on Windows/macOS

# Pieces: shrink in two steps for crisp results
for set_name in sorted(os.listdir(os.path.join(SRC, "pieces"))):
    src_dir = os.path.join(SRC, "pieces", set_name)
    dst_dir = os.path.join(OUT, "pieces", set_name)
    os.makedirs(dst_dir, exist_ok=True)
    for name in sorted(os.listdir(src_dir)):
        img = Image.open(os.path.join(src_dir, name)).convert("RGBA")
        method = Image.NEAREST if set_name == "pixel" else Image.LANCZOS
        img.resize((32, 32), method).save(os.path.join(dst_dir, name))

# Sounds: 48 kHz -> 44.1 kHz, 16-bit stereo
os.makedirs(os.path.join(OUT, "sounds"), exist_ok=True)
for name in sorted(os.listdir(os.path.join(SRC, "sounds"))):
    with wave.open(os.path.join(SRC, "sounds", name)) as w:
        rate, ch = w.getframerate(), w.getnchannels()
        pcm = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).reshape(-1, ch).astype(np.float64)
    n_out = int(len(pcm) * 44100 / rate)
    t_out = np.arange(n_out) * rate / 44100
    res = np.stack([np.interp(t_out, np.arange(len(pcm)), pcm[:, c]) for c in range(ch)], axis=1)
    with wave.open(os.path.join(OUT, "sounds", name), "wb") as w:
        w.setnchannels(ch); w.setsampwidth(2); w.setframerate(44100)
        w.writeframes(np.clip(res, -32768, 32767).astype(np.int16).tobytes())

# XMB icon
icon = Image.new("RGBA", (144, 80), (28, 30, 36, 255))
d = ImageDraw.Draw(icon)
for f in range(9):
    for r in range(5):
        if (f + r) % 2 == 0:
            d.rectangle([f * 16, r * 16, f * 16 + 15, r * 16 + 15], fill=(238, 216, 181, 40))
knight = Image.open(os.path.join(SRC, "pieces", "classic", "wN.png")).convert("RGBA").resize((60, 60), Image.LANCZOS)
icon.alpha_composite(knight, (6, 10))
d.text((68, 18), "VITA", font=ImageFont.truetype(BOLD, 20), fill=(255, 200, 90, 255))
d.text((68, 42), "CHESS", font=ImageFont.truetype(BOLD, 20), fill=(240, 240, 240, 255))
icon.save(os.path.join(OUT, "ICON0.PNG"))
print("PSP assets written to assets/psp/")
