import json,os,pathlib,subprocess,tempfile,unittest
class Parsing(unittest.TestCase):
 def test_parser_and_invalid_url(self):
  with tempfile.TemporaryDirectory() as d:
   env={**os.environ,'RUNNER_TEMP':d,'RELEASE_TAG':'v23','EXPECTED_SHA256':'a'*64,'FIREBASE_APP_ID':'app','GITHUB_REPOSITORY':'repo'}
   log=pathlib.Path(d)/'log';base='View this release in the Firebase console: https://console.firebase.google.com/project/p/appdistribution/app/a/releases/r\nShare this release with testers who have access: https://appdistribution.firebase.google.com/testerapps/a/releases/r\n'
   log.write_text(base+'SECRET DOWNLOAD URL SHOULD NEVER BE RETAINED')
   subprocess.run(['python3','scripts/firebase_result.py',str(log)],env=env,check=True)
   self.assertNotIn('SECRET', (pathlib.Path(d)/'firebase-result.json').read_text())
   for bad in [base.replace('appdistribution.firebase.google.com','evil.test'),base.replace('/testerapps/','?token=abc/testerapps/'),base+'Share this release with testers who have access: https://appdistribution.firebase.google.com/other\n']:
    log.write_text(bad);r=subprocess.run(['python3','scripts/firebase_result.py',str(log)],env=env,capture_output=True);self.assertNotEqual(r.returncode,0)
 def test_safe_error_never_echoes_secret(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)/'log';p.write_text('permission denied PRIVATE_KEY SECRET token https://signed.test')
   r=subprocess.run(['python3','scripts/firebase_result.py','--safe-error',str(p)],capture_output=True,text=True)
   self.assertIn('permission/access',r.stdout);self.assertNotIn('SECRET',r.stdout)
