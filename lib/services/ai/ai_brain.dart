import '../../models/chat_message.dart';
import '../../models/friday_response.dart';
import '../storage/settings_store.dart';
import 'friday_parser.dart';
import 'local_model_service.dart';
import 'offline_engine.dart';
import '../usage_reporter.dart';

/// Friday's thinking pipeline, with the fallback ladder built in:
/// every configured cloud key first, then the on-device Gemma model,
/// then the pure off-line pattern engine.
class AIBrain {
  AIBrain({
    required this.settings,
    required this.local,
    OfflineEngine? offline,
    this.parser = const FridayParser(),
  }) : offline = offline ?? const OfflineEngine();

  final SettingsStore settings;
  final LocalModelService local;
  final OfflineEngine offline;
  final FridayParser parser;

  static const _systemRaw = '''
You are Friday, the user's phone assistant on an Android phone. Answer briefly and helpfully.
You can run phone actions. Respond with ONLY minified JSON, no markdown, exactly this shape:
{"reply":"<short answer shown to the user>","action":{"type":"none|open_app|read_messages|set_reminder|torch_on|torch_off|volume_up|volume_down|wifi|bluetooth|call_contact|send_text|set_volume|set_brightness","app":"<app name if open_app, else empty>","query":"<text to search messages if read_messages, else empty>","after_minutes":<minutes from now if set_reminder, else 0>,"title":"<reminder title if set_reminder, else empty>","body":"<message text if send_text, else empty>","target":"<contact name or number for call_contact/send_text, or 0-100 percent for set_volume/set_brightness, else empty>"}}
Pick open_app when the user wants an app launched, read_messages when they ask about messages, texts, SMS or their inbox, set_reminder when they ask to be reminded of something, torch_on/torch_off for the flashlight, volume_up/volume_down for volume changes, wifi for Wi-Fi on/off, bluetooth for Bluetooth on/off, call_contact when they want to call someone, send_text when they want to text or SMS someone, set_volume/set_brightness when they give an exact volume or brightness percent. Otherwise type none.
One message can ask for several things. Then replace "action" with "actions", an array of action objects in the user's order, each with its own target: "set brightness 50 and volume 20" becomes {"reply":"Setting brightness to 50% and volume to 20%.","actions":[{"type":"set_brightness","target":"50"},{"type":"set_volume","target":"20"}]}.
Use ONLY values the user gave - never invent or guess a number. If the user confirms an earlier request ("do it", "yes", "both"), take the values from that earlier message. When the command already says what to change and to what value, do it - do not ask which one first. Keep the reply under two sentences.''';
  static final _system = _systemRaw.trim();

  Future<FridayResponse> ask(
    String userText, {
    List<ChatMessage> history = const [],
  }) async {
    for (final provider in settings.buildProviders()) {
      try {
        final raw = await provider.complete(
          system: _system,
          history: history.take(12).toList(),
          userText: userText,
        );
        final parsed = parser.parse(raw, source: FridaySource.cloud);
        if (parsed.reply.trim().isNotEmpty) {
          UsageReporter.report('ai_request', {'tier': 'cloud'});
          return parsed;
        }
      } catch (_) {
        // Key missing, quota gone, network down: try the next brain.
      }
    }

    if (settings.localFallbackEnabled) {
      try {
        final raw = await local.generate(
          system: _system,
          userText: userText,
          history: history.take(8).toList(),
        );
        final parsed = parser.parse(raw, source: FridaySource.local);
        if (parsed.reply.trim().isNotEmpty) {
          UsageReporter.report('ai_request', {'tier': 'local'});
          return parsed;
        }
      } catch (_) {
        // No model installed or the device could not load it: drop to offline.
      }
    }

    UsageReporter.report('ai_request', {'tier': 'offline'});
    return offline.handle(userText);
  }
}
