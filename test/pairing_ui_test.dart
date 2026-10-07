import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:friday/services/link/device_link.dart';
import 'package:friday/ui/screens/device_link_screen.dart';

class PreviewLink extends DeviceLink {
  @override
  bool get running => true;
  PreviewLink(List<String> ips) {
    addresses = ips;
    pairingKey = 'DEMO-KEY-NOT-A-REAL-PAIRING-KEY';
    status = 'Ready to pair';
  }
}

void main() {
  testWidgets('selection is required when multiple addresses exist', (t) async {
    await t.binding.setSurfaceSize(const Size(412, 1400));
    final link =
        PreviewLink(['http://192.168.1.4:12345', 'http://10.0.0.1:12345']);
    await t.pumpWidget(ChangeNotifierProvider<DeviceLink>.value(
        value: link, child: const MaterialApp(home: DeviceLinkScreen())));
    await t.pumpAndSettle();
    final pair =
        t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Pair'));
    expect(pair.onPressed, isNull);
    expect(find.text('Select My address on the shared network before pairing.'),
        findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('single address selected and format error visible', (t) async {
    await t.binding.setSurfaceSize(const Size(412, 1400));
    final link = PreviewLink(['http://192.168.1.4:12345']);
    final key = GlobalKey();
    await t.pumpWidget(ChangeNotifierProvider<DeviceLink>.value(
        value: link,
        child: MaterialApp(
            home: RepaintBoundary(key: key, child: const DeviceLinkScreen()))));
    await t.pumpAndSettle();
    expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Pair'))
            .onPressed,
        isNotNull);
    await t.enterText(find.byType(TextField).first, '192.168.1.5');
    await t.tap(find.widgetWithText(FilledButton, 'Pair'));
    await t.pumpAndSettle();
    expect(find.textContaining('Enter the other device address exactly'),
        findsOneWidget);
    expect(t.takeException(), isNull);
    await t.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/pairing-fix.png')
          .writeAsBytes(data!.buffer.asUint8List());
    });
  });
}
