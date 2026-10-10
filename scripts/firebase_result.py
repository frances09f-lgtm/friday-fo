#!/usr/bin/env python3
import json, os, pathlib, re, sys, urllib.parse
if sys.argv[1] == '--safe-error':
    text = pathlib.Path(sys.argv[2]).read_text().lower()
    category = next((label for needle,label in [('permission','permission/access'),('unauth','authentication'),('quota','quota/rate limit'),('not found','app/project not found'),('invalid','invalid request'),('network','network')] if needle in text), 'unclassified failure')
    print('Firebase distribution stopped: '+category+'. Upload state may be uncertain; inspect Firebase before retry. Raw output was not retained.')
    sys.exit(0)
text = pathlib.Path(sys.argv[1]).read_text()
text = re.sub(r'\x1b\[[0-9;]*m', '', text)
result = {}
for key, label, host in [
    ('testing_uri', 'Share this release with testers who have access:', 'appdistribution.firebase.google.com'),
    ('firebase_console_uri', 'View this release in the Firebase console:', 'console.firebase.google.com')]:
    urls = re.findall(re.escape(label) + r'\s+(https://\S+)', text)
    if len(set(urls)) != 1:
        raise ValueError('Missing or ambiguous Firebase release URL')
    url = urls[0]
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != 'https' or parsed.hostname != host:
        raise ValueError('Unexpected Firebase URL')
    if parsed.query or parsed.fragment or parsed.username or parsed.password:
        raise ValueError('Unexpected Firebase URL parameters')
    result[key] = url
result.update(tag=os.environ['RELEASE_TAG'], sha256=os.environ['EXPECTED_SHA256'],
              app_id=os.environ['FIREBASE_APP_ID'], repository=os.environ['GITHUB_REPOSITORY'])
pathlib.Path(os.environ['RUNNER_TEMP'], 'firebase-result.json').write_text(json.dumps(result, indent=2))
