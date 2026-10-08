import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:friday/services/ai/offline_engine.dart';
import 'package:friday/services/ai/ai_brain.dart';
import 'package:friday/services/ai/local_model_service.dart';
import 'package:friday/services/storage/settings_store.dart';
import 'package:friday/services/tasks/gold_task.dart';
import 'package:friday/models/friday_response.dart';
import 'package:friday/ui/screens/commands_screen.dart';

void main() {
  test('device screenshot compound search keeps app and exact query separate',
      () {
    final r =
        const OfflineEngine().handle('open YouTube and search Spider-Man');
    expect(r.action.type, FridayActionType.searchApp);
    expect(r.action.app, 'youtube');
    expect(r.action.query, 'Spider-Man');
  });
  test('Chrome and Instagram route to search action not giant app name', () {
    for (final app in ['Chrome', 'Instagram']) {
      final r = const OfflineEngine().handle('Open $app and search for Rahul');
      expect(r.action.type, FridayActionType.searchApp);
      expect(r.action.query, 'Rahul');
    }
  });
  test('explicit gold direction creates a real task shape', () {
    for (final verb in ['ping', 'alert', 'notify', 'tell']) {
      final t =
          GoldTaskRequest.parse('$verb me when gold price goes below 4120');
      expect(t?.threshold, 4120);
      expect(t?.direction, 'below');
      expect(t?.intervalMinutes, 5);
    }
    expect(
        GoldTaskRequest.parse('alert me when gold price rises above 4200')
            ?.direction,
        'above');
  });
  test('reaches does not become a quote answer or fake saved alert', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsStore(
        const FlutterSecureStorage(), await SharedPreferences.getInstance());
    final b = AIBrain(settings: s, local: LocalModelService());
    for (final verb in ['ping', 'alert']) {
      final request = '$verb me when gold price reaches 4120';
      expect(GoldTaskRequest.parse(request), isNull);
      final r = await b.ask(request);
      expect(r.action.type, FridayActionType.none);
      expect(r.reply, contains('No alert was created'));
      expect(r.reply, contains('above'));
    }
  });
  testWidgets('commands page explains supported patterns and limits',
      (t) async {
    await t.runAsync(() async {
      final f = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
      await (FontLoader('Roboto')
            ..addFont(
                Future.value(ByteData.sublistView(await f.readAsBytes()))))
          .load();
    });
    await t.binding.setSurfaceSize(const Size(412, 1000));
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark(useMaterial3: true),
            home: const CommandsScreen())));
    await t.pumpAndSettle();
    expect(find.text('Apps and search'), findsOneWidget);
    await t.runAsync(() async {
      final im = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final b = await im.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/friday-commands.png')
          .writeAsBytes(b!.buffer.asUint8List());
    });
  });
}
