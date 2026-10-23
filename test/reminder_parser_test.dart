import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:friday/models/chat_message.dart';
import 'package:friday/models/friday_response.dart';
import 'package:friday/services/ai/ai_brain.dart';
import 'package:friday/services/device/device_hub.dart';
import 'package:friday/services/device/reminder_service.dart';
import 'package:friday/services/intent_router.dart';
import 'package:friday/services/reminder_parser.dart';
import 'package:friday/services/speech/speech_service.dart';
import 'package:friday/services/storage/chat_store.dart';
import 'package:friday/services/storage/settings_store.dart';
import 'package:friday/state/friday_controller.dart';

class Recorder extends ReminderService {
  int calls = 0;
  Duration? delay;
  String? title;
  @override
  Future<bool> schedule(
      {required String title,
      required String body,
      required Duration after}) async {
    calls++;
    delay = after;
    this.title = title;
    return true;
  }
}

class NoSpeech extends SpeechService {
  @override
  Future<void> speak(String t, {String locale = 'en-IN'}) async {}
}

/// Throws if asked, so a passing test proves no model ran.
class ModelMustNotRun implements AIBrain {
  @override
  Future<FridayResponse> ask(String text,
      {List<ChatMessage> history = const []}) {
    throw StateError('a model must not run for a simple reminder');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<(FridayController, Recorder)> _controller() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsStore(const FlutterSecureStorage(), prefs)
    ..speakReplies = false;
  final recorder = Recorder();
  final c = FridayController(
      brain: ModelMustNotRun(),
      router: IntentRouter(deviceHub: DeviceHub(), reminders: recorder),
      chatStore: ChatStore(prefs),
      speech: NoSpeech(),
      settings: settings);
  return (c, recorder);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 23, 21, 40, 10);

  group('parser reads times', () {
    for (final text in [
      'remind me to drink water at 942',
      'remind me to drink water at 9:42',
      'Remind me to drink water at 9.42 pm',
      'remind me to drink water at 2142',
      'remind me to drink water at 21:42.',
      'set a reminder to drink water at 9:42 pm please',
    ]) {
      test(text, () {
        final r = ReminderParser.parse(text, now)!;
        expect(r.ok, true);
        expect(r.task, 'drink water');
        expect(r.when, DateTime(2026, 10, 23, 21, 42));
        expect(r.afterMinutes, 2);
        expect(r.relative, false);
        expect(r.toAction().type, FridayActionType.setReminder);
        expect(r.toAction().target, '2026-10-23T21:42:00.000');
      });
    }
    test('am rolls to tomorrow', () {
      final r = ReminderParser.parse('remind me to drink water at 9:42am', now)!;
      expect(r.when, DateTime(2026, 10, 24, 9, 42));
    });
    test('a time with no am or pm takes the next occurrence', () {
      final r = ReminderParser.parse('remind me at 9 to call mom', now)!;
      expect(r.task, 'call mom');
      expect(r.when, DateTime(2026, 10, 24, 9, 0));
    });
    test('tomorrow word', () {
      final r =
          ReminderParser.parse('remind me tomorrow to pay rent at 8 am', now)!;
      expect(r.task, 'pay rent');
      expect(r.when, DateTime(2026, 10, 24, 8, 0));
    });
    test('task keeps an earlier at', () {
      final r =
          ReminderParser.parse('remind me to meet at the cafe at 5pm', now)!;
      expect(r.task, 'meet at the cafe');
      expect(r.when, DateTime(2026, 10, 24, 17, 0));
    });
    test('in minutes, hours, an hour, half an hour', () {
      final a = ReminderParser.parse('remind me to stretch in 10 minutes', now)!;
      expect(a.relative, true);
      expect(a.afterMinutes, 10);
      expect(a.toAction().target, '');
      expect(ReminderParser.parse('remind me to stretch in 2 hours', now)!
          .afterMinutes, 120);
      expect(ReminderParser.parse('remind me to stretch in an hour', now)!
          .afterMinutes, 60);
      expect(ReminderParser.parse('remind me in half an hour to stretch', now)!
          .afterMinutes, 30);
    });
  });

  group('parser says so when it cannot read the time', () {
    test('minute over 59', () {
      expect(ReminderParser.parse('remind me to drink water at 1.99', now)!.error,
          ReminderParser.badTimeMessage);
    });
    test('hour over 23', () {
      expect(ReminderParser.parse('remind me to drink water at 25', now)!.error,
          ReminderParser.badTimeMessage);
    });
    test('13 with pm', () {
      expect(ReminderParser.parse('remind me to drink water at 13pm', now)!.error,
          ReminderParser.badAmPmMessage);
    });
    test('no time at all', () {
      expect(ReminderParser.parse('remind me to drink water', now)!.error,
          ReminderParser.noTimeMessage);
    });
    test('no task', () {
      expect(ReminderParser.parse('remind me', now)!.error,
          ReminderParser.noTaskMessage);
    });
    test('not a reminder request', () {
      expect(ReminderParser.parse('what is the weather', now), isNull);
      expect(ReminderParser.parse('remind Sam to call at 5', now), isNull);
      expect(ReminderParser.parse('what reminders do i have', now), isNull);
    });
  });

  test('describe shows weekday, date and 12-hour time', () {
    expect(ReminderParser.describe(DateTime(2026, 10, 23, 21, 42)),
        'Fri 23 Oct, 9:42 PM');
    expect(ReminderParser.describe(DateTime(2026, 10, 24, 0, 5)),
        'Sat 24 Oct, 12:05 AM');
    expect(ReminderParser.describe(DateTime(2026, 10, 24, 12, 0)),
        'Sat 24 Oct, 12:00 PM');
  });

  test('chat saves "at 942" with no model and confirms task and time',
      () async {
    final (c, recorder) = await _controller();
    await c.send('remind me to drink water at 942');
    expect(recorder.calls, 1);
    expect(recorder.title, 'drink water');
    expect(recorder.delay! > Duration.zero, true);
    expect(c.messages.length, 2);
    final reply = c.messages.last.text;
    expect(reply, startsWith('Reminder registered for '));
    expect(reply, endsWith(': drink water.'));
    expect(reply, matches(RegExp(r'9:42 (AM|PM)')));
    expect(c.busy, false);
    c.dispose();
  });

  test('chat saves "in 2 minutes" with no model', () async {
    final (c, recorder) = await _controller();
    await c.send('remind me to drink water in 2 minutes');
    expect(recorder.calls, 1);
    expect(recorder.delay, const Duration(minutes: 2));
    expect(c.messages.last.text, contains('drink water'));
    c.dispose();
  });

  test('chat says plainly when the time cannot be read and saves nothing',
      () async {
    final (c, recorder) = await _controller();
    await c.send('remind me to drink water');
    expect(recorder.calls, 0);
    expect(c.messages.last.text, ReminderParser.noTimeMessage);
    expect(c.messages.last.text, contains('no reminder was saved'));
    c.dispose();
  });

  test('a reminder does not auto-close the floating panel', () async {
    final (c, _) = await _controller();
    final before = c.completedCommandRevision;
    await c.send('remind me to drink water at 942');
    expect(c.completedCommandRevision, before);
    c.dispose();
  });
}
