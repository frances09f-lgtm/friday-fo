import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:friday/services/ai/ai_brain.dart';
import 'package:friday/services/ai/local_model_service.dart';
import 'package:friday/services/storage/settings_store.dart';
import 'package:friday/services/storage/chat_store.dart';
import 'package:friday/services/speech/speech_service.dart';
import 'package:friday/state/friday_controller.dart';
import 'package:friday/services/ai/offline_engine.dart';
import 'package:friday/services/intent_router.dart';
import 'package:friday/services/device/device_hub.dart';
import 'package:friday/services/device/reminder_service.dart';
import 'package:friday/models/friday_response.dart';

class Recorder extends ReminderService {
  int calls = 0;
  Duration? delay;
  String? title;
  bool succeeds = true;
  @override
  Future<bool> schedule(
      {required String title,
      required String body,
      required Duration after}) async {
    calls++;
    delay = after;
    this.title = title;
    return succeeds;
  }
}

class NoSpeech extends SpeechService {
  @override
  Future<void> speak(String t, {String locale = 'en-IN'}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'real controller brain router chain registers one reminder and single result',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsStore(const FlutterSecureStorage(), prefs)
      ..speakReplies = false;
    final recorder = Recorder();
    final c = FridayController(
        brain: AIBrain(settings: settings, local: LocalModelService()),
        router: IntentRouter(deviceHub: DeviceHub(), reminders: recorder),
        chatStore: ChatStore(prefs),
        speech: NoSpeech(),
        settings: settings);
    await c.send('remind me to drink water in 2 minutes');
    expect(recorder.calls, 1);
    expect(recorder.delay, const Duration(minutes: 2));
    expect(c.messages.length, 2);
    expect(c.messages.last.text, contains('Reminder registered'));
    expect(c.busy, false);
  });
  test('relative exact chat request awaits schedule two minutes', () async {
    final r =
        const OfflineEngine().handle('remind me to drink water in 2 minutes');
    final recorder = Recorder();
    final out = await IntentRouter(deviceHub: DeviceHub(), reminders: recorder)
        .executeAll(r.allActions);
    expect(recorder.calls, 1);
    expect(recorder.delay, const Duration(minutes: 2));
    expect(recorder.title, 'drink water');
    expect(out, contains('Reminder registered'));
  });
  for (final text in [
    'remind me to drink water at 1.03',
    'remind to drink water at 1:03'
  ]) {
    test('exact $text parses actual minute', () {
      final r =
          const OfflineEngine().handle(text, now: DateTime(2026, 10, 8, 1, 0));
      expect(r.action.type, FridayActionType.setReminder);
      expect(r.action.afterMinutes, 3);
    });
  }
  test('scheduling failure never confirms Done', () async {
    final recorder = Recorder()..succeeds = false;
    final r =
        const OfflineEngine().handle('remind to drink water in 2 minutes');
    final out = await IntentRouter(deviceHub: DeviceHub(), reminders: recorder)
        .executeAll(r.allActions);
    expect(out, contains('could not schedule'));
  });
  test('absolute time retains exact seconds boundary', () {
    final r = const OfflineEngine().handle('remind me to drink water at 1.02',
        now: DateTime(2026, 10, 8, 1, 0, 45));
    expect(r.action.target, '2026-10-08T01:02:00.000');
  });
  test('invalid minute never normalizes to another hour', () {
    final r = const OfflineEngine()
        .handle('remind to drink water at 1.99', now: DateTime(2026, 10, 8, 1));
    expect(r.allActions.every((a) => a.type == FridayActionType.none), true);
  });
}
