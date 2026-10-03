#!/usr/bin/env python3
"""Evaluate an explicitly selected steady-groove handoff against frozen LU limits.

For a development fixture whose intent is continuous musical energy. This is
not a universal classifier for intentional breakdowns, nor listening approval.
"""
import argparse
import json
import subprocess
from pathlib import Path

import numpy as np
import pyloudnorm as pyln
from measure_remix_exports import windows


def sustained(times, mask, minimum=0.2):
    runs, start = [], None
    for time, active in zip(times, mask):
        if active and start is None:
            start = float(time)
        if not active and start is not None:
            if time - start >= minimum - 1e-8:
                runs.append([start, float(time)])
            start = None
    if start is not None and times[-1] + 0.1 - start >= minimum - 1e-8:
        runs.append([start, float(times[-1] + 0.1)])
    return runs


def measure(path, cut, bpm):
    rate, bar = 44100, 240 / bpm
    offset, duration = max(0, cut - 4 * bar), 12 * bar
    raw = subprocess.check_output(['ffmpeg', '-v', 'error', '-ss', str(offset),
        '-i', str(path), '-t', str(duration), '-f', 'f32le', '-ac', '2', '-ar', str(rate), 'pipe:1'])
    pcm = np.frombuffer(raw, dtype='<f4').reshape(-1, 2).astype(np.float64)
    if len(pcm) < (cut-offset+6*bar)*rate or not np.isfinite(pcm).all():
        raise ValueError('Missing or invalid handoff/following-passage audio')
    meter = pyln.Meter(rate)
    for stage in meter._filters.values():
        for channel in range(2):
            pcm[:, channel] = stage.apply_filter(pcm[:, channel])
    times, energy = windows(pcm, 0.4, 0.1, rate)
    times += offset
    levels = -0.691 + 10*np.log10(np.maximum(energy, 1e-16))

    def median(start, end):
        chosen = levels[(times >= start) & (times+0.4 <= end)]
        if not len(chosen):
            raise ValueError('Missing reference window')
        return float(np.median(chosen))

    before = median(cut-4*bar, cut-2*bar)
    entrance = median(cut, cut+2*bar)
    following = median(cut+4*bar, cut+6*bar)
    scope = (times >= cut-2*bar) & (times+0.4 <= cut)
    local_times, local = times[scope], levels[scope]
    reference = min(before, entrance)
    dips = sustained(local_times, local < reference-3)
    result = {
        'file': str(path.resolve()), 'cut_seconds': cut,
        'intent': 'owner-selected steady musical handoff; vocals may rest, backing stays present',
        'measurement': 'ungated K-weighted 400ms windows, 100ms hop; stereo BS.1770 channel sum',
        'contract': 'acceptance-contract.json v1: 3LU trough for >=200ms; adjacent steady passages within2LU',
        'before_median_lufs': before, 'entrance_median_lufs': entrance,
        'following_median_lufs': following, 'following_change_lu': following-entrance,
        'worst_approach_deficit_lu': max(0, reference-float(min(local))),
        'unplanned_troughs': dips,
        'approach_pass': not dips, 'following_pass': abs(following-entrance) <= 2,
        'trajectory': [[float(t-cut), float(v)] for t, v in zip(times, levels)],
        'listening_approval': None,
    }
    result['pass'] = result['approach_pass'] and result['following_pass']
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('audio', type=Path)
    parser.add_argument('--cut', type=float, required=True)
    parser.add_argument('--bpm', type=float, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not np.isfinite([args.cut, args.bpm]).all() or args.bpm <= 0 or args.cut < 960/args.bpm:
        raise SystemExit('Invalid or insufficient reference timing')
    report = measure(args.audio, args.cut, args.bpm)
    args.output.write_text(json.dumps(report, indent=2)+'\n')
    print(f"{'PASS' if report['pass'] else 'FAIL'} handoff energy: approach deficit "
          f"{report['worst_approach_deficit_lu']:.2f} LU; following passage "
          f"{report['following_change_lu']:+.2f} LU; listening pending")
    raise SystemExit(0 if report['pass'] else 1)
