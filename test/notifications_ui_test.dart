import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/ui/screens/notifications_screen.dart';

void main() {
  testWidgets('notification diagnostics and test actions fit a phone',
      (t) async {
    const channel = MethodChannel('friday/device');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel,
            (c) async => {
                  'enabled': true,
                  'exactAlarms': false,
                  'batteryUnrestricted': false,
                  'channels': [
                    {'name': 'Friday reminders', 'enabled': true},
                    {'name': 'Gold task alerts', 'enabled': false}
                  ]
                });
    await t.runAsync(() async {
      final f = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
      if (await f.exists()) {
        final l = FontLoader('Roboto')
          ..addFont(Future.value(ByteData.sublistView(await f.readAsBytes())));
        await l.load();
      }
    });
    await t.binding.setSurfaceSize(const Size(412, 915));
    final key = GlobalKey();
    await t.pumpWidget(MaterialApp(
        home: RepaintBoundary(key: key, child: const NotificationsScreen())));
    await t.pumpAndSettle();
    expect(find.text('Test notification now'), findsOneWidget);
    expect(find.text('Test reminder in 1 minute'), findsOneWidget);
    expect(find.text('Gold task alerts: Disabled'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.runAsync(() async {
      final im = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final data = await im.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/notification-health.png')
          .writeAsBytes(data!.buffer.asUint8List());
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
