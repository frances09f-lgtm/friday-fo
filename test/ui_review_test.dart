import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:friday/services/ai/ai_brain.dart';
import 'package:friday/services/ai/local_model_service.dart';
import 'package:friday/services/device/device_hub.dart';
import 'package:friday/services/device/reminder_service.dart';
import 'package:friday/services/intent_router.dart';
import 'package:friday/services/speech/speech_service.dart';
import 'package:friday/services/storage/chat_store.dart';
import 'package:friday/services/storage/settings_store.dart';
import 'package:friday/state/friday_controller.dart';
import 'package:friday/services/link/device_link.dart';
import 'package:friday/app.dart';

class FixtureSpeech extends SpeechService {
  bool active = false;
  @override
  Future<bool> initSpeech() async => true;
  @override
  bool get isListening => active;
  @override
  void startListening(
      {required void Function(String) onResult,
      required void Function() onDone,
      String localeId = 'en_IN'}) {
    active = true;
    onResult(
        'Friday, read my screen and remind me to stretch in thirty minutes.');
  }

  @override
  Future<void> stopListening() async {
    active = false;
  }
}

void main() {
  testWidgets('render actual Friday UI for review', (t) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsStore(const FlutterSecureStorage(), prefs);
    final speech = FixtureSpeech();
    final local = LocalModelService();
    final controller = FridayController(
        brain: AIBrain(settings: settings, local: local),
        router:
            IntentRouter(deviceHub: DeviceHub(), reminders: ReminderService()),
        chatStore: ChatStore(prefs),
        speech: speech,
        settings: settings);
    await t.runAsync(() async {
      for (final name in ['Inter', 'SpaceGrotesk', 'JetBrainsMono']) {
        final l = FontLoader(name)
          ..addFont(Future.value(ByteData.sublistView(
              await File('assets/fonts/$name.ttf').readAsBytes())));
        await l.load();
      }
      final l = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(await File(
                '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
            .readAsBytes())));
      await l.load();
    });
    final output = Directory(
        Platform.environment['REVIEW_OUTPUT'] ?? '/tmp/friday-ui-evidence')
      ..createSync(recursive: true);
    final key = GlobalKey();
    await t.binding.setSurfaceSize(const Size(412, 892));
    await t.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<FridayController>.value(value: controller),
      Provider<SpeechService>.value(value: speech),
      ChangeNotifierProvider<SettingsStore>.value(value: settings),
      ChangeNotifierProvider<LocalModelService>.value(value: local),
      ChangeNotifierProvider<DeviceLink>(create: (_) => DeviceLink())
    ], child: RepaintBoundary(key: key, child: const FridayApp())));
    Future<void> shot(String name) async {
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.runAsync(() async {
        final im = await (key.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
        final b = await im.toByteData(format: ui.ImageByteFormat.png);
        await File('${output.path}/$name.png')
            .writeAsBytes(b!.buffer.asUint8List());
        im.dispose();
      });
    }

    final prefix = Platform.environment['REVIEW_PREFIX'] ?? 'after';
    await shot('$prefix-home');
    if (find.text('More actions').evaluate().isNotEmpty) {
      await t.tap(find.text('More actions'));
      await shot('$prefix-actions');
      await t.tapAt(const Offset(15, 90));
      await t.pumpAndSettle();
    }
    await t.tap(find.byTooltip('Settings').first);
    await shot('$prefix-settings');
    await t.pageBack();
    await t.pumpAndSettle();
    await t.binding.setSurfaceSize(const Size(320, 640));
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('More actions'));
    await t.tap(find.text('More actions'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Agent Mode'));
    await t.pumpAndSettle();
    expect(find.text('Agent Mode'), findsOneWidget);
    expect(t.takeException(), isNull);
    t.platformDispatcher.clearTextScaleFactorTestValue();
    await t.pumpWidget(const SizedBox.shrink());
    await t.binding.setSurfaceSize(null);
  });
}
