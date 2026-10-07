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

import 'package:friday/ui/screens/assistant_setup_screen.dart';

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
  testWidgets('assistant setup reports state and requests one overlay grant',
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
    const channel = MethodChannel('friday/device');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'assistantState')
        return {'overlay': false, 'microphone': true, 'selected': false};
      return true;
    });
    await t.binding.setSurfaceSize(const Size(412, 850));
    await t.pumpWidget(MaterialApp(
        home: RepaintBoundary(key: key, child: const AssistantSetupScreen())));
    await t.pumpAndSettle();
    expect(find.text('Display over other apps: Not allowed'), findsOneWidget);
    expect(find.text('Microphone: Allowed'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await t.tap(find.text('Allow floating bar'));
    await t.pumpAndSettle();
    expect(calls, contains('assistantOverlayPermission'));
    expect(t.takeException(), isNull);
    await t.runAsync(() async {
      final im = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final d = await im.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/friday-assistant-setup.png')
          .writeAsBytes(d!.buffer.asUint8List());
    });
  });
}
