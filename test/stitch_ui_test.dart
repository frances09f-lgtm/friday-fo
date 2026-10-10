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
import 'package:friday/services/tasks/task_service.dart';
import 'package:friday/state/friday_controller.dart';
import 'package:friday/models/chat_message.dart';
import 'package:friday/services/link/device_link.dart';
import 'package:friday/app.dart';
import 'package:friday/ui/stitch_style.dart';
import 'package:friday/ui/screens/home_screen.dart';
import 'package:friday/ui/screens/immersive_voice_screen.dart';
import 'package:friday/ui/screens/background_tasks_screen.dart';
import 'package:friday/ui/screens/settings_screen.dart';

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

class FixtureTasks extends TaskService {
  @override
  Future<Map<String, dynamic>> state() async => {
        'mode': 'foreground',
        'runtime': 'Foreground checker waiting until next task is due',
        'tasks': [
          {
            'direction': 'below',
            'threshold': 4150,
            'status': 'active',
            'intervalMinutes': 5,
            'lastOutcome': 'Quote too old. Open Sona and let it update.'
          }
        ]
      };
}

void main() {
  testWidgets('Stitch five-screen fixture renders and narrow layout checks',
      (t) async {
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
        final f = File('assets/fonts/$name.ttf');
        final loader = FontLoader(name)
          ..addFont(Future.value(ByteData.sublistView(await f.readAsBytes())));
        await loader.load();
      }
      final f = File(
          '${Platform.environment['FLUTTER_ROOT'] ?? '/home/sandbox/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (await f.exists()) {
        final loader = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.sublistView(await f.readAsBytes())));
        await loader.load();
      }
    });
    final key = GlobalKey();
    Widget root(Widget page) => MultiProvider(providers: [
          ChangeNotifierProvider<FridayController>.value(value: controller),
          Provider<SpeechService>.value(value: speech),
          ChangeNotifierProvider<SettingsStore>.value(value: settings),
          ChangeNotifierProvider<LocalModelService>.value(value: local),
          ChangeNotifierProvider<DeviceLink>(create: (_) => DeviceLink())
        ], child: RepaintBoundary(key: key, child: page));
    Future<void> capture(String name) async {
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.runAsync(() async {
        final im = await (key.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final b = await im.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/friday-stitch-$name.png')
            .writeAsBytes(b!.buffer.asUint8List());
      });
    }

    await t.binding.setSurfaceSize(const Size(390, 1182));
    await t.pumpWidget(root(const FridayApp()));
    await capture('home-pass2');
    expect(find.textContaining('Gemini Nano'), findsNothing);
    expect(find.textContaining('NPU 18%'), findsNothing);
    expect(find.textContaining('Hotword active'), findsNothing);
    controller.messages.addAll([
      ChatMessage(
          id: 'fixture1',
          role: MessageRole.user,
          text: 'Can you read my screen?',
          at: DateTime(2026, 10, 10, 8, 40)),
      ChatMessage(
          id: 'fixture2',
          role: MessageRole.friday,
          text:
              'Screen read completed. Open Agent Mode to see the transient result.',
          at: DateTime(2026, 10, 10, 8, 40)),
      ChatMessage(
          id: 'fixture3',
          role: MessageRole.user,
          text: 'Remind me to stretch in thirty minutes.',
          at: DateTime(2026, 10, 10, 8, 41)),
      ChatMessage(
          id: 'fixture4',
          role: MessageRole.friday,
          text: 'Reminder registered for 10/10 9:11: stretch. ID 123.',
          at: DateTime(2026, 10, 10, 8, 41))
    ]);
    await t.binding.setSurfaceSize(const Size(390, 1198));
    await t.pumpWidget(root(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: Stitch.theme(),
        home: const HomeScreen())));
    await capture('conversation-pass2');
    await t.binding.setSurfaceSize(const Size(390, 998));
    controller.setPartialHeard(
        'Friday, read my screen and remind me to stretch in thirty minutes.');
    speech.active = true;
    await t.pumpWidget(root(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: Stitch.theme(),
        home: const ImmersiveVoiceScreen())));
    await capture('voice-pass2');
    speech.active = false;
    controller.setPartialHeard('');
    await t.binding.setSurfaceSize(const Size(390, 1250));
    await t.pumpWidget(root(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: Stitch.theme(),
        home: BackgroundTasksScreen(service: FixtureTasks()))));
    await capture('tasks-pass2');
    expect(find.textContaining('HTTP 200'), findsNothing);
    await t.binding.setSurfaceSize(const Size(390, 1850));
    await t.pumpWidget(root(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: Stitch.theme(),
        home: const SettingsScreen())));
    await capture('settings-pass2');
    expect(find.textContaining('Gemini Nano'), findsNothing);
    expect(find.textContaining('GGUF / ONNX'), findsNothing);
    expect(find.text('Microphone'), findsOneWidget);
    expect(find.text('Floating assistant'), findsOneWidget);
    expect(find.text('Cloud fallback keys'), findsOneWidget);
    await t.tap(find.text('Cloud fallback keys'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Gemini API key'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Groq API key'), findsOneWidget);
    expect(
        find.widgetWithText(TextField, 'OpenRouter API key'), findsOneWidget);
    await t.tap(find.text('Cloud fallback keys').first);
    await t.pumpAndSettle();
    await t.binding.setSurfaceSize(const Size(320, 640));
    for (final page in [
      const FridayApp(),
      MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: Stitch.theme(),
          home: const HomeScreen()),
      MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: Stitch.theme(),
          home: const ImmersiveVoiceScreen()),
      MaterialApp(
          theme: Stitch.theme(),
          home: BackgroundTasksScreen(service: FixtureTasks())),
      MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: Stitch.theme(),
          home: const SettingsScreen())
    ]) {
      await t.pumpWidget(root(page));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }
  });
}
