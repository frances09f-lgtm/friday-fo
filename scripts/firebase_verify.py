#!/usr/bin/env python3
"""Validate an approved release against trusted default-branch records. No build."""
import hashlib, json, os, pathlib, re, subprocess, sys

def require(test, message):
    if not test:
        raise ValueError(message)

def cmd(*args):
    return subprocess.check_output(args, text=True)

def verify_metadata(manifest, policy, release, tag, expected, repository):
    require(re.fullmatch(r'v[0-9]+', tag) is not None, 'Unexpected release tag')
    require(re.fullmatch(r'[0-9a-f]{64}', expected) is not None, 'Invalid expected SHA256')
    require(manifest['schema_version'] == 1, 'Unsupported manifest')
    require(manifest['repository'] == repository == policy['repository'], 'Repository mismatch')
    require(manifest['tag'] == tag == release['tag_name'], 'Release tag mismatch')
    require(not release['draft'] and not release['prerelease'], 'Not a final published release')
    require(manifest['release_id'] == release['id'], 'Release ID mismatch')
    require(manifest['sha256'] == expected, 'Approval hash differs from audit')
    require(manifest['package_name'] == policy['package_name'], 'Wrong package')
    require(manifest['signer_cert_sha256'] == policy['signer_sha256'], 'Wrong persistent signer')
    require(isinstance(manifest['version_code'], int) and manifest['version_code'] > 0, 'Invalid version')
    require(manifest['version_code'] >= policy['minimum_version_code'], 'Version below approved floor')
    require(manifest['asset_name'] == policy['asset_name'], 'Wrong release asset')
    require(manifest['version_name'] == '1.0.' + str(manifest['version_code']) and tag == 'v' + str(manifest['version_code']), 'Tag/version disagree')
    require(re.fullmatch(r'[0-9a-f]{40}', manifest['commit']) is not None, 'Invalid source commit')
    require(manifest.get('ci_run_id'), 'Missing audit provenance')
    for gate in ['signature_v2_verified', 'internet_permission', 'zip_crc_ok', 'common_secret_scan_clean', 'feature_markers_verified']:
        require(manifest.get(gate) is True, 'Audit gate failed: ' + gate)
    if policy['package_name'] == 'com.ambi.tiffe':
        require(manifest.get('entrypoint') == 'lib/connected_main.dart', 'Tiffe is not connected')
        require(manifest.get('backend_mode') == 'connected' and manifest.get('backend_config_verified') is True,
                'Missing verified real-backend provenance')
    assets = [a for a in release['assets'] if a['name'] == policy['asset_name']]
    require(len(assets) == 1, 'Missing or ambiguous APK asset')
    require(assets[0]['id'] == manifest['asset_id'], 'APK asset replaced after audit')
    require(assets[0]['size'] == manifest['asset_bytes'], 'APK size differs from audit')
    return assets[0]

def main():
    tag = os.environ['RELEASE_TAG']
    require(re.fullmatch(r'v[0-9]+', tag) is not None, 'Invalid tag before file access')
    expected = os.environ['EXPECTED_SHA256'].lower()
    repository = os.environ['GITHUB_REPOSITORY']
    require(os.environ['GITHUB_REF'] == 'refs/heads/main', 'Dispatch must run trusted main')
    root = pathlib.Path('distribution')
    policy = json.loads((root / 'policy.json').read_text())
    manifest = json.loads((root / 'audits' / (tag + '.json')).read_text())
    require(policy['firebase_project_id'] == os.environ['FIREBASE_PROJECT_ID'], 'Firebase project mismatch')
    require(policy['firebase_app_id'] == os.environ['FIREBASE_APP_ID'], 'Firebase app mismatch')
    release = json.loads(cmd('gh', 'api', f'repos/{repository}/releases/tags/{tag}'))
    asset = verify_metadata(manifest, policy, release, tag, expected, repository)
    source = json.loads(cmd('gh', 'api', f'repos/{repository}/commits/{tag}'))
    require(source['sha'] == manifest['commit'], 'Tag moved after audit')
    ci = json.loads(cmd('gh','api',f'repos/{repository}/actions/runs/{manifest["ci_run_id"]}'))
    require(ci['conclusion']=='success' and ci['head_sha']==manifest['commit'], 'CI provenance mismatch')
    directory = pathlib.Path(os.environ['RUNNER_TEMP']) / 'firebase-release'
    directory.mkdir(exist_ok=True)
    apk = directory / policy['asset_name']
    with apk.open('wb') as out:
        subprocess.run(['gh', 'api', '-H', 'Accept: application/octet-stream',
                        f'repos/{repository}/releases/assets/{asset["id"]}'], stdout=out, check=True)
    with apk.open('rb') as binary:
        require(hashlib.file_digest(binary, 'sha256').hexdigest() == expected, 'APK hash mismatch')
    require(apk.stat().st_size == manifest['asset_bytes'], 'Downloaded APK size mismatch')
    tools = pathlib.Path(os.environ['AUDIT_ANDROID_TOOLS']) if os.environ.get('AUDIT_ANDROID_TOOLS') else pathlib.Path(os.environ['ANDROID_HOME']) / 'build-tools' / '35.0.0'
    badging = cmd(str(tools / 'aapt'), 'dump', 'badging', str(apk))
    match = re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging)
    require(match is not None, 'APK metadata unreadable')
    require(match.groups() == (manifest['package_name'], str(manifest['version_code']), manifest['version_name']),
            'APK package or version mismatch')
    require(re.search(r"sdkVersion:'([0-9]+)'", badging).group(1) == str(manifest['min_sdk']), 'minSdk mismatch')
    require(re.search(r"targetSdkVersion:'([0-9]+)'", badging).group(1) == str(manifest['target_sdk']), 'targetSdk mismatch')
    require("uses-permission: name='android.permission.INTERNET'" in badging, 'Missing Internet permission')
    signature = cmd(str(tools / 'apksigner'), 'verify', '--verbose', '--print-certs', str(apk))
    signers = re.findall(r'Signer #[0-9]+ certificate SHA-256 digest: ([0-9a-fA-F]+)', signature)
    require([x.lower() for x in signers] == [policy['signer_sha256']], 'Invalid or unexpected APK signer')
    require('Verified using v2 scheme (APK Signature Scheme v2): true' in signature, 'v2 not verified')
    import zipfile
    with zipfile.ZipFile(apk) as z:
        require(z.testzip() is None, 'Bad ZIP CRC')
        binary=z.read('lib/arm64-v8a/libapp.so')
        for marker in policy.get('required_binary_markers', []):
            require(marker.encode() in binary, 'Missing feature marker')
    notes = directory / 'release-notes.txt'
    notes.write_text((release.get('body') or f'{tag}\n') + '\nAUDIT-SHA256:' + expected, encoding='utf-8')
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        output.write(f'audit={root / "audits" / (tag + ".json")}\napk={apk}\nnotes={notes}\nversion_code={manifest["version_code"]}\nversion_name={manifest["version_name"]}\n')

if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(f'Release validation stopped: {error}', file=sys.stderr)
        sys.exit(1)
