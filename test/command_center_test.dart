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

import 'package:friday/app.dart';
import 'package:friday/models/chat_message.dart';
import 'package:friday/services/link/device_link.dart';

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
  testWidgets('command center home chat activity preserve real results',
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
            '${Platform.environment['FLUTTER_ROOT'] ?? '/home/sandbox/flutter'}/bin/cache/dart-sdk/bin/resources/devtools/assets/fonts/MaterialIcons-Regular.otf'
      }.entries) {
        if (!await File(item.value).exists()) continue;
        final l = FontLoader(item.key)
          ..addFont(Future.value(
              ByteData.sublistView(await File(item.value).readAsBytes())));
        await l.load();
      }
    });
    await t.binding.setSurfaceSize(const Size(412, 915));
    final key = GlobalKey();
    c.messages.add(ChatMessage(
        id: 'old-session',
        role: MessageRole.friday,
        text: 'Previous session private text',
        at: DateTime(2026, 10, 8)));
    await t.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<FridayController>.value(value: c),
      Provider<SpeechService>.value(value: speech),
      ChangeNotifierProvider<SettingsStore>.value(value: settings),
      ChangeNotifierProvider<LocalModelService>(
          create: (_) => LocalModelService()),
      ChangeNotifierProvider<DeviceLink>(create: (_) => DeviceLink()),
    ], child: RepaintBoundary(key: key, child: const FridayApp())));
    await t.pumpAndSettle();
    expect(speech.starts, 0);
    expect(find.byTooltip('Notifications'), findsNothing);
    expect(find.byTooltip('Pair devices'), findsNothing);
    expect(find.byTooltip('Assistant setup'), findsNothing);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.text('What do you want me to do?'), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
    expect(find.text('Previous session private text'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.runAsync(() async {
      final im = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final d = await im.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/friday-command-center.png')
          .writeAsBytes(d!.buffer.asUint8List());
    });
    await t.tap(find.byTooltip('Settings'));
    await t.pumpAndSettle();
    expect(find.text('Assistant setup'), findsOneWidget);
    expect(find.text('Connected devices'), findsOneWidget);
    expect(find.text('Notifications'), findsNothing);
    await t.runAsync(() async {
      final im = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final d = await im.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/friday-v42-settings.png')
          .writeAsBytes(d!.buffer.asUint8List());
    });
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.text('Activity'));
    await t.pumpAndSettle();
    expect(find.text('Previous session private text'), findsOneWidget);
    c.messages.addAll([
      ChatMessage(
          id: 'preview-user',
          role: MessageRole.user,
          text: 'remind me to drink water in 2 minutes',
          at: DateTime(2026, 10, 8, 1, 50)),
      ChatMessage(
          id: 'preview-result',
          role: MessageRole.friday,
          text: 'Reminder registered for 9/10 10:44: drink water. ID 123.',
          at: DateTime(2026, 10, 8, 1, 50))
    ]);
    c.notifyListeners();
    await t.pumpAndSettle();
    await t.runAsync(() async {
      final im = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final d = await im.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/friday-activity-preview.png')
          .writeAsBytes(d!.buffer.asUint8List());
    });
    await t.tap(find.text('Home'));
    await t.pumpAndSettle();
    await t.runAsync(() async {
      final im = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final d = await im.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/friday-session-home.png')
          .writeAsBytes(d!.buffer.asUint8List());
    });
    await t.tap(find.text('Chat'));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsWidgets);
    expect(find.text('Done'), findsNothing);
    expect(find.textContaining('Reminder registered for'), findsOneWidget);
    expect(c.messages.last.text, contains('ID 123'));
    expect(FridayController.conciseReply('I could not schedule the reminder.'),
        'I could not schedule the reminder.');
    await t.runAsync(() async {
      final im = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final d = await im.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/friday-chat-preview.png')
          .writeAsBytes(d!.buffer.asUint8List());
    });
  });
}
