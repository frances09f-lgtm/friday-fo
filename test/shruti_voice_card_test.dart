import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:friday/ui/widgets/shruti_voice_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('not-ready state offers the model download', (tester) async {
    var toggled = false;
    await tester.pumpWidget(_wrap(ShrutiVoiceCard(
      enabled: false,
      onToggle: (_) => toggled = true,
      modelReady: false,
      downloading: false,
      downloadedBytes: 0,
      onDownload: () {},
    )));
    expect(find.text('Offline voice input (Shruti)'), findsOneWidget);
    expect(
        find.text('Understands English, Hindi and Marathi on the phone'),
        findsOneWidget);
    expect(find.text('Needs a one-time 29.5 MB model download'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
    await tester.tap(find.byType(Switch));
    expect(toggled, isTrue);
  });

  testWidgets('downloading state shows progress and no buttons',
      (tester) async {
    await tester.pumpWidget(_wrap(ShrutiVoiceCard(
      enabled: true,
      onToggle: (_) {},
      modelReady: false,
      downloading: true,
      downloadedBytes: 15 * 1024 * 1024,
    )));
    expect(find.text('Downloading model: 15.0 of 29.5 MB'), findsOneWidget);
    expect(find.text('Download'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('ready state offers delete and says offline',
      (tester) async {
    await tester.pumpWidget(_wrap(ShrutiVoiceCard(
      enabled: true,
      onToggle: (_) {},
      modelReady: true,
      downloading: false,
      downloadedBytes: 0,
      onDelete: () {},
    )));
    expect(
        find.text('Model on this phone (29.5 MB). Works offline.'),
        findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Download'), findsNothing);
  });

  testWidgets('error state shows the honest message and download again',
      (tester) async {
    await tester.pumpWidget(_wrap(ShrutiVoiceCard(
      enabled: false,
      onToggle: (_) {},
      modelReady: false,
      downloading: false,
      downloadedBytes: 0,
      error: 'Download failed. Check the connection and retry.',
      onDownload: () {},
    )));
    expect(find.text('Download failed. Check the connection and retry.'),
        findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
  });
}
