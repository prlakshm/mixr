#!/usr/bin/env python3
"""Synthesize Mixr's copyright-free demo songs (App Store screenshots, UI tests).

Every sample is generated here from oscillators and noise: no recordings,
no samples, no third-party material. Titles and artists are made up.

    python3 Scripts/generate_demo_songs.py <out_dir>

Writes "<Artist> - <Title>.m4a" (AAC, via afconvert) into out_dir, tagged
with title, artist, tempo and key (Scripts/tag_audio_metadata.swift) so the
editor shows the true BPM and key instead of an on-device estimate.
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np
from scipy.signal import lfilter

SR = 44100
RNG = np.random.default_rng(7)

# (artist, title, bpm, root midi note, minor?, chord degrees, arrangement in 8-bar blocks)
# Keys: Velvet Static A minor, Paper Suns C major, Night Signals F minor.
# Arrangement letters: i intro, v verse, b build, d drop, k break, o outro.
SONGS = [
    ("Luma Vale", "Velvet Static", 122, 57, True, [0, 5, 3, 7], "ivbdkbdo"),
    ("Sable Coast", "Paper Suns", 118, 60, False, [0, 7, 9, 5], "ivvbdkdo"),
    ("Arlo Vance", "Night Signals", 124, 53, True, [0, 8, 3, 10], "ibdvkbdo"),
]

MAJOR = [0, 2, 4, 5, 7, 9, 11]
MINOR = [0, 2, 3, 5, 7, 8, 10]


def midi_hz(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def env(n, attack, release):
    e = np.ones(n)
    a = min(n, int(attack * SR))
    r = min(n - a, int(release * SR))
    if a:
        e[:a] = np.linspace(0, 1, a)
    if r:
        e[n - r:] = np.linspace(1, 0, r)
    return e


def saw(freq, n, detune=0.0):
    t = np.arange(n) / SR
    out = np.zeros(n)
    for d in (-detune, 0.0, detune):
        f = freq * (1 + d)
        out += 2 * ((t * f) % 1.0) - 1
    return out / 3


def lowpass(x, cutoff):
    # One-pole low-pass.
    a = np.exp(-2 * np.pi * cutoff / SR)
    return lfilter([1 - a], [1, -a], x)


def kick(n):
    t = np.arange(n) / SR
    f = 50 + 110 * np.exp(-t * 28)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7)


def clap(n):
    t = np.arange(n) / SR
    noise = RNG.uniform(-1, 1, n)
    return lowpass(noise, 3500) * np.exp(-t * 22) * 1.6


def hat(n):
    t = np.arange(n) / SR
    noise = RNG.uniform(-1, 1, n)
    hp = noise - lowpass(noise, 6000)
    return hp * np.exp(-t * 60)


def render(bpm, root, minor, degrees, arrangement):
    beat = 60.0 / bpm
    bar = beat * 4
    block_bars = 8
    total = int(len(arrangement) * block_bars * bar * SR)
    left = np.zeros(total)
    right = np.zeros(total)
    scale = MINOR if minor else MAJOR

    kick_s, clap_s, hat_s = kick(int(0.35 * SR)), clap(int(0.25 * SR)), hat(int(0.08 * SR))

    def add(buf, sig, start, gain=1.0):
        s = int(start * SR)
        if s >= total:
            return
        e = min(total, s + len(sig))
        buf[s:e] += sig[: e - s] * gain

    def add_st(sig, start, gain=1.0, pan=0.0):
        add(left, sig, start, gain * (1 - max(0, pan)))
        add(right, sig, start, gain * (1 + min(0, pan)))

    for b, section in enumerate(arrangement):
        for local_bar in range(block_bars):
            bar_index = b * block_bars + local_bar
            t0 = bar_index * bar
            chord_root = root + degrees[local_bar % len(degrees)]
            third = 3 if minor and degrees[local_bar % len(degrees)] in (0, 5) else 4
            if not minor and degrees[local_bar % len(degrees)] == 9:
                third = 3
            chord = [chord_root, chord_root + third, chord_root + 7, chord_root + 12]
            rise = local_bar / block_bars

            drums = section in "vbdo"
            full = section == "d"

            # Pad: every section, brighter on drops.
            pad_n = int(bar * SR)
            pad = sum(saw(midi_hz(n), pad_n, 0.004) for n in chord) / len(chord)
            cutoff = {"i": 900, "v": 1200, "b": 900 + 3000 * rise, "d": 4200, "k": 700, "o": 900}[section]
            pad = lowpass(pad, cutoff) * env(pad_n, 0.05, 0.2)
            pad_gain = {"i": 0.20, "v": 0.16, "b": 0.18, "d": 0.20, "k": 0.26, "o": 0.18}[section]
            add_st(pad, t0, pad_gain, -0.15)
            add_st(pad, t0 + 0.012, pad_gain, 0.15)

            for q in range(4):
                tq = t0 + q * beat
                if drums and not (section == "b" and local_bar == block_bars - 1 and q == 3):
                    add_st(kick_s, tq, 0.9 if full else 0.7)
                if drums and q in (1, 3):
                    add_st(clap_s, tq, 0.28 if full else 0.18, 0.05)
                if section in "vdbo":
                    add_st(hat_s, tq + beat / 2, 0.22 if full else 0.14, 0.3)
                if section == "b" and local_bar >= block_bars - 2:
                    for s16 in range(4):
                        add_st(clap_s, tq + s16 * beat / 4, 0.06 + 0.12 * rise)

                # Bass: off-beat eighths on drops, roots on verses.
                if section in "vdo":
                    bn = int(beat / 2 * SR)
                    bass = lowpass(saw(midi_hz(chord_root - 24), bn), 380 if full else 260)
                    bass *= env(bn, 0.004, 0.06)
                    add_st(bass, tq + (beat / 2 if full else 0), 0.55)

            # Lead: an eighth-note figure on drops and the last verse bars.
            if full or (section == "v" and local_bar >= 4):
                pattern = [0, 2, 4, 2, 5, 4, 2, 1]
                for e8, deg in enumerate(pattern):
                    note = root + 12 + scale[deg % 7] + (12 if deg >= 7 else 0)
                    n8 = int(beat / 2 * SR)
                    lead = lowpass(saw(midi_hz(note), n8, 0.006), 2600) * env(n8, 0.005, 0.08)
                    add_st(lead, t0 + e8 * beat / 2, 0.12 if full else 0.07, 0.25 if e8 % 2 else -0.25)

    # Fade in / out, then normalize to about -3 dBFS.
    fade = int(2.0 * SR)
    ramp = np.linspace(0, 1, fade)
    for ch in (left, right):
        ch[:fade] *= ramp
        ch[-fade:] *= ramp[::-1]
    stereo = np.stack([left, right], axis=1)
    stereo *= 0.7 / max(1e-9, np.abs(stereo).max())
    return stereo


def write_wav(path, stereo):
    pcm = (np.clip(stereo, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "output/demo-songs"
    os.makedirs(out_dir, exist_ok=True)
    here = os.path.dirname(os.path.abspath(__file__))
    with tempfile.TemporaryDirectory() as tmp:
        tagger = os.path.join(tmp, "tag_audio_metadata")
        subprocess.run(["xcrun", "swiftc", "-O", "-suppress-warnings",
                        os.path.join(here, "tag_audio_metadata.swift"), "-o", tagger], check=True)
        for artist, title, bpm, root, minor, degrees, arrangement in SONGS:
            name = f"{artist} - {title}"
            wav = os.path.join(tmp, name + ".wav")
            write_wav(wav, render(bpm, root, minor, degrees, arrangement))
            untagged = os.path.join(tmp, name + ".m4a")
            subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "192000", wav, untagged], check=True)
            key = NOTE_NAMES[root % 12] + ("m" if minor else "")
            m4a = os.path.join(out_dir, name + ".m4a")
            subprocess.run([tagger, untagged, m4a, title, artist, str(bpm), key], check=True)
            print(m4a)


if __name__ == "__main__":
    main()
