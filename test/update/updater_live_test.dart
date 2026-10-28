import 'package:flutter_test/flutter_test.dart';
import 'package:friday/update/app_update.dart';

/// LIVE test: hits the real public GitHub releases feed for
/// frances09f-lgtm/friday-fo. It proves the shipped update-check path
/// resolves the actually published release - the piece fixture tests
/// cannot cover. Needs real network (like the lookout repo's LIVE tests),
/// so this file deliberately does NOT initialize a TestWidgetsFlutterBinding:
/// that binding replaces every HttpClient with a 400-answering mock.
/// Dialog rendering with this data is covered by the fixture widget tests
/// in app_update_test.dart; Android-side delivery stays device-only.
void main() {
  // Any install older than the latest published release must see an update.
  test('LIVE: published latest release parses and beats a 1.0.162 install',
      () async {
    final checker = UpdateChecker(currentVersion: () async => '1.0.162');
    final result = await checker.check();
    expect(result.status, UpdateCheckStatus.available,
        reason:
            'live feed answered ${result.status} (error: ${result.error})');
    expect(result.info!.version, isNotEmpty);
    expect(result.info!.apkUrl, contains('Friday.apk'),
        reason: 'the published release must carry the Friday.apk asset');
    expect(result.info!.sizeBytes, greaterThan(1000000),
        reason: 'asset size must ride along for download verification');
  });
}
