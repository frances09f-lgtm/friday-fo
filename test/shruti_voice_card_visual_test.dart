import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:friday/ui/widgets/shruti_voice_card.dart';

/// Renders the Shruti settings card states to real PNG pixels so layout and
/// readability can be inspected without a phone. CI uploads test_output/*.png
/// as the shruti-card-renders artifact. All font loading and pixel capture
/// run inside tester.runAsync, matching the repo's proven render-test
/// pattern: engine-channel awaits in the fake-async zone hang for the full
/// 10-minute test timeout.
void main() {
  testWidgets('renders Shruti card states to PNGs', (tester) async {
    await tester.runAsync(() async {
      final bytes =
          await File('assets/fonts/Inter.ttf').readAsBytes();
      final loader = FontLoader('Inter')
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      await Directory('test_output').create(recursive: true);
    });

    final key = GlobalKey();
    Future<void> shot(String name, Widget card) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'Inter', brightness: Brightness.dark),
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: SizedBox(
                width: 380, child: RepaintBoundary(key: key, child: card)),
          ),
        ),
      ));
      // Explicit pumps, never pumpAndSettle: a stuck animation must fail
      // fast, not hang the whole CI job.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2.0);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('test_output/$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
      });
    }

    await shot(
        'shruti_card_not_ready',
        ShrutiVoiceCard(
            enabled: false,
            onToggle: (_) {},
            modelReady: false,
            downloading: false,
            downloadedBytes: 0,
            onDownload: () {}));
    await shot(
        'shruti_card_downloading',
        ShrutiVoiceCard(
            enabled: true,
            onToggle: (_) {},
            modelReady: false,
            downloading: true,
            downloadedBytes: 15 * 1024 * 1024));
    await shot(
        'shruti_card_ready',
        ShrutiVoiceCard(
            enabled: true,
            onToggle: (_) {},
            modelReady: true,
            downloading: false,
            downloadedBytes: 0,
            onDelete: () {}));
    await shot(
        'shruti_card_error',
        ShrutiVoiceCard(
            enabled: false,
            onToggle: (_) {},
            modelReady: false,
            downloading: false,
            downloadedBytes: 0,
            error: 'Download failed. Check the connection and retry.',
            onDownload: () {}));
    expect(File('test_output/shruti_card_ready.png').existsSync(), isTrue);
  });
}
