// ADC credential use stays in process; tokens and signed binary URIs never print.
const fs=require('fs');
const {GoogleAuth}=require('../distribution/tooling/node_modules/google-auth-library');
const assert=(v,m)=>{if(!v)throw Error(m)};
async function list(client,parent){
 let items=[],pageToken;
 do{
  const response=await client.request({url:`https://firebaseappdistribution.googleapis.com/v1/${parent}/releases`,params:{pageSize:100,...(pageToken?{pageToken}:{})},timeout:30000});
  items.push(...(response.data.releases||[]));pageToken=response.data.nextPageToken;
 }while(pageToken);
 return items;
}
function verifyPrevious(items,code){
 for(const item of items){assert(/^\d+$/.test(item.buildVersion),'Existing release version unreadable');assert(Number(item.buildVersion)<code,'Equal/newer Firebase build already exists. Do not retry without reconciliation.');}
}
function verifyAfter(items,m,parent,testingUri){
 const matching=items.filter(r=>r.buildVersion===String(m.version_code)&&r.displayVersion===m.version_name);
 assert(matching.length===1,'New Firebase release missing or ambiguous');
 const r=matching[0];assert(r.name.startsWith(parent+'/releases/'),'Wrong Firebase app');
 assert(r.testingUri===testingUri,'CLI URL does not match live release');
 assert((r.releaseNotes?.text||'').includes(`AUDIT-SHA256:${m.sha256}`),'Uploaded release audit marker missing');
 return {release_name:r.name,build_version:r.buildVersion,display_version:r.displayVersion,testing_uri:r.testingUri,firebase_console_uri:r.firebaseConsoleUri};
}
async function main(){
 const mode=process.argv[2],m=JSON.parse(fs.readFileSync(process.env.AUDIT_PATH));
 const p=JSON.parse(fs.readFileSync('distribution/policy.json'));
 const parent=`projects/${p.firebase_project_number}/apps/${p.firebase_app_id}`;
 assert(p.firebase_app_id===process.env.FIREBASE_APP_ID,'Wrong target app');
 const auth=new GoogleAuth({scopes:['https://www.googleapis.com/auth/cloud-platform']});
 const client=await auth.getClient();let items=await list(client,parent);
 if(mode==='before')verifyPrevious(items,m.version_code);
 else if(mode==='after'||mode==='reconcile'){
  const file=process.env.RUNNER_TEMP+'/firebase-result.json';
  const result=mode==='after'?JSON.parse(fs.readFileSync(file)):{tag:m.tag,sha256:m.sha256,app_id:p.firebase_app_id,repository:p.repository};
  if(mode==='reconcile'){const matching=items.filter(r=>r.buildVersion===String(m.version_code)&&r.displayVersion===m.version_name);assert(matching.length===1,'Release missing or ambiguous');result.testing_uri=matching[0].testingUri;}
  let verified;
  for(let attempt=0;attempt<6;attempt++){
    try{verified=verifyAfter(items,m,parent,result.testing_uri);break;}catch(error){if(attempt===5)throw error;await new Promise(resolve=>setTimeout(resolve,5000));items=await list(client,parent);}
  }
  Object.assign(result,verified);
  result.metadata_verified=true;fs.writeFileSync(file,JSON.stringify(result,null,2));
 }else throw Error('Unknown metadata check mode');
}
if(require.main===module)main().catch(()=>{console.error('Firebase metadata verification failed. No automatic retry. Check app access, existing versions and the release in Firebase console.');process.exit(1)});
module.exports={verifyPrevious,verifyAfter};
