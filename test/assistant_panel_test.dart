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

import 'package:friday/assistant_overlay.dart';

class LiveSpeech extends SpeechService {
  int starts = 0;
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
    starts++;
    active = true;
  }
}

void main() {
  testWidgets('assistant panel starts mic once and fits a bottom bar',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsStore(const FlutterSecureStorage(), prefs);
    final speech = LiveSpeech();
    final c = FridayController(
        brain: AIBrain(settings: settings, local: LocalModelService()),
        router:
            IntentRouter(deviceHub: DeviceHub(), reminders: ReminderService()),
        chatStore: ChatStore(prefs),
        speech: speech,
        settings: settings);
    await t.runAsync(() async {
      for (final item in {
        'Roboto': '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
        'MaterialIcons':
            '/home/sandbox/flutter/bin/cache/dart-sdk/bin/resources/devtools/assets/fonts/MaterialIcons-Regular.otf'
      }.entries) {
        final l = FontLoader(item.key)
          ..addFont(Future.value(
              ByteData.sublistView(await File(item.value).readAsBytes())));
        await l.load();
      }
    });
    await t.binding.setSurfaceSize(const Size(412, 230));
    final key = GlobalKey();
    await t.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<FridayController>.value(value: c),
      Provider<SpeechService>.value(value: speech)
    ], child: RepaintBoundary(key: key, child: const AssistantOverlayApp())));
    await t.pumpAndSettle();
    expect(speech.starts, 1);
    expect(find.text('Ask Friday...'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.runAsync(() async {
      final im = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final d = await im.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/friday-assistant-panel.png')
          .writeAsBytes(d!.buffer.asUint8List());
    });
  });
}
