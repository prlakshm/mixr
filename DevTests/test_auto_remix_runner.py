"""Exercise the real runner with a fake compiler; no Swift build or audio needed."""
import os, pathlib, shutil, subprocess, tempfile, unittest
RUNNER=pathlib.Path(__file__).resolve().parents[1]/'Scripts/run_auto_remix_tests.sh'
class RunnerTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory(); self.root=pathlib.Path(self.tmp.name)
  (self.root/'Scripts').mkdir(); shutil.copy2(RUNNER,self.root/'Scripts/run_auto_remix_tests.sh')
  (self.root/'DevTests').mkdir()
  for name in ['Pipeline','RenderQuality','Golden','ClubRemix','JoinEngine']:
   filename={'ClubRemix':'AutoClubRemixTests.swift','JoinEngine':'AutoJoinEngineTests.swift'}.get(name,'AutoRemix'+name+'Tests.swift')
   (self.root/'DevTests'/filename).write_text('// fixture')
  self.bin=self.root/'bin'; self.bin.mkdir()
  (self.bin/'xcrun').write_text('''#!/bin/bash
if [[ "$1" == "--sdk" ]]; then echo /tmp; exit 0; fi
if [[ "${MOCK_KIND}" == "compile-fail" ]]; then exit 9; fi
while [[ "$#" -gt 0 ]]; do if [[ "$1" == "-o" ]]; then shift; out="$1"; fi; shift; done
cat > "$out" <<'SCRIPT'
#!/bin/bash
case "$MOCK_KIND" in
  crash) exit 7;;
  empty) exit 0;;
  no-assertions) echo 'ALL PASSED';;
  hidden-fail) echo 'FAIL injected'; echo 'ALL PASSED';;
  indented-fail) echo 'PASS assertion'; echo '  FAILED injected'; echo 'ALL PASSED';;
  skipped) echo 'PASS assertion'; echo 'SKIP missing fixture'; echo 'ALL PASSED';;
  inconclusive) echo 'PASS assertion'; echo 'whisper=inconclusive'; echo 'ALL PASSED';;
  skipped-status) echo 'PASS assertion'; echo '  SKIPPED missing fixture'; echo 'ALL PASSED';;
  inconclusive-status) echo 'PASS assertion'; echo '  INCONCLUSIVE missing annotation'; echo 'ALL PASSED';;
  narrative) echo 'PASS N=4 places multiple guests or records skip/cameo'; echo 'skipped a second kick'; echo 'some sections were skipped for lack of material.'; echo 'ALL PASSED';;
  *) echo 'PASS assertion'; echo 'ALL PASSED';;
esac
SCRIPT
chmod +x "$out"
'''); (self.bin/'xcrun').chmod(0o755)
 def tearDown(self): self.tmp.cleanup()
 def run_case(self,selector='all',kind='good'):
  return subprocess.run(['/bin/bash',str(self.root/'Scripts/run_auto_remix_tests.sh'),selector],capture_output=True,text=True,env={**os.environ,'PATH':str(self.bin)+':'+os.environ['PATH'],'MOCK_KIND':kind})
 def test_unknown_selector_fails(self): self.assertNotEqual(self.run_case('typo').returncode,0)
 def test_every_harness_completes(self):
  result=self.run_case(); self.assertEqual(result.returncode,0,result.stdout+result.stderr); self.assertIn('HARNESS_SUMMARY completed=5 expected=5',result.stdout)
 def test_failure_and_missing_evidence_fail(self):
  for kind in ['compile-fail','crash','empty','no-assertions','hidden-fail','indented-fail','skipped','inconclusive','skipped-status','inconclusive-status']:
   with self.subTest(kind=kind): self.assertNotEqual(self.run_case(kind=kind).returncode,0)
 def test_narrative_skips_do_not_mean_skipped_checks(self):
  result=self.run_case(kind='narrative'); self.assertEqual(result.returncode,0,result.stdout+result.stderr)
 def test_preserves_existing_main(self):
  path=self.root/'main.swift'; path.write_text('existing user source'); result=self.run_case('club'); self.assertEqual(result.returncode,0); self.assertTrue(path.exists(),'runner deleted user source'); self.assertEqual(path.read_text(),'existing user source')
if __name__=='__main__': unittest.main()
