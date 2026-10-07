import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/ai/ai_brain.dart';
import 'services/ai/local_model_service.dart';
import 'services/device/device_hub.dart';
import 'services/device/reminder_service.dart';
import 'services/intent_router.dart';
import 'services/speech/speech_service.dart';
import 'services/storage/chat_store.dart';
import 'services/storage/settings_store.dart';
import 'services/usage_reporter.dart';
import 'state/friday_controller.dart';

/// Everything the Friday UI needs, built once and shared by the full app and
/// the assistant overlay. Startup is fault-tolerant: if any service init
/// fails on a real device (keystore hiccup, notifications plugin, etc.) the
/// UI still opens instead of hanging on a blank screen.
class FridayServices {
  FridayServices({
    required this.settings,
    required this.speech,
    required this.controller,
  });

  final SettingsStore settings;
  final SpeechService speech;
  final FridayController controller;

  List<SingleChildWidget> get providers => [
        Provider<SettingsStore>.value(value: settings),
        Provider<SpeechService>.value(value: speech),
        ChangeNotifierProvider<FridayController>.value(value: controller),
      ];
}

Future<FridayServices> createFridayServices({bool loadHistory = true}) async {
  const secure = FlutterSecureStorage();
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsStore(secure, prefs);
  try {
    await settings.load();
  } catch (_) {}

  final reminders = ReminderService();
  try {
    await reminders.init();
  } catch (_) {}

  final speech = SpeechService(
    groqKeyProvider: () async => settings.groqKey,
  );
  final brain = AIBrain(settings: settings, local: LocalModelService());
  final controller = FridayController(
    brain: brain,
    router: IntentRouter(deviceHub: DeviceHub(), reminders: reminders),
    chatStore: ChatStore(prefs),
    speech: speech,
    settings: settings,
  );
  if (loadHistory) {
    try {
      await controller.loadHistory();
    } catch (_) {}
  }
  UsageReporter.report('app_start', {'os': Platform.operatingSystem});
  return FridayServices(settings: settings, speech: speech, controller: controller);
}
