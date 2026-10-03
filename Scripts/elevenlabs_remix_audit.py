#!/usr/bin/env python3
"""
Mixr remix quality audit — ElevenLabs stem separation + measured DSP metrics.

Stem-separates a rendered remix (vocals / drums / bass / guitar / piano /
other) with the ElevenLabs Music stem-separation API, then measures what a
DJ hears as "bad transitions" and "no banger":

  • loudness dips / jumps     (short-term loudness, 3 s window, 100 ms hop)
  • beat-grid breaks          (drum-stem beat tracking: inter-beat anomalies)
  • trainwrecks / flams       (drum onset energy that falls OFF the beat grid)
  • mid-phrase vocal chops    (vocal stem collapses > 18 dB in < 60 ms)
  • silence, clicks, clipping, true peak, integrated loudness
  • energy arc                (per-phrase loudness + drum/bass presence)

Usage:
  export ELEVENLABS_API_KEY=...        # needs the music stem-separation scope
  Scripts/elevenlabs_remix_audit.py path/to/remix.m4a [--stems DIR] [--json out.json]
  Scripts/elevenlabs_remix_audit.py mix.wav --no-api   # DSP-only (no stems)

Requires: ffmpeg, numpy, scipy, librosa, soundfile, pyloudnorm, requests.
Stems are cached next to the input (<name>.stems/) so re-runs are free.
"""
import argparse, io, json, os, subprocess, sys, tempfile, zipfile

import numpy as np

SR = 44100


def decode(path, sr=SR, mono=False):
    ch = 1 if mono else 2
    raw = subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-i", path, "-f", "f32le", "-ac", str(ch), "-ar", str(sr), "-"],
        check=True, capture_output=True).stdout
    x = np.frombuffer(raw, dtype=np.float32)
    return x.reshape(-1, ch) if ch > 1 else x


def separate_stems(path, out_dir):
    """ElevenLabs Music stem separation → out_dir/{vocals,drums,bass,…}.mp3"""
    import requests
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        raise SystemExit("ELEVENLABS_API_KEY not set (or pass --no-api / --stems)")
    with tempfile.TemporaryDirectory() as td:
        mp3 = os.path.join(td, "in.mp3")
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", path, "-ac", "2", "-ar", "44100",
                        "-b:a", "192k", mp3], check=True)
        with open(mp3, "rb") as f:
            r = requests.post("https://api.elevenlabs.io/v1/music/stem-separation",
                              headers={"xi-api-key": key}, files={"file": f}, timeout=1200)
    if r.status_code != 200:
        raise SystemExit(f"stem separation failed: {r.status_code} {r.text[:300]}")
    os.makedirs(out_dir, exist_ok=True)
    zipfile.ZipFile(io.BytesIO(r.content)).extractall(out_dir)


# ── Metrics ─────────────────────────────────────────────────────────────

def short_term_loudness(stereo, sr=SR, win=3.0, hop=0.1):
    import pyloudnorm as pyln
    meter = pyln.Meter(sr)
    # K-weight once, then windowed mean-square (BS.1770 short-term).
    from scipy.signal import lfilter
    y = stereo.astype(np.float64)
    for f in meter._filters.values():
        y = lfilter(f.b, f.a, y, axis=0)
    ms = np.mean(y ** 2, axis=1)
    n, h = int(win * sr), int(hop * sr)
    c = np.concatenate([[0], np.cumsum(ms)])
    starts = np.arange(0, max(1, len(ms) - n), h)
    vals = (c[starts + n] - c[starts]) / n
    lufs = -0.691 + 10 * np.log10(np.maximum(vals, 1e-12))
    times = (starts + n / 2) / sr
    return times, lufs, meter.integrated_loudness(stereo)


def true_peak_db(stereo):
    from scipy.signal import resample_poly
    tp = 0.0
    for c in range(stereo.shape[1]):
        tp = max(tp, float(np.max(np.abs(resample_poly(stereo[:, c], 4, 1)))))
    return 20 * np.log10(max(tp, 1e-9))


def loudness_events(times, lufs, gate=-40.0):
    """Dips: ≥ 4 LU below the surrounding ±8 s median; jumps: ≥ 4 LU step within 1 s."""
    dips, jumps = [], []
    hop = times[1] - times[0] if len(times) > 1 else 0.1
    k = int(8 / hop)
    for i in range(len(lufs)):
        if lufs[i] < gate:
            continue
        ctx = lufs[max(0, i - k): i + k]
        ctx = ctx[ctx > gate]
        if len(ctx) < 10:
            continue
        d = np.median(ctx) - lufs[i]
        if d >= 4.0:
            dips.append((float(times[i]), float(d)))
    j = int(1.0 / hop)
    for i in range(j, len(lufs)):
        if lufs[i] > gate and lufs[i - j] > gate:
            s = lufs[i] - lufs[i - j]
            if abs(s) >= 4.0:
                jumps.append((float(times[i]), float(s)))
    return merge_events(dips), merge_events(jumps)


def merge_events(ev, gap=2.0):
    out = []
    for t, v in ev:
        if out and t - out[-1][0] < gap:
            if abs(v) > abs(out[-1][1]):
                out[-1] = (out[-1][0], v)
        else:
            out.append((t, v))
    return [{"t": round(t, 2), "db": round(v, 1)} for t, v in out]


def silence_runs(mono, sr=SR, thresh_db=-50, min_len=0.1):
    w = int(0.01 * sr)
    n = len(mono) // w
    rms = np.sqrt(np.mean(mono[: n * w].reshape(n, w) ** 2, axis=1) + 1e-20)
    q = 20 * np.log10(rms) < thresh_db
    runs, start = [], None
    for i, v in enumerate(q):
        if v and start is None:
            start = i
        elif not v and start is not None:
            if (i - start) * 0.01 >= min_len and start > 0:
                runs.append({"t": round(start * 0.01, 2), "len": round((i - start) * 0.01, 2)})
            start = None
    return runs


def clicks(mono, sr=SR):
    """Sample discontinuities far above the local derivative level."""
    d = np.abs(np.diff(mono))
    w = int(0.05 * sr)
    n = len(d) // w
    blocks = d[: n * w].reshape(n, w)
    local = np.percentile(blocks, 99, axis=1)
    peaks = blocks.max(axis=1)
    idx = np.where((peaks > 0.25) & (peaks > 6 * np.maximum(local, 1e-4)))[0]
    return [{"t": round(i * w / sr, 3), "jump": round(float(peaks[i]), 3)} for i in idx[:50]]


def beat_analysis(drums, sr=22050):
    import librosa
    oenv = librosa.onset.onset_strength(y=drums, sr=sr, hop_length=256)
    tempo, beats = librosa.beat.beat_track(onset_envelope=oenv, sr=sr, hop_length=256, tightness=400)
    bt = librosa.frames_to_time(beats, sr=sr, hop_length=256)
    tempo = float(np.atleast_1d(tempo)[0])
    breaks = []
    if len(bt) > 8:
        ibi = np.diff(bt)
        med = np.median(ibi)
        for i, v in enumerate(ibi):
            if abs(v - med) > 0.18 * med:
                breaks.append({"t": round(float(bt[i]), 2), "ibi_ratio": round(float(v / med), 2)})
    # Off-grid onset energy per 4 s window (8th-note grid from tracked beats).
    ot = librosa.times_like(oenv, sr=sr, hop_length=256)
    grid = []
    for a, b in zip(bt[:-1], bt[1:]):
        grid += [a, (a + b) / 2]
    grid = np.array(grid) if grid else np.array([0.0])
    dist = np.abs(ot[:, None] - grid[None, :]).min(axis=1) if len(grid) < 4000 else None
    flams = []
    if dist is not None:
        strong = oenv > np.percentile(oenv, 90)
        win = 4.0
        for s in np.arange(0, ot[-1] - win, 2.0):
            m = (ot >= s) & (ot < s + win) & strong
            if m.sum() < 6:
                continue
            off = oenv[m & (dist > 0.07)].sum() / (oenv[m].sum() + 1e-9)
            if off > 0.35:
                flams.append({"t": round(float(s), 1), "off_grid": round(float(off), 2)})
    return tempo, bt, merge_flams(flams), breaks


def merge_flams(f):
    out = []
    for e in f:
        if out and e["t"] - out[-1]["t_end"] <= 2.0:
            out[-1]["t_end"] = e["t"] + 4.0
            out[-1]["off_grid"] = max(out[-1]["off_grid"], e["off_grid"])
        else:
            out.append({"t": e["t"], "t_end": e["t"] + 4.0, "off_grid": e["off_grid"]})
    return out


def stem_db_curve(y, sr, hop=0.01):
    h = int(hop * sr)
    n = len(y) // h
    return 20 * np.log10(np.sqrt(np.mean(y[: n * h].reshape(n, h) ** 2, axis=1)) + 1e-9)


def vocal_chops(vocals, sr, beats):
    """Hard vocal edits: the vocal stem falls ≥ 24 dB within 30 ms from a
    sung level (> −28 dBFS). Natural phrase endings decay far slower, so on
    un-edited songs this stays near zero (calibrated on the test corpus)."""
    c = stem_db_curve(vocals, sr, hop=0.005)
    out = []
    for i in range(8, len(c) - 30):
        before = c[i - 8: i].mean()
        after = c[i + 6: i + 30].mean()
        if before > -28 and before - after >= 24 and c[i + 6] < before - 20:
            t = i * 0.005
            near_beat = len(beats) and np.min(np.abs(beats - t)) < 0.06
            if not out or t - out[-1]["t"] > 1.0:
                out.append({"t": round(t, 2), "drop_db": round(float(before - after), 1), "on_beat": bool(near_beat)})
    return out


def phrase_arc(times, lufs, stems, sr, bpm, n_bars=8):
    bar = 240.0 / max(bpm, 60)
    span = bar * n_bars
    total = times[-1] if len(times) else 0
    out = []
    t = 0.0
    while t < total:
        m = (times >= t) & (times < t + span)
        row = {"t": round(t, 1), "lufs": round(float(np.median(lufs[m])), 1) if m.any() else None}
        for name in ("vocals", "drums", "bass"):
            if name in stems:
                y = stems[name][int(t * sr): int((t + span) * sr)]
                row[name] = round(20 * np.log10(np.sqrt(np.mean(y ** 2)) + 1e-9), 1) if len(y) else None
        out.append(row)
        t += span
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mix")
    ap.add_argument("--stems", help="directory with separated stems (skips the API)")
    ap.add_argument("--no-api", action="store_true")
    ap.add_argument("--json")
    ap.add_argument("--joins", help="comma-separated join times (s) to report around")
    a = ap.parse_args()

    stereo = decode(a.mix)
    mono = stereo.mean(axis=1)
    dur = len(mono) / SR

    stem_dir = a.stems or os.path.splitext(a.mix)[0] + ".stems"
    stems = {}
    if not a.no_api:
        if not os.path.isdir(stem_dir) or not os.listdir(stem_dir):
            print(f"Separating stems via ElevenLabs → {stem_dir}", file=sys.stderr)
            separate_stems(a.mix, stem_dir)
    if os.path.isdir(stem_dir):
        for f in sorted(os.listdir(stem_dir)):
            name = os.path.splitext(f)[0]
            stems[name] = decode(os.path.join(stem_dir, f), sr=22050, mono=True)

    times, lufs, integrated = short_term_loudness(stereo)
    dips, jumps = loudness_events(times, lufs)
    report = {
        "file": os.path.basename(a.mix),
        "duration_s": round(dur, 2),
        "integrated_lufs": round(float(integrated), 1),
        "true_peak_dbtp": round(true_peak_db(stereo), 2),
        "clipped_samples": int(np.sum(np.abs(stereo) >= 0.9999)),
        "loudness_range_lu": round(float(np.percentile(lufs[lufs > -40], 95) - np.percentile(lufs[lufs > -40], 10)), 1),
        "loudness_dips": dips,
        "loudness_jumps": jumps,
        "silences": silence_runs(mono),
        "clicks": clicks(mono),
    }
    drums = stems.get("drums")
    if drums is None:
        import librosa
        drums = librosa.resample(mono, orig_sr=SR, target_sr=22050)
    tempo, beats, flams, breaks = beat_analysis(drums)
    report["tempo_bpm"] = round(tempo, 2)
    report["beat_grid_breaks"] = breaks
    report["off_grid_drum_windows"] = flams
    if "vocals" in stems:
        report["vocal_chops"] = vocal_chops(stems["vocals"], 22050, beats)
        voc = stem_db_curve(stems["vocals"], 22050, hop=0.1)
        report["vocal_coverage"] = round(float(np.mean(voc > -35)), 2)
    report["phrase_arc"] = phrase_arc(times, lufs, stems, 22050, tempo)

    if a.json:
        with open(a.json, "w") as f:
            json.dump(report, f, indent=1, default=float)

    print(f"\n== {report['file']}  ({dur/60:.1f} min, {tempo:.1f} BPM) ==")
    print(f"integrated {report['integrated_lufs']} LUFS · true peak {report['true_peak_dbtp']} dBTP · "
          f"clipped {report['clipped_samples']} · LRA≈{report['loudness_range_lu']} LU")
    print(f"loudness dips ≥4 LU: {len(dips)}   jumps ≥4 LU: {len(jumps)}   silences: {len(report['silences'])}   clicks: {len(report['clicks'])}")
    print(f"beat-grid breaks: {len(breaks)}   off-grid drum windows (trainwreck/flam): {len(flams)}")
    if "vocal_chops" in report:
        chops = report["vocal_chops"]
        print(f"hard vocal cuts: {len(chops)} ({sum(not c['on_beat'] for c in chops)} off-beat) · vocal coverage {report['vocal_coverage']:.0%}")
    for k in ("loudness_dips", "loudness_jumps", "beat_grid_breaks", "off_grid_drum_windows"):
        if report[k]:
            print(f"  {k}: {report[k][:12]}")


if __name__ == "__main__":
    main()
