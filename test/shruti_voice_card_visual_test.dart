import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:friday/ui/widgets/shruti_voice_card.dart';

/// Renders the Shruti settings card states to real PNG pixels so layout and
/// readability can be inspected without a phone. CI uploads test_output/*.png
/// as the shruti-card-renders artifact. The Inter font is loaded from the
/// repo so text renders as real glyphs, not test-font boxes.
Future<void> _shot(WidgetTester tester, String name, Widget card) async {
  final key = GlobalKey();
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
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2.0);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  await File('test_output/$name.png')
      .writeAsBytes(data!.buffer.asUint8List());
}

void main() {
  setUpAll(() async {
    final bytes = File('assets/fonts/Inter.ttf').readAsBytesSync();
    final loader = FontLoader('Inter')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    await Directory('test_output').create(recursive: true);
  });

  testWidgets('renders Shruti card states to PNGs', (tester) async {
    await _shot(
        tester,
        'shruti_card_not_ready',
        ShrutiVoiceCard(
            enabled: false,
            onToggle: (_) {},
            modelReady: false,
            downloading: false,
            downloadedBytes: 0,
            onDownload: () {}));
    await _shot(
        tester,
        'shruti_card_downloading',
        ShrutiVoiceCard(
            enabled: true,
            onToggle: (_) {},
            modelReady: false,
            downloading: true,
            downloadedBytes: 15 * 1024 * 1024));
    await _shot(
        tester,
        'shruti_card_ready',
        ShrutiVoiceCard(
            enabled: true,
            onToggle: (_) {},
            modelReady: true,
            downloading: false,
            downloadedBytes: 0,
            onDelete: () {}));
    await _shot(
        tester,
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
