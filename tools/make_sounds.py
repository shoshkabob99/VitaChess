#!/usr/bin/env python3
"""Synthesize the sound effects in assets/sounds/ (needs numpy)."""
import os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
import numpy as np, wave
SR = 48000
rng = np.random.default_rng(7)
def env(n, a=0.002, d=0.05):
    t = np.arange(n)/SR
    return np.minimum(t/a, 1.0) * np.exp(-t/d)
def tock(freq, dur, decay, noise=0.6, vol=0.8):
    n = int(SR*dur); t = np.arange(n)/SR
    body = np.sin(2*np.pi*freq*t) + 0.5*np.sin(2*np.pi*freq*2.7*t)
    nz = rng.standard_normal(n); nz = np.convolve(nz, np.ones(12)/12, mode="same")
    return vol * env(n, 0.0008, decay) * (body*(1-noise) + nz*noise*2)
def save(name, x):
    x = x / max(1e-9, np.abs(x).max()) * 0.85
    pcm = (x*32767).astype(np.int16)
    st = np.repeat(pcm[:,None], 2, axis=1).flatten()
    with wave.open(os.path.join(ROOT, "assets", "sounds", name + ".wav"),"wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(st.tobytes())
def pad(x, total):
    out = np.zeros(int(SR*total)); out[:len(x)] += x; return out
save("move", pad(tock(420, 0.09, 0.018), 0.12))
a = pad(tock(300, 0.12, 0.025, noise=0.7), 0.2); b = tock(520, 0.08, 0.015); a[int(SR*0.035):int(SR*0.035)+len(b)] += b*0.8
save("capture", a)
n = int(SR*0.25); t = np.arange(n)/SR
chk = pad(tock(600,0.06,0.012),0.25) + 0.5*env(n,0.003,0.07)*np.sin(2*np.pi*988*t)
save("check", chk)
n = int(SR*0.9); t = np.arange(n)/SR
e = 0.6*env(n,0.004,0.35)*np.sin(2*np.pi*523.25*t)
d = int(SR*0.16); e2 = np.zeros(n); e2[d:] = 0.6*env(n-d,0.004,0.4)*np.sin(2*np.pi*783.99*t[:n-d])
save("end", e + e2 + 0.15*env(n,0.004,0.3)*np.sin(2*np.pi*1046.5*t))

# Menu sounds: a soft tick for moving, a bright two-note click for selecting, a low tick for back
n = int(SR * 0.05); t = np.arange(n) / SR
save("tick", pad(0.5 * env(n, 0.001, 0.012) * np.sin(2 * np.pi * 1800 * t), 0.06))
n = int(SR * 0.12); t = np.arange(n) / SR
sel = 0.6 * env(n, 0.001, 0.03) * np.sin(2 * np.pi * 1320 * t)
d = int(SR * 0.04); sel[d:] += 0.5 * env(n - d, 0.001, 0.04) * np.sin(2 * np.pi * 1760 * t[:n - d])
save("select", pad(sel, 0.14))
n = int(SR * 0.08); t = np.arange(n) / SR
save("back", pad(0.55 * env(n, 0.001, 0.02) * np.sin(2 * np.pi * 900 * t), 0.09))

# Trophy unlocked: a bright rising arpeggio
n = int(SR * 0.7); t = np.arange(n) / SR
tro = np.zeros(n)
for i, f in enumerate((784, 988, 1175, 1568)):
    d = int(SR * 0.07 * i)
    tro[d:] += 0.45 * env(n - d, 0.002, 0.25) * np.sin(2 * np.pi * f * t[:n - d])
save("trophy", tro)
