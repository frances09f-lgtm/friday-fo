#!/usr/bin/env bash
set -euo pipefail
umask 077
credential="$RUNNER_TEMP/firebase-app-distribution.json"
log="$RUNNER_TEMP/firebase-distribution-output.log"
trap 'rm -f "$credential" "$log"' EXIT
printf '%s' "$FIREBASE_SERVICE_ACCOUNT_JSON" > "$credential"
unset FIREBASE_SERVICE_ACCOUNT_JSON
export GOOGLE_APPLICATION_CREDENTIALS="$credential"
python3 - <<'PY'
import json,os
with open(os.environ['GOOGLE_APPLICATION_CREDENTIALS']) as f:data=json.load(f)
assert data['type']=='service_account','Invalid credential type'
assert data['project_id']==os.environ['FIREBASE_PROJECT_ID'],'Wrong project'
assert data['client_email']=='github-app-distribution@app-testing-2cdba.iam.gserviceaccount.com','Wrong upload account'
PY
printf '%s\n' 'Checking previous Firebase version (read only)'
node scripts/firebase_state.cjs before
if ! distribution/tooling/node_modules/.bin/firebase appdistribution:distribute "$APK_PATH" --non-interactive \
 --app "$FIREBASE_APP_ID" --testers frances09f@gmail.com --release-notes-file "$RELEASE_NOTES_PATH" > "$log" 2>&1; then
 python3 scripts/firebase_result.py --safe-error "$log" >&2
 exit 1
fi
python3 scripts/firebase_result.py "$log"
printf '%s\n' 'Upload accepted, checking resulting Firebase metadata (read only)'
node scripts/firebase_state.cjs after
