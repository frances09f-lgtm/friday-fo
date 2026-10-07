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
import 'package:friday/ui/screens/home_screen.dart';
import 'package:friday/models/chat_message.dart';

class SilentSpeech extends SpeechService {
  @override
  Future<bool> initSpeech() async => false;
}

void main() {
  testWidgets('opens at latest, follows bottom, preserves scrolled-up position',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsStore(const FlutterSecureStorage(), prefs);
    final speech = SilentSpeech();
    final c = FridayController(
        brain: AIBrain(settings: settings, local: LocalModelService()),
        router:
            IntentRouter(deviceHub: DeviceHub(), reminders: ReminderService()),
        chatStore: ChatStore(prefs),
        speech: speech,
        settings: settings);
    void append(String text) {
      c.messages.add(ChatMessage(
          id: text, role: MessageRole.friday, text: text, at: DateTime(2026)));
      c.notifyListeners();
    }

    for (var i = 0; i < 50; i++) {
      append('Message $i with some readable chat content.');
    }
    await t.runAsync(() async {
      final f = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
      final loader = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(await f.readAsBytes())));
      await loader.load();
    });
    await t.binding.setSurfaceSize(const Size(412, 850));
    final key = GlobalKey();
    await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<FridayController>.value(value: c),
          Provider<SpeechService>.value(value: speech),
          ChangeNotifierProvider<DeviceLink>(create: (_) => DeviceLink())
        ],
        child: MaterialApp(
            home: RepaintBoundary(key: key, child: const HomeScreen()))));
    await t.pumpAndSettle();
    final sc = t.widget<ListView>(find.byType(ListView)).controller!;
    expect(sc.position.extentAfter, lessThan(1));
    append('Latest arrived');
    await t.pumpAndSettle();
    expect(sc.position.extentAfter, lessThan(1));
    await t.runAsync(() async {
      final im = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final d = await im.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/friday-chat-bottom.png')
          .writeAsBytes(d!.buffer.asUint8List());
    });
    await t.drag(find.byType(ListView), const Offset(0, 500));
    await t.pumpAndSettle();
    final before = sc.offset;
    expect(sc.position.extentAfter, greaterThan(80));
    append('New while reading older');
    await t.pumpAndSettle();
    expect(sc.offset, closeTo(before, 1));
  });
}
