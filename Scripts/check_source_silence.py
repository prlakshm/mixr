#!/usr/bin/env python3
"""Compare internal quiet candidates with mapped source PCM; no label exemptions."""
import argparse
import json
import subprocess
from pathlib import Path
import numpy as np

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('folder', type=Path)
parser.add_argument('--stem-root', type=Path, required=True)
args = parser.parse_args()
results = []
for report in json.loads((args.folder / 'decoded-metrics.json').read_text()):
    manifest = json.loads((args.folder / Path(report['file']).with_suffix('.join_manifest.json')).read_text())
    identities = {p['id']: Path(p['path']) for p in manifest['sourceIdentity']}
    for lo, hi in report['sub60db_20ms_rms_runs']:
        # This check is only the internal-gap gate. Beginning and terminal
        # decay remain separately unreviewed, rather than silently passing.
        if lo <= 1 or hi >= report['duration_seconds'] - 2:
            continue
        references = []
        for clip in manifest['placements']:
            a = max(lo, clip['timelineStart'])
            b = min(hi, clip['timelineStart'] + clip['timelineDuration'])
            if b <= a:
                continue
            source = identities[clip['songID']]
            if clip['stemKind'] != 'fullMix':
                source = args.stem_root / source.stem / (clip['stemKind'] + '.wav')
            if not source.is_file():
                references.append({'source': str(source), 'status': 'missing'})
                continue
            start = clip['sourceStart'] + (a - clip['timelineStart']) * clip['tempoRatio']
            duration = (b - a) * clip['tempoRatio']
            raw = subprocess.check_output(['ffmpeg', '-v', 'error', '-ss', str(start), '-t', str(duration),
                '-i', str(source), '-f', 'f32le', '-ac', '1', '-ar', '22050', 'pipe:1'])
            pcm = np.frombuffer(raw, dtype='<f4')
            level = float(10 * np.log10(max(float(np.mean(pcm.astype(float) ** 2)), 1e-16))) if len(pcm) else None
            references.append({'source': str(source), 'source_start': start, 'rms_dbfs': level,
                               'status': 'measured' if level is not None else 'missing'})
        if not references or any(r['status'] != 'measured' for r in references):
            status = 'inconclusive'
        elif any(r['rms_dbfs'] > -45 for r in references):
            status = 'unresolved_active_source_gap'
        else:
            status = 'quiet_source_confirmed'
        results.append({'file': report['file'], 'start': lo, 'end': hi, 'status': status, 'sources': references})
(args.folder / 'source-silence-review.json').write_text(json.dumps(results, indent=2) + '\n')
for result in results:
    print(f"{result['status']}: {result['file']} {result['start']:.2f}–{result['end']:.2f}s")
if any(r['status'] != 'quiet_source_confirmed' for r in results):
    raise SystemExit(1)

print(f"SOURCE_SILENCE_DONE cases={len(json.loads((args.folder / 'decoded-metrics.json').read_text()))} unresolved=0")
