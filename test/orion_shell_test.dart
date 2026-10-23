import 'package:flutter/material.dart';
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
import 'package:friday/orion_app.dart';
import 'package:friday/ui/screens/background_tasks_screen.dart';

class OrionSpeech extends SpeechService {
  @override
  Future<bool> initSpeech() async => true;
}

Finder dock(String label) => find.descendant(
    of: find.byType(NavigationBar), matching: find.text(label));

void main() {
  Future<Widget> app() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsStore(const FlutterSecureStorage(), prefs);
    final speech = OrionSpeech();
    final local = LocalModelService();
    final controller = FridayController(
        brain: AIBrain(settings: settings, local: local),
        router:
            IntentRouter(deviceHub: DeviceHub(), reminders: ReminderService()),
        chatStore: ChatStore(prefs),
        speech: speech,
        settings: settings);
    return MultiProvider(providers: [
      ChangeNotifierProvider<FridayController>.value(value: controller),
      Provider<SpeechService>.value(value: speech),
      ChangeNotifierProvider<SettingsStore>.value(value: settings),
      ChangeNotifierProvider<LocalModelService>.value(value: local),
      ChangeNotifierProvider<DeviceLink>(create: (_) => DeviceLink()),
    ], child: const OrionApp());
  }

  testWidgets('dock has five tabs and Settings is a plain gear', (t) async {
    await t.binding.setSurfaceSize(const Size(412, 892));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(await app());
    await t.pumpAndSettle();
    for (final label in ['Chat', 'Agent', 'Tasks', 'Alerts', 'Devices']) {
      expect(dock(label), findsOneWidget);
    }
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.byIcon(Icons.account_circle_outlined), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tabs are built on first open and the dock fits 320 px',
      (t) async {
    await t.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final errs = <String>[];
    var phase = 'start';
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      final s = d.toString();
      errs.add('[$phase] ${s.length > 1800 ? s.substring(0, 1800) : s}');
    };
    try {
      await t.pumpWidget(await app());
      phase = 'chat';
      await t.pumpAndSettle();
      expect(find.byType(BackgroundTasksScreen), findsNothing);
      phase = 'tasks';
      await t.tap(dock('Tasks'));
      await t.pumpAndSettle();
      expect(find.byType(BackgroundTasksScreen), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    } finally {
      FlutterError.onError = prev;
    }
    expect(errs, isEmpty, reason: errs.join('\n-----\n'));
  });

  testWidgets('theme toggle switches between light and dark', (t) async {
    t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    await t.binding.setSurfaceSize(const Size(412, 892));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(await app());
    await t.pumpAndSettle();
    expect(Theme.of(t.element(find.byType(NavigationBar))).brightness,
        Brightness.light);
    await t.tap(find.byTooltip('Dark theme'));
    await t.pumpAndSettle();
    expect(Theme.of(t.element(find.byType(NavigationBar))).brightness,
        Brightness.dark);
    expect(find.byTooltip('Light theme'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
