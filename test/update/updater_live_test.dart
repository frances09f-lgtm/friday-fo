import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/update/app_update.dart';

/// LIVE tests: these hit the real public GitHub releases feed for
/// frances09f-lgtm/friday-fo. They prove the shipped update-check path
/// resolves the actually published release and that the update dialog
/// renders with that real data - the piece fixture tests cannot cover.
/// They need network, like the lookout repo's LIVE tests.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Any install older than the latest published release must see an update.
  UpdateChecker liveChecker() => UpdateChecker(
        currentVersion: () async => '1.0.162',
      );

  test('LIVE: published latest release parses and beats a 1.0.162 install',
      () async {
    final result = await liveChecker().check();
    expect(result.status, UpdateCheckStatus.available,
        reason:
            'live feed answered ${result.status} (error: ${result.error})');
    expect(result.info!.version, isNotEmpty);
    expect(result.info!.apkUrl, contains('Friday.apk'),
        reason: 'the published release must carry the Friday.apk asset');
    expect(result.info!.sizeBytes, greaterThan(1000000),
        reason: 'asset size must ride along for download verification');
  });

  testWidgets('LIVE: update dialog renders the published release', (t) async {
    final checker = liveChecker();
    final result = await checker.check();
    expect(result.info, isNotNull);
    final info = result.info!;
    await t.pumpWidget(MaterialApp(
      theme: ThemeData.light(),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () =>
                showUpdateDialog(ctx, info, checker: checker, current: '1.0.162'),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('Software Update'), findsOneWidget);
    expect(find.textContaining(info.version), findsWidgets);
    expect(
        find.text('Installed: 1.0.162  ->  New: ${info.version}'), findsOneWidget);
    expect(find.text("What's new"), findsOneWidget);
    expect(t.takeException(), isNull);
    // Do not tap Update: that path needs the Android installer.
  });
}
