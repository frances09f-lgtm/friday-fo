import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:friday/update/app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('compareVersions', () {
    expect(compareVersions('1.0.20', '1.0.19'), greaterThan(0));
    expect(compareVersions('v1.0.20', '1.0.20'), 0);
    // Short release tags ("v80") mean 1.0.80.
    expect(compareVersions('80', '1.0.80'), 0);
    expect(compareVersions('v81', '1.0.80'), greaterThan(0));
    expect(compareVersions('v80', '1.0.161'), lessThan(0));
    expect(compareVersions('1.0.161', '1.0.160'), greaterThan(0));
    expect(compareVersions('1.0.161', '1.0.80'), greaterThan(0));
  });
  test('fetchLatest parses latest release and compares', () async {
    const body = '{"tag_name":"v1.0.20","body":"notes here",'
        '"assets":[{"name":"Friday.apk","browser_download_url":"https://x/F.apk"}]}';
    final c = UpdateChecker(
      client: MockClient((_) async => http.Response(body, 200)),
      currentVersion: () async => '1.0.19',
    );
    final info = await c.fetchLatest();
    expect(info!.version, '1.0.20');
    expect(info.apkUrl, endsWith('F.apk'));
    final same = UpdateChecker(
      client: MockClient((_) async => http.Response(body, 200)),
      currentVersion: () async => '1.0.20',
    );
    expect(await same.fetchLatest(), isNull);
  });
  test('autoCheck stamps failures and respects the interval', () async {
    SharedPreferences.setMockInitialValues({});
    var calls = 0;
    final c = UpdateChecker(
      client: MockClient((_) async {
        calls++;
        return http.Response('x', 500);
      }),
      currentVersion: () async => '1.0.19',
    );
    expect(await c.autoCheck(), isNull);
    expect(await c.autoCheck(), isNull);
    expect(calls, 1);
  });
}
