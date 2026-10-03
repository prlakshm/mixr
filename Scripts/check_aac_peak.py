#!/usr/bin/env python3
"""Independently decode both AAC controls and enforce the frozen output ceiling."""
import argparse
import json
import subprocess
from pathlib import Path

import numpy as np
from scipy.signal import resample_poly


def true_peak(path):
    raw = subprocess.check_output(['ffmpeg', '-v', 'error', '-i', str(path),
                                   '-f', 'f32le', '-ac', '2', '-ar', '44100', 'pipe:1'])
    pcm = np.frombuffer(raw, dtype='<f4').reshape(-1, 2)
    if not len(pcm) or not np.isfinite(pcm).all():
        raise ValueError('Missing or invalid decoded control PCM')
    peak = max(np.max(np.abs(resample_poly(pcm[:, c], 4, 1))) for c in range(2))
    return float(20 * np.log10(max(peak, 1e-16)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder', type=Path)
    args = parser.parse_args()
    peaks = {name: true_peak(args.folder / (name + '.m4a')) for name in ['unguarded', 'guarded']}
    audit = json.loads((args.folder / 'audit.json').read_text())
    checks = {
        'previous encode fails the frozen ceiling': peaks['unguarded'] > -1,
        'guarded delivery passes independent 4x peak check': peaks['guarded'] <= -1,
        'codec correction is bounded attenuation': 1 < audit['attempts'] <= 3 and audit['gainDB'] < 0,
    }
    report = {'true_peaks': peaks, 'pass': all(checks.values()), 'checks': checks, 'audit': audit}
    (args.folder / 'independent-control.json').write_text(json.dumps(report, indent=2) + '\n')
    for name, ok in checks.items():
        print(('PASS ' if ok else 'FAIL ') + name)
    print('ALL PASSED' if report['pass'] else 'FAILED codec control')
    return 0 if report['pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
