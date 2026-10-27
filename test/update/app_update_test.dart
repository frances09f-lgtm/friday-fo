import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:friday/update/app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The version compare shipped in v1.0.161 (6a69640), copied verbatim so
/// this test proves a 1.0.161 install sees each new release as newer.
int compareVersions161(String a, String b) {
  List<int> parts(String v) {
    final core = v.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
    final segs = core
        .split('.')
        .map((s) => int.tryParse(s.split('-').first) ?? 0)
        .toList();
    return segs.length == 1 ? [1, 0, segs.first] : segs;
  }

  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < pa.length || i < pb.length; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x - y;
  }
  return 0;
}

const _release = '{"tag_name":"v1.0.162","body":"notes here","assets":['
    '{"name":"other.apk","browser_download_url":"https://github.com/x/other.apk","url":"https://api.github.com/a/1","size":3},'
    '{"name":"Friday.apk","browser_download_url":"https://github.com/x/Friday.apk","url":"https://api.github.com/a/2","size":5}]}';

UpdateChecker _checker(Future<http.Response> Function(http.Request) fn,
        {String current = '1.0.161', Directory? dir}) =>
    UpdateChecker(
      client: MockClient(fn),
      currentVersion: () async => current,
      cacheDir: () async => dir ?? Directory.systemTemp,
    );

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
    expect(compareVersions('1.0.162', '1.0.161'), greaterThan(0));
    expect(compareVersions('1.0.162', '1.0.162-debug1'), 0);
  });
  test('a v1.0.161 install sees v1.0.162 as newer', () {
    expect(compareVersions161('1.0.162', '1.0.161'), greaterThan(0));
    expect(compareVersions161('v1.0.162'.replaceFirst('v', ''), '1.0.161'),
        greaterThan(0));
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
  test('check prefers Friday.apk and carries the API asset URL and size',
      () async {
    final r = await _checker((_) async => http.Response(_release, 200)).check();
    expect(r.status, UpdateCheckStatus.available);
    expect(r.current, '1.0.161');
    expect(r.latest, '1.0.162');
    expect(r.info!.apkUrl, 'https://github.com/x/Friday.apk');
    expect(r.info!.apiAssetUrl, 'https://api.github.com/a/2');
    expect(r.info!.sizeBytes, 5);
  });
  test('check says up to date and why a check failed', () async {
    final same = await _checker((_) async => http.Response(_release, 200),
            current: '1.0.162')
        .check();
    expect(same.status, UpdateCheckStatus.upToDate);
    final http500 =
        await _checker((_) async => http.Response('x', 500)).check();
    expect(http500.status, UpdateCheckStatus.failed);
    expect(http500.error, contains('HTTP 500'));
    final limited =
        await _checker((_) async => http.Response('x', 403)).check();
    expect(limited.error, contains('rate-limiting'));
    final dns = await _checker((_) async => throw http.ClientException(
            'Failed host lookup: api.github.com'))
        .check();
    expect(dns.error, contains('DNS'));
    expect(dns.error, contains('api.github.com'));
    final noApk = await _checker((_) async =>
            http.Response('{"tag_name":"v1.0.162","assets":[]}', 200))
        .check();
    expect(noApk.error, contains('no APK'));
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
  test('autoCheck returns the newer release on launch', () async {
    SharedPreferences.setMockInitialValues({});
    final info =
        await _checker((_) async => http.Response(_release, 200)).autoCheck();
    expect(info!.version, '1.0.162');
  });

  group('download', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('upd'));
    tearDown(() async => dir.delete(recursive: true));
    const info = UpdateInfo(
        version: '1.0.162',
        notes: '',
        apkUrl: 'https://github.com/x/Friday.apk',
        apiAssetUrl: 'https://api.github.com/a/2',
        sizeBytes: 5);

    test('falls back to the API asset URL when the download link fails',
        () async {
      final seen = <String>[];
      final c = _checker((req) async {
        seen.add('${req.url.host} ${req.headers['Accept'] ?? ''}');
        if (req.url.host == 'github.com') {
          throw http.ClientException(
              'Failed host lookup: objects.githubusercontent.com');
        }
        return http.Response.bytes(utf8.encode('APK!!'), 200);
      }, dir: dir);
      final progress = <int>[];
      final f = await c.download(info, onProgress: (r, _) => progress.add(r));
      expect(await f.readAsString(), 'APK!!');
      expect(seen, ['github.com ', 'api.github.com application/octet-stream']);
      expect(progress.last, 5);
    });

    test('names the reason for every failed link', () async {
      final c = _checker((req) async {
        if (req.url.host == 'github.com') {
          throw http.ClientException('Failed host lookup: github.com');
        }
        return http.Response('nope', 404);
      }, dir: dir);
      try {
        await c.download(info);
        fail('should throw');
      } on UpdateException catch (e) {
        expect(e.message, contains("Couldn't download the update"));
        expect(e.message, contains('github.com: '));
        expect(e.message, contains('DNS'));
        expect(
            describeNetworkError(
                http.ClientException(
                    "Failed host lookup: 'release-assets.githubusercontent.com'"),
                host: 'github.com'),
            contains('release-assets.githubusercontent.com'));
        expect(e.message, contains('api.github.com: HTTP 404'));
      }
    });

    test('rejects an incomplete download', () async {
      final c = _checker(
          (req) async => http.Response.bytes(utf8.encode('AP'), 200),
          dir: dir);
      await expectLater(
          c.download(info),
          throwsA(isA<UpdateException>().having(
              (e) => e.message, 'message', contains('incomplete'))));
    });
  });

  group('dialog', () {
    UpdateChecker fake(
            {required List<String> log, required bool Function() can}) =>
        UpdateChecker(
          client: MockClient((_) async => http.Response(_release, 200)),
          currentVersion: () async => '1.0.161',
          canInstall: () async => can(),
          openInstallSettings: () async => log.add('settings'),
          installer: (p) async => log.add('install $p'),
          downloader: (i, {onProgress, cancelToken}) async {
            log.add('download ${i.version}');
            onProgress?.call(5, 5);
            return File('/tmp/Friday-${i.version}.apk');
          },
        );
    const info = UpdateInfo(
        version: '1.0.162', notes: 'Tasks clear when done.', apkUrl: 'u');

    Future<void> open(WidgetTester t, UpdateChecker c, ThemeData theme) async {
      await t.pumpWidget(MaterialApp(
          theme: theme,
          home: Builder(
              builder: (ctx) => Scaffold(
                  body: TextButton(
                      onPressed: () => showUpdateDialog(ctx, info,
                          checker: c, current: '1.0.161'),
                      child: const Text('go'))))));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
    }

    testWidgets('shows versions and notes and follows the light theme',
        (t) async {
      final log = <String>[];
      await open(t, fake(log: log, can: () => true), ThemeData.light());
      expect(find.text('Friday 1.0.162 is available'), findsOneWidget);
      expect(find.text('Installed: 1.0.161  ->  New: 1.0.162'), findsOneWidget);
      expect(find.text('Tasks clear when done.'), findsOneWidget);
      final dialog = t.widget<AlertDialog>(find.byType(AlertDialog));
      expect(dialog.backgroundColor, isNull,
          reason: 'no hard-coded dark background in a light theme');
      await t.tap(find.text('Update'));
      await t.pumpAndSettle();
      expect(log, ['download 1.0.162', 'install /tmp/Friday-1.0.162.apk']);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('asks for the install permission, then continues by itself',
        (t) async {
      final log = <String>[];
      var allowed = false;
      await open(t, fake(log: log, can: () => allowed), ThemeData.dark());
      await t.tap(find.text('Update'));
      await t.pumpAndSettle();
      expect(find.text('One permission needed'), findsOneWidget);
      await t.tap(find.text('Open settings'));
      await t.pumpAndSettle();
      expect(log, ['settings']);
      expect(find.text('Continue'), findsOneWidget);
      allowed = true;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(log, [
        'settings',
        'download 1.0.162',
        'install /tmp/Friday-1.0.162.apk'
      ]);
    });

    testWidgets('a failed download shows the reason and a Retry', (t) async {
      final c = UpdateChecker(
        currentVersion: () async => '1.0.161',
        canInstall: () async => true,
        downloader: (i, {onProgress, cancelToken}) async =>
            throw const UpdateException(
                "Couldn't download the update.\ngithub.com: HTTP 403"),
      );
      await open(t, c, ThemeData.light());
      await t.tap(find.text('Update'));
      await t.pumpAndSettle();
      expect(find.text('Update failed'), findsOneWidget);
      expect(find.textContaining('github.com: HTTP 403'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('settings card', () {
    testWidgets('shows the installed version and what a check found',
        (t) async {
      var body = '{"tag_name":"v1.0.161","assets":[{"name":"Friday.apk","browser_download_url":"https://x/F.apk"}]}';
      var status = 200;
      final c = UpdateChecker(
        client: MockClient((_) async => http.Response(body, status)),
        currentVersion: () async => '1.0.161',
      );
      await t.pumpWidget(MaterialApp(
          home: Scaffold(body: UpdateSettingsCard(checker: c))));
      await t.pumpAndSettle();
      expect(find.text('Installed: Friday 1.0.161'), findsOneWidget);
      expect(find.text('Check for updates'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('check-for-updates')));
      await t.pumpAndSettle();
      expect(find.text("You're on the latest version."), findsOneWidget);
      status = 500;
      await t.tap(find.byKey(const ValueKey('check-for-updates')));
      await t.pumpAndSettle();
      expect(find.textContaining("Couldn't check: GitHub answered HTTP 500"),
          findsOneWidget);
      status = 200;
      body = _release;
      await t.tap(find.byKey(const ValueKey('check-for-updates')));
      await t.pumpAndSettle();
      expect(find.text('Friday 1.0.162 is available'), findsOneWidget);
      expect(find.text('Install Friday 1.0.162'), findsOneWidget);
    });
  });
}
