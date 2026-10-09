import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/ai/ai_brain.dart';
import 'services/agent/friday_agent.dart';
import 'services/ai/local_model_service.dart';
import 'services/device/device_hub.dart';
import 'services/device/reminder_service.dart';
import 'services/intent_router.dart';
import 'services/link/device_link.dart';
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
    required this.link,
    required this.agent,
    required this.local,
  });

  final SettingsStore settings;
  final SpeechService speech;
  final FridayController controller;
  final DeviceLink link;
  final FridayAgent agent;
  final LocalModelService local;

  List<SingleChildWidget> get providers => [
        ChangeNotifierProvider<DeviceLink>.value(value: link),
        ChangeNotifierProvider<SettingsStore>.value(value: settings),
        Provider<SpeechService>.value(value: speech),
        ChangeNotifierProvider<LocalModelService>.value(value: local),
        ChangeNotifierProvider<FridayAgent>.value(value: agent),
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
  final local = LocalModelService();
  final brain = AIBrain(settings: settings, local: local);
  final agent =
      FridayAgent(brain: LocalBrain(local), device: NativeAgentDevice());
  final link = DeviceLink();
  final controller = FridayController(
    link: link,
    screenAgent: agent,
    agentRunning: () => agent.running || local.setupBusy,
    brain: brain,
    router: IntentRouter(deviceHub: DeviceHub(), reminders: reminders),
    chatStore: ChatStore(prefs,
        storageKey: loadHistory ? 'friday_chat_log' : 'friday_overlay_log'),
    speech: speech,
    settings: settings,
  );
  if (loadHistory) {
    try {
      await controller.loadHistory();
    } catch (_) {}
  }
  UsageReporter.report('app_start', {'os': Platform.operatingSystem});
  link.onCommand = controller.receiveRemote;
  return FridayServices(
      settings: settings,
      speech: speech,
      controller: controller,
      link: link,
      agent: agent,
      local: local);
}
