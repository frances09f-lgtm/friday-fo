import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/update/app_update.dart';

/// LIVE tests: hit the real public GitHub releases feed for
/// frances09f-lgtm/friday-fo and render the shipped update dialog with the
/// actually published release data. The widget-test binding installs a
/// 400-answering mock via HttpOverrides.global; setUp clears that override
/// so this file uses real networking (same reason lookout's LIVE tests run
/// without a widget binding). The screenshot lands in the repo root and CI
/// uploads it as the live-update-dialog-screenshot artifact.
/// What this proves: feed -> parse -> "update available" wiring and the
/// dialog rendering of current-release data. What it cannot prove:
/// Android/OEM delivery of the popup on a phone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    HttpOverrides.global = null;
  });

  UpdateChecker liveChecker() =>
      UpdateChecker(currentVersion: () async => '1.0.162');

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

  testWidgets('LIVE: update dialog renders the published release',
      (t) async {
    final checker = liveChecker();
    final result = await checker.check();
    expect(result.status, UpdateCheckStatus.available,
        reason:
            'live feed answered ${result.status} (error: ${result.error})');
    final info = result.info!;
    await t.binding.setSurfaceSize(const Size(420, 720));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      theme: ThemeData.light(),
      home: Scaffold(
        body: Center(
          child: UpdateDialog(
            info: info,
            checker: checker,
            current: '1.0.162',
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('Software Update'), findsOneWidget);
    expect(find.text('Installed: 1.0.162  ->  New: ${info.version}'),
        findsOneWidget);
    expect(find.text("What's new"), findsOneWidget);
    expect(find.text(info.version), findsWidgets);
    expect(t.takeException(), isNull);
    await t.binding.takeScreenshot('live-update-dialog');
  });
}
