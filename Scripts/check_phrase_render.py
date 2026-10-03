#!/usr/bin/env python3
"""Narrow decoded coverage regression; not perceptual or full acceptance certification."""
import array, hashlib, json, math, shutil, subprocess, sys
from pathlib import Path
folder = Path(sys.argv[1])
cases = json.loads((folder / 'phrase-results.json').read_text())
reports = []
for case in cases:
    path = folder / f"phrase-{case['songs']}.m4a"
    raw = subprocess.check_output([shutil.which('ffmpeg') or 'ffmpeg', '-v', 'error', '-i', str(path), '-f', 'f32le', '-ac', '1', '-ar', '44100', 'pipe:1'])
    samples = array.array('f'); samples.frombytes(raw)
    cut = case['drop1_elapsed_bars'] * 240 / 128
    lo, hi = int((cut - 4) * 44100), int((cut + 4) * 44100)
    def meter(pcm):
        windows = [pcm[i:i+882] for i in range(lo, hi-882, 441)]
        if not windows or any(len(w) != 882 for w in windows):
            raise ValueError("Missing required decoded coverage")
        return [10 * math.log10(max(1e-16, sum(x*x for x in w) / len(w))) for w in windows]
    levels = meter(samples)
    max_run = run = 0
    for level in levels:
        run = run + 1 if level < -60 else 0
        max_run = max(max_run, run)
    # Known faulty negative control: a 100ms zero hole must fail the same gate.
    control_pcm = array.array('f', samples)
    gap_start = int(cut * 44100)
    control_pcm[gap_start:gap_start+4410] = array.array('f', [0]) * 4410
    control = meter(control_pcm)
    negative_run = negative_max = 0
    for level in control:
        negative_run = negative_run + 1 if level < -60 else 0
        negative_max = max(negative_max, negative_run)
    passed = max_run < 5 and negative_max >= 5 and case['early_phrase_pass']
    reports.append({**case, 'decoded_audio_sha256': hashlib.sha256(raw).hexdigest(), 'minimum_20ms_rms_dbfs': min(levels), 'maximum_sub60db_run_seconds': max_run*.01, 'negative_hole_rejected': negative_max>=5, 'coverage_pass': passed, 'scope': 'Drop1 +/-4seconds, decoded actual export; full loudness/limiter/live/audition gates remain unmeasured'})
    print(('PASS' if passed else 'FAIL') + f" {case['songs']}-song decoded coverage: minimum {min(levels):.2f} dBFS, below -60dBFS {max_run*.01:.3f}s")
(folder/'phrase-pcm-metrics.json').write_text(json.dumps(reports, indent=2)+'\n')
raise SystemExit(0 if len(reports)==2 and all(r['coverage_pass'] for r in reports) else 1)
