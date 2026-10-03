#!/usr/bin/env python3
"""Measure decoded local exports. Missing source/limiter/listening evidence is not pass."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

import numpy as np
from scipy.signal import resample_poly
import pyloudnorm as pyln


def windows(signal, seconds, hop, rate):
    size, stride = round(seconds * rate), round(hop * rate)
    energy = np.sum(signal.astype(np.float64) ** 2, axis=1)
    prefix = np.concatenate(([0.0], np.cumsum(energy)))
    starts = np.arange(0, len(signal) - size + 1, stride)
    return starts / rate, (prefix[starts + size] - prefix[starts]) / size


def quiet_runs(times, levels, threshold=-60):
    spans, start = [], None
    for t, level in zip(times, levels):
        if level < threshold and start is None:
            start = float(t)
        elif level >= threshold and start is not None:
            if t - start >= 0.05 - 1e-8:
                spans.append([start, float(t)])
            start = None
    if start is not None and times[-1] + 0.01 - start >= 0.05 - 1e-8:
        spans.append([start, float(times[-1] + 0.01)])
    return spans


def measure(path):
    rate = 44100
    raw = subprocess.check_output(['ffmpeg', '-v', 'error', '-i', str(path),
                                   '-f', 'f32le', '-ac', '2', '-ar', str(rate), 'pipe:1'])
    pcm = np.frombuffer(raw, dtype='<f4').reshape(-1, 2)
    if not len(pcm) or not np.isfinite(pcm).all():
        raise ValueError('Missing or nonfinite decoded PCM')
    peak = float(np.max(np.abs(pcm)))
    true_peak = max(float(np.max(np.abs(resample_poly(pcm[:, c], 4, 1)))) for c in range(2))
    meter = pyln.Meter(rate)
    integrated = float(meter.integrated_loudness(pcm))
    weighted = pcm.astype(np.float64)
    for stage in meter._filters.values():
        for c in range(2):
            weighted[:, c] = stage.apply_filter(weighted[:, c])
    times, energy = windows(weighted, 0.4, 0.1, rate)
    loudness = -0.691 + 10 * np.log10(np.maximum(energy, 1e-16))
    short_times, short_energy = windows(weighted, 3, 0.1, rate)
    short_loudness = -0.691 + 10 * np.log10(np.maximum(short_energy, 1e-16))
    silence_times, silence_energy = windows(pcm, 0.02, 0.01, rate)
    rms = 10 * np.log10(np.maximum(silence_energy / 2, 1e-16))
    manifest_path = path.with_suffix('.join_manifest.json')
    manifest = json.loads(manifest_path.read_text())
    joins = []
    boundaries = [dict(join, evidence='declared join contract') for join in manifest['joinContracts']]
    primary = sorted((p for p in manifest['placements'] if p['role'] == 'dominant' and p['volume'] > 0),
                     key=lambda p: p['timelineStart'])
    for previous, incoming in zip(primary, primary[1:]):
        cut = incoming['timelineStart']
        previous_end = previous['timelineStart'] + previous['timelineDuration']
        expected_source = previous['sourceStart'] + (cut - previous['timelineStart']) * previous['tempoRatio']
        continuous = previous['songID'] == incoming['songID'] and abs(expected_source - incoming['sourceStart']) < 0.04
        if continuous or any(abs(join['cutAt'] - cut) < 0.04 for join in boundaries):
            continue
        boundaries.append({'cutAt': cut, 'windowStart': cut, 'kind': 'source_handoff',
                           'outgoingEnd': previous_end, 'evidence': 'derived from applied source mapping'})
    bar = 240 / manifest['targetBPM']
    for join in sorted(boundaries, key=lambda b: b['cutAt']):
        cut = join['cutAt']
        selection = (times >= max(0, cut - 4 * bar)) & (times + 0.4 <= cut + 4 * bar)
        if not selection.any():
            raise ValueError('Missing join PCM')
        local_times, local = times[selection], loudness[selection]
        lowest = int(np.argmin(local))
        before = loudness[(times >= max(0, join['windowStart'] - 2 * bar)) & (times + 0.4 <= join['windowStart'])]
        after_start = max(cut, join.get('outgoingEnd', cut))
        after = loudness[(times >= after_start) & (times + 0.4 <= after_start + 2 * bar)]
        references = None
        if len(before) and len(after):
            before_median, after_median = float(np.median(before)), float(np.median(after))
            references = {'before_median_lufs': before_median, 'after_median_lufs': after_median,
                          'steady_passage_change_lu': after_median - before_median,
                          'trough_below_quieter_reference_lu': max(0, min(before_median, after_median) - float(np.min(local))),
                          'overshoot_above_louder_reference_lu': max(0, float(np.max(local)) - max(before_median, after_median)),
                          'classification': 'diagnostic only; intended energy envelope and independent annotations are missing'}
        short_selection = (short_times >= max(0, cut - 4 * bar)) & (short_times + 3 <= cut + 4 * bar)
        joins.append({'kind': join['kind'], 'cut_seconds': cut,
                      'evidence': join['evidence'], 'window': 'join +/-4 bars; 400ms and 3s K-weighted windows, 100ms hop',
                      'minimum_400ms_loudness': float(local[lowest]),
                      'minimum_at_seconds': float(local_times[lowest]),
                      'maximum_400ms_loudness': float(np.max(local)),
                      'reference_diagnostic': references,
                      'loudness_400ms': [[float(t), float(v)] for t, v in zip(local_times, local)],
                      'loudness_3s': [[float(t), float(v)] for t, v in zip(short_times[short_selection], short_loudness[short_selection])],
                      'verdict': 'inconclusive: source and intended energy annotation required'})
    dbtp = 20 * np.log10(max(true_peak, 1e-16))
    audit_path = path.with_suffix('.master_audit.json')
    audit = json.loads(audit_path.read_text()) if audit_path.exists() else None
    limiter_pass = None if audit is None else bool(audit['sampleCount'] > 0
        and audit['maximumDB'] <= 6 and audit['longestHeavySeconds'] < 0.5
        and audit['heavyFraction'] <= 0.01)
    return {'file': path.name, 'audio_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'duration_seconds': len(pcm) / rate, 'integrated_lufs': integrated,
            'sample_peak_dbfs': float(20 * np.log10(max(peak, 1e-16))),
            'true_peak_4x_dbtp': float(dbtp), 'clipped_samples': int(np.sum(np.abs(pcm) >= 1)),
            'encoded_peak_pass': bool(dbtp <= -1 and peak < 1),
            'software_limiter_pass': limiter_pass,
            'software_limiter': None if audit is None else {k: v for k, v in audit.items() if k != 'maximum10msDB'},
            'sub60db_20ms_rms_runs': quiet_runs(silence_times, rms),
            'join_loudness': joins,
            'release_status': 'inconclusive',
            'missing_evidence': ['mapped source silence', 'pre-SFX headroom', 'upstream Audio Unit limiter trace',
                                 'live capture parity', 'human headphone and speaker audition']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder', type=Path)
    parser.add_argument('--require-encoded-peak', action='store_true',
                        help='Fail if any decoded export exceeds the frozen -1 dBTP limit')
    parser.add_argument('--require-software-limiter', action='store_true')
    args = parser.parse_args()
    paths = sorted(args.folder.glob('*.m4a'))
    if not paths:
        raise SystemExit('No exports: inconclusive')
    reports = [measure(path) for path in paths]
    (args.folder / 'decoded-metrics.json').write_text(json.dumps(reports, indent=2) + '\n')
    for r in reports:
        print(f"{r['file']}: {r['integrated_lufs']:.2f} LUFS, {r['true_peak_4x_dbtp']:.3f} dBTP, "
              f"{r['clipped_samples']} clipped samples; release inconclusive")
    if args.require_encoded_peak and not all(r['encoded_peak_pass'] for r in reports):
        raise SystemExit(1)
    if args.require_software_limiter and not all(r['software_limiter_pass'] is True for r in reports):
        raise SystemExit(1)

    print(f"MEASUREMENTS_DONE cases={len(reports)}")
