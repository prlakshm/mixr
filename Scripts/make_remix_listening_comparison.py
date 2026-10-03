#!/usr/bin/env python3
"""Align two local handoff excerpts and match loudness using fixed gain only."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

import numpy as np
import pyloudnorm as pyln
from scipy.io import wavfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('candidate', type=Path)
parser.add_argument('baseline', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--candidate-drop', type=float, required=True)
parser.add_argument('--baseline-drop', type=float, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
reports = []
for name, source, drop in [('revised', args.candidate, args.candidate_drop),
                            ('preferred-B', args.baseline, args.baseline_drop)]:
    offset = drop - 12
    if offset < 0:
        raise ValueError('The comparison requires 12 seconds before each drop')
    raw = subprocess.check_output(['ffmpeg', '-v', 'error', '-ss', str(offset), '-t', '26',
        '-i', str(source), '-f', 'f32le', '-ac', '2', '-ar', '44100', 'pipe:1'])
    pcm = np.frombuffer(raw, dtype='<f4').reshape(-1, 2)
    if len(pcm) < 25.99 * 44100 or not np.isfinite(pcm).all():
        raise ValueError('Missing or incomplete comparison excerpt')
    meter = pyln.Meter(44100)
    gain = -18 - meter.integrated_loudness(pcm)
    matched = (pcm * 10 ** (gain / 20)).astype(np.float32)
    if np.max(np.abs(matched)) >= 1:
        raise ValueError('Fixed-gain excerpt would clip; cannot silently add limiting')
    target = args.output / (name + '.wav')
    wavfile.write(target, 44100, matched)
    reports.append({'label': name, 'source': str(source.resolve()),
        'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
        'excerpt': str(target.resolve()), 'excerpt_sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
        'source_offset_seconds': offset, 'drop_at_excerpt_seconds': 12,
        'gain_db': float(gain), 'measured_excerpt_lufs': float(meter.integrated_loudness(matched)),
        'normalization': 'single fixed gain to -18 integrated LUFS; no extra limiting',
        'review_status': 'not auditioned; labeled development comparison, not blinded release approval'})
(args.output / 'comparison-key.json').write_text(json.dumps(reports, indent=2) + '\n')
print('COMPARISON_READY')
