import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:friday/models/friday_response.dart';
import 'package:friday/services/ai/ai_brain.dart';
import 'package:friday/services/ai/local_model_service.dart';
import 'package:friday/services/device/device_hub.dart';
import 'package:friday/services/device/reminder_service.dart';
import 'package:friday/services/intent_router.dart';
import 'package:friday/services/speech/speech_service.dart';
import 'package:friday/services/storage/chat_store.dart';
import 'package:friday/services/storage/settings_store.dart';
import 'package:friday/state/friday_controller.dart';

class _FakeBrain extends AIBrain {
  _FakeBrain(SettingsStore settings, this._response)
      : super(settings: settings, local: LocalModelService());
  final FridayResponse _response;
  @override
  Future<FridayResponse> ask(String userText,
          {List<dynamic> history = const []}) async =>
      _response;
}

class _FakeRouter extends IntentRouter {
  _FakeRouter() : super(deviceHub: DeviceHub(), reminders: ReminderService());
  String outcome = '';
  @override
  Future<String> executeAll(List<FridayAction> actions) async => outcome;
}

class _FakeSpeech extends SpeechService {
  @override
  Future<void> speak(String text, {String locale = 'en-IN'}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('silent outcome means the confirmation is just Done.', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsStore(const FlutterSecureStorage(), prefs);
    final c = FridayController(
      brain: _FakeBrain(
          settings,
          FridayResponse(
            reply: 'Opening whatsapp.',
            action: const FridayAction(
                type: FridayActionType.openApp, app: 'whatsapp'),
            source: FridaySource.offline,
          )),
      router: _FakeRouter(), // outcome stays '' - echo silenced
      chatStore: ChatStore(prefs),
      speech: _FakeSpeech(),
      settings: settings,
    );
    await c.send('open whatsapp');
    final texts = c.messages.map((m) => m.text).toList();
    expect(texts, ['open whatsapp', 'Done.']);
  });
}
