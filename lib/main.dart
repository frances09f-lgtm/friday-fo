import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'services/ai/ai_brain.dart';
import 'services/ai/local_model_service.dart';
import 'services/device/device_hub.dart';
import 'services/device/reminder_service.dart';
import 'services/intent_router.dart';
import 'services/speech/speech_service.dart';
import 'services/storage/chat_store.dart';
import 'services/storage/settings_store.dart';
import 'state/friday_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const secure = FlutterSecureStorage();
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsStore(secure, prefs);
  await settings.load();

  final reminders = ReminderService();
  await reminders.init();

  final speech = SpeechService();
  final brain = AIBrain(settings: settings, local: LocalModelService());
  final controller = FridayController(
    brain: brain,
    router: IntentRouter(deviceHub: DeviceHub(), reminders: reminders),
    chatStore: ChatStore(prefs),
    speech: speech,
    settings: settings,
  );
  await controller.loadHistory();

  runApp(
    MultiProvider(
      providers: [
        Provider<SettingsStore>.value(value: settings),
        Provider<SpeechService>.value(value: speech),
        ChangeNotifierProvider<FridayController>.value(value: controller),
      ],
      child: const FridayApp(),
    ),
  );
}
