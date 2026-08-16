#!/usr/bin/env python3
"""Generates Mixr's built-in V1 sound-effect assets.

Reproducible, dependency-free (stdlib only), deterministic (seeded RNG).
Every sound is synthesized from noise/sines — no copyrighted samples.

Output: 44.1 kHz mono 16-bit PCM WAVs in Mixr/Resources/SFX/,
peak-normalized to -3 dBFS with 8 ms edge fades (no clicks).

Run:  python3 Scripts/generate_sfx_assets.py
"""

import math
import os
import random
import struct
import wave

SR = 44100
PEAK = 0.708  # -3 dBFS
EDGE_FADE_SEC = 0.008
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "Mixr", "Resources", "SFX")


# ── Small DSP toolkit ────────────────────────────────────────────────

class OnePoleLP:
    def __init__(self):
        self.y = 0.0

    def process(self, x, fc):
        a = 1.0 - math.exp(-2.0 * math.pi * max(1.0, fc) / SR)
        self.y += a * (x - self.y)
        return self.y


class SVF:
    """Chamberlin state-variable filter — 12 dB/oct low/band/high."""

    def __init__(self):
        self.low = 0.0
        self.band = 0.0

    def process(self, x, fc, q):
        f = 2.0 * math.sin(math.pi * min(fc, SR * 0.22) / SR)
        self.low += f * self.band
        high = x - self.low - (1.0 / max(q, 0.5)) * self.band
        self.band += f * high
        return self.low, self.band, high


def exp_interp(a, b, t):
    """Exponential interpolation a→b for t in 0…1 (both positive)."""
    return a * math.pow(b / a, min(max(t, 0.0), 1.0))


def soft_clip(x, drive=1.0):
    return math.tanh(x * drive)


def normalize(samples, peak=PEAK):
    m = max(1e-9, max(abs(s) for s in samples))
    g = peak / m
    return [s * g for s in samples]


def edge_fades(samples, fade_sec=EDGE_FADE_SEC):
    n = len(samples)
    f = min(int(fade_sec * SR), n // 2)
    for i in range(f):
        g = i / f
        samples[i] *= g
        samples[n - 1 - i] *= g
    return samples


def write_wav(name, samples):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    samples = edge_fades(normalize(samples))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples
        )
        w.writeframes(frames)
    print(f"  wrote {name}  ({len(samples) / SR:.2f}s)")


def silence(duration):
    return [0.0] * int(duration * SR)


def add_into(dest, src, start_sec, gain=1.0):
    start = int(start_sec * SR)
    for i, s in enumerate(src):
        j = start + i
        if 0 <= j < len(dest):
            dest[j] += s * gain


# ── Sound designs ────────────────────────────────────────────────────

def gen_riser(duration=4.0, seed=1):
    """Filtered noise + sine rising in brightness/pitch, gated near the top."""
    rng = random.Random(seed)
    n = int(duration * SR)
    svf = SVF()
    out = []
    phase = 0.0
    for i in range(n):
        t = i / n
        fc = exp_interp(300.0, 7000.0, t)
        q = 1.0 + 3.0 * t
        _, band, _ = svf.process(rng.uniform(-1, 1), fc, q)

        freq = exp_interp(110.0, 440.0, t)
        phase += 2.0 * math.pi * freq / SR
        tone = math.sin(phase) * 0.4

        amp = exp_interp(0.12, 1.0, t)
        # 16th-note gate tightens the last quarter — trance-build energy.
        gate = 1.0
        if t > 0.75:
            g = math.sin(2.0 * math.pi * (i / SR) * 8.0)
            gate = 0.62 + 0.38 * (1.0 if g > 0 else 0.35)
        out.append((band * 1.6 + tone) * amp * gate)
    return out


def gen_downlifter(duration=2.0, seed=2):
    """Brightness and pitch falling away after a drop."""
    rng = random.Random(seed)
    n = int(duration * SR)
    svf = SVF()
    out = []
    phase = 0.0
    for i in range(n):
        t = i / n
        fc = exp_interp(5000.0, 250.0, t)
        _, band, _ = svf.process(rng.uniform(-1, 1), fc, 2.0)
        freq = exp_interp(400.0, 70.0, t)
        phase += 2.0 * math.pi * freq / SR
        tone = math.sin(phase) * 0.5 * (1.0 - t)
        amp = exp_interp(1.0, 0.14, t)
        out.append((band * 1.5 + tone) * amp)
    return out


def gen_impact(duration=1.0, seed=3):
    """Sub thump with pitch glide + fast bright noise burst."""
    rng = random.Random(seed)
    n = int(duration * SR)
    lp = OnePoleLP()
    out = []
    phase = 0.0
    for i in range(n):
        ts = i / SR
        t = i / n
        freq = exp_interp(85.0, 42.0, min(1.0, ts / 0.5))
        phase += 2.0 * math.pi * freq / SR
        sub = math.sin(phase) * math.exp(-ts / 0.35)
        burst = lp.process(rng.uniform(-1, 1), 2500.0) * math.exp(-ts / 0.06) * 2.2
        out.append(soft_clip(sub * 1.1 + burst, 1.2) * (1.0 - t * 0.15))
    return out


def gen_sweep(duration, rising, seed):
    """Whoosh — LP noise brightening (up) or darkening (down)."""
    rng = random.Random(seed)
    n = int(duration * SR)
    svf = SVF()
    out = []
    peak_at = 0.72 if rising else 0.28
    for i in range(n):
        t = i / n
        fc = exp_interp(500.0, 9000.0, t) if rising else exp_interp(9000.0, 400.0, t)
        low, band, _ = svf.process(rng.uniform(-1, 1), fc, 1.4)
        x = (t - peak_at) / (0.62 if rising else 0.62)
        amp = math.exp(-x * x * 3.2)
        out.append((low * 0.8 + band * 0.9) * amp)
    return out


def gen_reverse_cymbal(duration=1.5, seed=6):
    """Bright noise swelling exponentially into a short accent hit."""
    rng = random.Random(seed)
    n = int(duration * SR)
    lp = OnePoleLP()
    out = []
    for i in range(n):
        t = i / n
        ts = i / SR
        x = rng.uniform(-1, 1)
        bright = x - lp.process(x, 3800.0)
        swell = math.exp((t - 1.0) * 5.2)
        shimmer = 1.0 + 0.18 * math.sin(2.0 * math.pi * 6.0 * ts)
        out.append(bright * swell * shimmer)
    # Accent burst in the final 45 ms
    accent = int(0.045 * SR)
    rng2 = random.Random(seed + 100)
    for i in range(accent):
        j = n - accent + i
        out[j] += rng2.uniform(-1, 1) * (1.0 - i / accent) * 0.8
    return out


def gen_crash(duration=1.0, seed=7):
    """Bright burst with a long decay."""
    rng = random.Random(seed)
    n = int(duration * SR)
    lp = OnePoleLP()
    out = []
    for i in range(n):
        ts = i / SR
        x = rng.uniform(-1, 1)
        bright = x - lp.process(x, 3200.0)
        out.append(bright * math.exp(-ts / 0.30))
    return out


def _snare_hit(seed):
    """One snare-ish hit: 190 Hz body + bright noise, ~120 ms."""
    rng = random.Random(seed)
    n = int(0.12 * SR)
    lp = OnePoleLP()
    hit = []
    phase = 0.0
    for i in range(n):
        ts = i / SR
        phase += 2.0 * math.pi * 190.0 / SR
        body = math.sin(phase) * math.exp(-ts / 0.045) * 0.8
        x = rng.uniform(-1, 1)
        snap = (x - lp.process(x, 1600.0)) * math.exp(-ts / 0.055) * 1.1
        hit.append(body + snap)
    return hit


def gen_snare_build(duration=4.0, bpm=128.0, seed=8):
    """Snare hits doubling in density — 8ths → 16ths → 32nds → roll."""
    out = silence(duration)
    beat = 60.0 / bpm
    t = 0.0
    idx = 0
    while t < duration - 0.05:
        progress = t / duration
        if progress < 0.5:
            step = beat / 2.0     # 8th notes
        elif progress < 0.78:
            step = beat / 4.0     # 16th notes
        elif progress < 0.93:
            step = beat / 8.0     # 32nd notes
        else:
            step = beat / 16.0    # roll
        gain = 0.45 + 0.55 * progress
        add_into(out, _snare_hit(seed + idx), t, gain)
        t += step
        idx += 1
    return out


def _clap(seed):
    """3 micro-bursts 12 ms apart + short tail."""
    rng = random.Random(seed)
    n = int(0.16 * SR)
    svf = SVF()
    clap = [0.0] * n
    for b in range(3):
        start = int(b * 0.012 * SR)
        for i in range(int(0.010 * SR)):
            j = start + i
            if j < n:
                _, band, _ = svf.process(rng.uniform(-1, 1), 2100.0, 1.8)
                clap[j] += band * 2.0
    for i in range(n):
        ts = i / SR
        if ts > 0.036:
            _, band, _ = svf.process(rng.uniform(-1, 1), 1700.0, 1.5)
            clap[i] += band * 1.6 * math.exp(-(ts - 0.036) / 0.05)
    return clap


def gen_clap_fill(duration=2.0, bpm=128.0, seed=9):
    """Rhythmic claps on 8ths with a crescendo and doubled final hits."""
    out = silence(duration)
    beat = 60.0 / bpm
    step = beat / 2.0
    t = 0.0
    idx = 0
    while t < duration - 0.1:
        progress = t / duration
        add_into(out, _clap(seed + idx), t, 0.5 + 0.5 * progress)
        if progress > 0.72:
            add_into(out, _clap(seed + 50 + idx), t + step / 2.0, 0.45 + 0.5 * progress)
        t += step
        idx += 1
    return out


def gen_bass_drop(duration=1.5, seed=10):
    """Sub sine pitch drop with gentle saturation."""
    n = int(duration * SR)
    out = []
    phase = 0.0
    for i in range(n):
        ts = i / SR
        glide = min(1.0, ts / 1.1)
        freq = exp_interp(160.0, 32.0, glide)
        phase += 2.0 * math.pi * freq / SR
        amp = 1.0 if ts < 1.1 else math.exp(-(ts - 1.1) / 0.16)
        out.append(soft_clip(math.sin(phase) * 1.25, 1.3) * amp)
    return out


def gen_tape_stop(duration=1.0, seed=11):
    """A tone cluster whose playback speed and level fall to zero."""
    rng = random.Random(seed)
    n = int(duration * SR)
    lp = OnePoleLP()
    freqs = [220.0, 277.2, 329.6, 440.0]
    phases = [0.0] * len(freqs)
    out = []
    for i in range(n):
        t = i / n
        speed = math.pow(max(0.0, 1.0 - t), 1.6)
        sample = 0.0
        for k, f in enumerate(freqs):
            phases[k] += 2.0 * math.pi * f * speed / SR
            sample += math.sin(phases[k]) * (0.28 - 0.04 * k)
        bed = lp.process(rng.uniform(-1, 1), 1200.0 * speed + 60.0) * 0.35
        out.append((sample + bed) * math.pow(speed, 0.8))
    return out


def gen_air_sweep(duration=2.0, seed=12):
    """Soft filtered-noise movement — atmosphere, not a statement."""
    rng = random.Random(seed)
    n = int(duration * SR)
    svf = SVF()
    out = []
    for i in range(n):
        t = i / n
        ts = i / SR
        fc = 900.0 + 600.0 * math.sin(2.0 * math.pi * 0.5 * ts)
        low, _, _ = svf.process(rng.uniform(-1, 1), max(300.0, fc), 1.1)
        amp = math.pow(math.sin(math.pi * t), 1.5)
        out.append(low * amp)
    return out


def gen_club_kick(duration=0.18, seed=21):
    """Short four-on-the-floor kick thump — soft attack, no click."""
    n = int(duration * SR)
    out = []
    phase = 0.0
    rng = random.Random(seed)
    for i in range(n):
        ts = i / SR
        t = i / max(1, n - 1)
        attack = min(1.0, t / 0.08)
        env = attack * math.exp(-12.0 * ts / max(duration, 0.01))
        freq = exp_interp(120.0, 48.0, min(1.0, ts / duration))
        phase += 2.0 * math.pi * freq / SR
        tone = math.sin(phase)
        noise = rng.uniform(-1, 1) * 0.25
        out.append((tone * 0.75 + noise) * env)
    return out


def gen_club_bass(duration=0.28, seed=22):
    """Short sub / bass-weight hit for the club pulse layer."""
    n = int(duration * SR)
    out = []
    phase = 0.0
    for i in range(n):
        ts = i / SR
        t = i / max(1, n - 1)
        attack = min(1.0, t / 0.05)
        env = attack * math.exp(-8.0 * ts / max(duration, 0.01))
        phase += 2.0 * math.pi * 45.0 / SR
        out.append(math.sin(phase) * env)
    return out


# ── Manifest ─────────────────────────────────────────────────────────

def main():
    print("Generating Mixr SFX assets →", os.path.abspath(OUT_DIR))
    write_wav("riser.wav", gen_riser(4.0))
    write_wav("downlifter.wav", gen_downlifter(2.0))
    write_wav("impact.wav", gen_impact(1.0))
    write_wav("sweep_up.wav", gen_sweep(2.0, rising=True, seed=4))
    write_wav("sweep_down.wav", gen_sweep(2.0, rising=False, seed=5))
    write_wav("reverse_cymbal.wav", gen_reverse_cymbal(1.5))
    write_wav("crash.wav", gen_crash(1.0))
    write_wav("snare_build.wav", gen_snare_build(4.0))
    write_wav("clap_fill.wav", gen_clap_fill(2.0))
    write_wav("bass_drop.wav", gen_bass_drop(1.5))
    write_wav("tape_stop.wav", gen_tape_stop(1.0))
    write_wav("air_sweep.wav", gen_air_sweep(2.0))
    write_wav("club_kick.wav", gen_club_kick(0.18))
    write_wav("club_bass.wav", gen_club_bass(0.28))
    print("Done — 14 assets.")


if __name__ == "__main__":
    main()
