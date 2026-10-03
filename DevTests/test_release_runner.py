import importlib.util,pathlib,unittest
import contextlib,io,subprocess,tempfile
from unittest.mock import patch
path=pathlib.Path(__file__).resolve().parents[1]/'Scripts/verify_auto_remix.py'
spec=importlib.util.spec_from_file_location('release',path); release=importlib.util.module_from_spec(spec); spec.loader.exec_module(release)
class ReleaseRunnerTests(unittest.TestCase):
 def test_crash_never_passes(self): self.assertEqual(release.evaluate(9,'PASS case\nALL PASSED',r'ALL PASSED',1),'fail')
 def test_empty_or_skipped_is_inconclusive(self):
  for text in ['', 'ALL PASSED', 'PASS one\nSKIP two\nALL PASSED', 'PASS one\nwhisper=inconclusive\nALL PASSED']:
   with self.subTest(text=text): self.assertEqual(release.evaluate(0,text,r'ALL PASSED',2),'inconclusive')
 def test_printed_failure_never_passes(self): self.assertEqual(release.evaluate(0,'FAIL case\nALL PASSED',r'ALL PASSED',0),'fail')
 def test_narrative_skip_does_not_mean_skipped_check(self):
  text='PASS N=4 places multiple guests or records skip/cameo\nskipped a second kick\nsome sections were skipped for lack of material.\nALL PASSED'
  self.assertEqual(release.evaluate(0,text,r'ALL PASSED',1),'pass')
 def test_explicit_incomplete_status_rejects_completed_footer(self):
  for status in ['SKIP missing case','  SKIPPED missing case','  INCONCLUSIVE missing annotation','whisper=inconclusive','status=skipped']:
   with self.subTest(status=status):
    self.assertEqual(release.evaluate(0,'PASS one\n'+status+'\nALL PASSED',r'ALL PASSED',1),'inconclusive')
 def test_completed_count_required(self):
  self.assertEqual(release.evaluate(0,'PASS a\nPASS b\nALL PASSED',r'ALL PASSED',2),'pass')
  self.assertEqual(release.evaluate(0,'PASS a\nPASS b',r'ALL PASSED',2),'inconclusive')
 def test_render_completion_requires_distinct_artifacts(self):
  requirement=[(r'^wrote (.+\.wav)$',2)]
  for output in ['DONE', 'wrote a.wav\nDONE', 'wrote a.wav\nwrote a.wav\nDONE']:
   with self.subTest(output=output):
    self.assertEqual(release.evaluate(0,output,r'^DONE$',0,requirement),'inconclusive')
  self.assertEqual(release.evaluate(0,'wrote a.wav\nwrote b.wav\nDONE',r'^DONE$',0,requirement),'pass')
 def test_failed_crate_does_not_analyze_stale_audio(self):
  calls=[]
  counts={'run_tempo_alignment_tests.sh':19,'run_join_manifest_tests.sh':44,
          'run_silence_exemption_tests.sh':6,'run_low_confidence_tests.sh':6,
          'run_limiter_audit_tests.sh':7,'run_rising_handoff_tests.sh':47,
          'run_pulse_ownership_tests.sh':5,'run_generalization_tests.sh':35,'run_input_domain_tests.sh':31}
  def run(command,**kwargs):
   calls.append(command)
   name=pathlib.Path(command[0]).name
   if name=='run_auto_remix_tests.sh': output='PASS assertion\n'*687+'HARNESS_SUMMARY completed=5 expected=5\n'
   elif name in counts: output='PASS assertion\n'*counts[name]+'ALL PASSED\n'
   elif name=='xcodebuild': output='** BUILD SUCCEEDED **'
   elif name=='run_tempo_render_tests.sh': output='TEMPO_RENDER_DONE cases=6'
   elif name=='run_phrase_render_tests.sh': output='PHRASE_RENDER_DONE cases=2'
   elif name=='run_aac_peak_tests.sh': output='ENCODED_PEAK_CONTROL_DONE'
   elif name=='run_crate_render_tests.sh': return subprocess.CompletedProcess(command,1,'FAIL crate')
   else:
    script=pathlib.Path(command[1]).name
    output={'check_tempo_render.py':'PASS tempo\n'*6,
            'check_phrase_render.py':'PASS phrase\n'*2,
            'check_aac_peak.py':'PASS codec\n'*3+'ALL PASSED'}.get(script,'PASS stale\n')
   return subprocess.CompletedProcess(command,0,output)
  with tempfile.TemporaryDirectory() as directory, patch.object(release.tempfile,'mkdtemp',return_value=directory), patch.object(release.subprocess,'run',side_effect=run), patch('sys.argv',['verify_auto_remix.py','all']), contextlib.redirect_stdout(io.StringIO()):
   self.assertEqual(release.main(),1)
  self.assertEqual(pathlib.Path(calls[-1][0]).name,'run_crate_render_tests.sh','dependent audio checks ran after the crate render failed')
  self.assertFalse(any('whisper' in str(c) or 'dump_gate' in str(c) for c in calls),'retired token/festival gates still govern the revised handoff')
if __name__=='__main__': unittest.main()
