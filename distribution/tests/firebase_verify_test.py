import copy,importlib.util,json,pathlib,unittest
spec=importlib.util.spec_from_file_location('verify','scripts/firebase_verify.py');v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
class Verification(unittest.TestCase):
 def setUp(self):
  root=pathlib.Path('distribution');self.p=json.loads((root/'policy.json').read_text());self.m=json.loads(next((root/'audits').glob('*.json')).read_text());self.r={'id':self.m['release_id'],'tag_name':self.m['tag'],'draft':False,'prerelease':False,'assets':[{'id':self.m['asset_id'],'name':self.m['asset_name'],'size':self.m['asset_bytes']}]}
 def check(self):return v.verify_metadata(self.m,self.p,self.r,self.m['tag'],self.m['sha256'],self.m['repository'])
 def test_valid(self):self.check()
 def test_false_audit_gates(self):
  for key in ['signature_v2_verified','internet_permission','zip_crc_ok','common_secret_scan_clean','feature_markers_verified']:
   with self.subTest(key=key):
    old=self.m[key];self.m[key]=False
    with self.assertRaises(ValueError):self.check()
    self.m[key]=old
 def test_identity_changes(self):
  for key,value in [('release_id',0),('asset_id',0),('asset_bytes',0),('package_name','bad'),('signer_cert_sha256','bad'),('version_code',1),('commit','bad')]:
   with self.subTest(key=key):
    old=self.m[key];self.m[key]=value
    with self.assertRaises(ValueError):self.check()
    self.m[key]=old
 def test_draft_or_prerelease(self):
  for key in ['draft','prerelease']:
   self.r[key]=True
   with self.assertRaises(ValueError):self.check()
   self.r[key]=False
 def test_wrong_hash_or_tag(self):
  for tag,hash in [('../policy','a'*64),(self.m['tag'],'b'*64)]:
   with self.assertRaises(ValueError):v.verify_metadata(self.m,self.p,self.r,tag,hash,self.m['repository'])
 def test_asset_ambiguity(self):
  self.r['assets']*=2
  with self.assertRaises(ValueError):self.check()
 def test_connected_gate(self):
  if self.m['package_name']=='com.ambi.tiffe':
   self.m['entrypoint']='lib/main.dart'
   with self.assertRaises(ValueError):self.check()
if __name__=='__main__':unittest.main()
