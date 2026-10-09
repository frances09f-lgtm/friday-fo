import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:friday/services/link/device_link.dart';
import 'package:friday/services/link/pairing_code.dart';
import 'package:friday/ui/screens/device_link_screen.dart';

class PreviewLink extends DeviceLink {
  PreviewLink() {
    addresses = ['http://192.168.1.7:54321'];
    pairingKey = base64UrlEncode(List.filled(32, 7)); // Fixture, not a live key.
    status = 'Ready to pair';
  }
  @override
  bool get running => true;
}

void main() {
  testWidgets('Windows displays Android-compatible QR for selected local address', (t) async {
    await t.runAsync(() async {
      final font = File('${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/arial.ttf');
      if (await font.exists()) {
        final bytes = await font.readAsBytes();
        await (FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
    });
    await t.binding.setSurfaceSize(const Size(1000, 1200));
    final link = PreviewLink();
    final key = GlobalKey();
    await t.pumpWidget(ChangeNotifierProvider<DeviceLink>.value(value: link,
      child: MaterialApp(home: RepaintBoundary(key: key, child: const DeviceLinkScreen()))));
    await t.pumpAndSettle();
    final qr = t.widget<QrImageView>(find.byType(QrImageView));
    final data = (qr.key as ValueKey<String>).value;
    final code = PairingCode.decode(data);
    expect(code.address, link.addresses.single);
    expect(code.key, link.pairingKey);
    expect(find.text('Refresh QR (valid 10 minutes)'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('windows-pairing-preview.png').writeAsBytes(png!.buffer.asUint8List());
    });
  });
}
