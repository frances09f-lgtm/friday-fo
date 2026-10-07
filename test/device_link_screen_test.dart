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

void main() {
  testWidgets('device link has visible enable button and pairing instructions',
      (t) async {
    await t.runAsync(() async {
      final bytes = await File('/usr/share/fonts/truetype/ubuntu/Ubuntu-R.ttf')
          .readAsBytes();
      final loader = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    });
    await t.binding.setSurfaceSize(const Size(412, 915));
    final link = DeviceLink();
    final key = GlobalKey();
    await t.pumpWidget(ChangeNotifierProvider.value(
        value: link,
        child: MaterialApp(
            home: RepaintBoundary(key: key, child: const DeviceLinkScreen()))));
    await t.pumpAndSettle();
    expect(find.text('Enable local link'), findsOneWidget);
    expect(find.textContaining('same Wi-Fi'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/link-screen.png')
          .writeAsBytes(data!.buffer.asUint8List());
    });
  });
}
