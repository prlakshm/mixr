#!/usr/bin/env python3
"""Measure rhythmic onset spacing in deterministic actual-engine exports."""
import hashlib,json,subprocess,sys
from pathlib import Path
import numpy as np
from scipy.signal import find_peaks
folder=Path(sys.argv[1]); cases=json.loads((folder/'renders.json').read_text()); reports=[]
for case in cases:
 raw=subprocess.check_output(['/Users/pranavi/bin/ffmpeg','-v','error','-i',case['path'],'-f','f32le','-ac','1','-ar','44100','pipe:1'])
 y=np.frombuffer(raw,dtype='<f4').astype(float)
 # 5ms RMS, 1ms hop; markers are 35ms sine-enveloped 1100Hz bursts.
 win=221; hop=44
 power=np.convolve(y*y,np.ones(win)/win,mode='valid')[::hop]
 envelope=np.sqrt(power)
 peaks,_=find_peaks(envelope,height=max(envelope)*.35,distance=int(.65*60/case['target']*44100/hop),prominence=max(envelope)*.25)
 times=(peaks*hop+win/2)/44100
 # Ignore the first/last markers, which touch clip/codec boundaries.
 times=times[1:65]
 expected=np.arange(len(times))*60/case['target']
 error=times-times[0]-expected if len(times) else np.array([float('inf')])
 drift=float(error[-1]); p95=float(np.quantile(np.abs(error),.95)); worst=float(max(np.abs(error)))
 # A single-interval median is biased by the 1ms hop quantization.
 # Estimate rate over the full annotated span; onset-error gates stay unchanged.
 bpm=60*(len(times)-1)/float(times[-1]-times[0]) if len(times)>1 else 0
 segment=y[44100:44100*11]
 spectrum=np.abs(np.fft.rfft(segment*np.hanning(len(segment))))
 freqs=np.fft.rfftfreq(len(segment),1/44100)
 band=(freqs>=150)&(freqs<=290)
 fundamental=float(freqs[band][np.argmax(spectrum[band])])
 pitch_error=float(1200*np.log2(fundamental/(220*2**(case.get("expected_pitch_semitones",0)/12))))
 ok=len(times)==64 and abs(drift)<=.020 and p95<=.020 and worst<=.040 and abs(bpm/case['target']-1)<=.001 and abs(pitch_error)<=10
 expected_ok=not case['negative_control']
 report={**case,'audio_sha256':hashlib.sha256(Path(case['path']).read_bytes()).hexdigest(),'markers':len(times),'measured_bpm':bpm,'drift_seconds':drift,'p95_error_seconds':p95,'maximum_error_seconds':worst,'pitch_error_cents':pitch_error,'signal_gate_pass':ok,'test_pass':ok==expected_ok,'method':'5ms RMS/1ms hop; 64 interior marker centers; first marker removes constant latency only; no per-beat correction'}
 reports.append(report)
 print(f"{'PASS' if report['test_pass'] else 'FAIL'} {case['name']}: {len(times)} markers, target={case['target']:.4f}, measured={bpm:.4f}, drift={drift*1000:.1f}ms, p95={p95*1000:.1f}ms, pitch={pitch_error:.1f}c, negative={case['negative_control']}")
(folder/'tempo-metrics.json').write_text(json.dumps(reports,indent=2)+'\n')
raise SystemExit(0 if {c['name'] for c in cases}=={'pair-vocal','pair-bed','native-control','negative-drift','pitch-up','slowdown'} and all(r['test_pass'] for r in reports) else 1)
