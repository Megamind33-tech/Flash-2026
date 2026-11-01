"""Synthesise the wet-weather loops (project-owned, no third-party audio):
  rain_loop.wav       steady rainfall: soft pink-ish noise bed plus thousands of individual drop ticks
  tyre_wet_loop.wav   tyres on a wet road: band-passed hiss with a slow swish (water sheeting off the tread)
Both are seamless 4 s mono loops at 44.1 kHz (crossfaded ends).

    python3 -I tools/audio/make_rain_audio.py   ->  godot/assets/audio/rain_loop.wav, tyre_wet_loop.wav
"""
import os, wave
import numpy as np

SR = 44100
SEC = 4.0
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "godot", "assets", "audio")
rng = np.random.default_rng(27)
n = int(SR * SEC)


def onepole(x, a):
    """Simple one-pole low-pass (a: 0..1, higher = darker)."""
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def bandpass(x, lo, hi):
    f = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    f[(fr < lo) | (fr > hi)] *= 0.05
    return np.fft.irfft(f, len(x))


def loopify(x, fade=0.25):
    """Crossfade the tail into the head so the loop has no click."""
    k = int(SR * fade)
    w = np.linspace(0, 1, k)
    x = x.copy()
    x[:k] = x[:k] * w + x[-k:] * (1 - w)
    return x[:-k]


def norm(x, peak):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def write(name, x):
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
    print("wrote", path, "%.2f s" % (len(x) / SR))


# --- rain: noise bed (1/f-ish via two low-passes) + drop ticks (short decaying high-passed bursts)
white = rng.normal(0, 1, n + int(SR * 0.25))
bed = bandpass(white, 300, 9000) * 0.6 + bandpass(white, 1500, 12000) * 0.4
drops = np.zeros_like(white)
for _ in range(int(SEC * 900)):
    at = rng.integers(0, len(drops) - 600)
    length = rng.integers(60, 500)
    env = np.exp(-np.linspace(0, rng.uniform(5, 12), length))
    burst = rng.normal(0, 1, length) * env * rng.uniform(0.2, 1.0)
    drops[at:at + length] += burst
drops = bandpass(drops, 1800, 14000)
rain = norm(bed, 0.35) + norm(drops, 0.55)
write("rain_loop.wav", norm(loopify(rain), 0.6))

# --- wet tyres: hiss band 600-5000 Hz with a slow amplitude swish
white = rng.normal(0, 1, n + int(SR * 0.25))
hiss = bandpass(white, 600, 5000)
t = np.arange(len(hiss)) / SR
swish = 0.75 + 0.25 * np.sin(2 * np.pi * 0.5 * t) * np.sin(2 * np.pi * 1.3 * t + 1.0)   # 4 s periodic: loops
write("tyre_wet_loop.wav", norm(loopify(hiss * swish), 0.6))
