#!/usr/bin/env python3
"""Run reproducible implementation checks without turning failures or missing evidence into success.

These checks are an implementation baseline, not the complete frozen release
contract. No automated invocation grants human listening approval.
"""
import argparse, json, os, re, subprocess, sys, tempfile
from pathlib import Path

def evaluate(returncode, output, completion_pattern, minimum_passes, evidence_requirements=()):
    if returncode or re.search(r'(?im)^\s*FAIL(?:ED)?(?:\b|:)',output): return 'fail'
    # Test labels and planner decisions may describe skipped musical material.
    # Only explicit check statuses count as incomplete verification evidence.
    if re.search(r'^\s*(?:SKIP(?:PED)?|INCONCLUSIVE)(?:\s|:|$)',output,re.M): return 'inconclusive'
    if re.search(r'(?i)\b[\w.-]+\s*=\s*(?:SKIP(?:PED)?|INCONCLUSIVE)\b',output): return 'inconclusive'
    if not re.search(completion_pattern,output,re.M): return 'inconclusive'
    if len(re.findall(r'^\s*PASS\s',output,re.M))<minimum_passes: return 'inconclusive'
    for pattern, minimum in evidence_requirements:
        if len(set(re.findall(pattern,output,re.M))) < minimum: return 'inconclusive'
    return 'pass'

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',nargs='?',choices=['fast','all'],default='all')
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]
    local=Path('/Users/pranavi/Documents/Mixr')
    default_python=local/'.venv/bin/python3'
    py=os.environ.get('MIXR_AUDIO_PYTHON', str(default_python) if default_python.exists() else sys.executable)
    logs=Path(tempfile.mkdtemp(prefix='mixr-verification-'))
    script=lambda name: str(root/'Scripts'/name)
    # All checks use repository-owned sources. Historical external gates forced
    # title tokens and festival stacks and no longer govern the revised join.
    stages=[
      ('swift',[script('run_auto_remix_tests.sh')],r'^HARNESS_SUMMARY completed=5 expected=5$',687),
      ('tempo-math',[script('run_tempo_alignment_tests.sh')],r'^ALL PASSED$',19),
      ('manifest-integrity',[script('run_join_manifest_tests.sh')],r'^ALL PASSED$',44),
      ('silence-controls',[script('run_silence_exemption_tests.sh')],r'^ALL PASSED$',6),
      ('source-continuity',[script('run_low_confidence_tests.sh')],r'^ALL PASSED$',6),
      ('generalization',[script('run_generalization_tests.sh')],r'^ALL PASSED$',35),
      ('input-domain',[script('run_input_domain_tests.sh')],r'^ALL PASSED$',31),
      ('rising-handoffs',[script('run_rising_handoff_tests.sh')],r'^ALL PASSED$',47),
      ('pulse-ownership',[script('run_pulse_ownership_tests.sh')],r'^ALL PASSED$',5),
      ('limiter-controls',[script('run_limiter_audit_tests.sh')],r'^ALL PASSED$',7),
    ]
    artifacts={}
    if args.mode=='all':
      tempo,phrase,codec,crate=[str(logs/name) for name in ['tempo','phrase','codec','crate']]
      stages += [
        ('build',['xcodebuild','-project',str(root/'Mixr.xcodeproj'),'-scheme','Mixr',
                  '-destination','generic/platform=iOS Simulator','-derivedDataPath',str(logs/'build'),
                  'CODE_SIGNING_ALLOWED=NO','build'],r'\*\* BUILD SUCCEEDED \*\*',0),
        ('tempo-render',[script('run_tempo_render_tests.sh'),tempo],r'TEMPO_RENDER_DONE',0),
        ('tempo-pcm',[py,script('check_tempo_render.py'),tempo],r'^PASS ',6),
        ('phrase-render',[script('run_phrase_render_tests.sh'),phrase],r'PHRASE_RENDER_DONE',0),
        ('phrase-pcm',[py,script('check_phrase_render.py'),phrase],r'^PASS ',2),
        ('codec-render',[script('run_aac_peak_tests.sh'),codec],r'ENCODED_PEAK_CONTROL_DONE',0),
        ('codec-pcm',[py,script('check_aac_peak.py'),codec],r'^ALL PASSED$',3),
        ('crate',[script('run_crate_render_tests.sh'),crate,'--all-subsets'],r'LISTEN_RENDERS_DONE cases=31 failures=0',0),
        ('delivery-pcm',[py,script('measure_remix_exports.py'),crate,'--require-encoded-peak','--require-software-limiter'],r'MEASUREMENTS_DONE cases=31',0),
        ('mapped-silence',[py,script('check_source_silence.py'),crate,'--stem-root',str(local/'Stems/htdemucs_ft')],r'SOURCE_SILENCE_DONE cases=31 unresolved=0',0),
      ]
      artifacts['crate']=[(r'^\s*wrote (\S+\.m4a)$',31),(r'^\s*wrote (\S+join_manifest\.json)$',31)]
    results=[]
    for name,command,completion,count in stages:
      print(f'Checking {name}...',flush=True)
      try:
        run=subprocess.run(command,cwd=root,env={**os.environ,'MIXR_ROOT':str(root),'MIXR_FAST':'all'},stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace',timeout=3600)
        output=run.stdout; rc=run.returncode
      except (OSError,subprocess.TimeoutExpired) as error:
        output=f'Unavailable or interrupted check: {type(error).__name__}'; rc=1
      (logs/f'{name}.log').write_text(output)
      status=evaluate(rc,output,completion,count,artifacts.get(name,()))
      results.append({'name':name,'status':status,'exit_code':rc,'log':str(logs/f'{name}.log')})
      print(f'{name}: {status}',flush=True)
      # Do not analyze stale exports when compilation or rendering failed.
      if status!='pass': break
    summary={'mode':args.mode,'checks':results,'release_status':'inconclusive','release_reason':'Frozen contract PCM/telemetry, source provenance, independent annotations and human listening approval are separate required evidence.'}
    (logs/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(f'Report: {logs}/summary.json')
    print('Release remains INCONCLUSIVE; automated checks cannot certify the revised audio contract.')
    # This is a verification entry point, so no zero exit while release is incomplete.
    return 1 if any(x['status']=='fail' for x in results) else 2
if __name__=='__main__': raise SystemExit(main())
