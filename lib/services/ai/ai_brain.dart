import '../../models/chat_message.dart';
import '../../models/friday_response.dart';
import '../storage/memory_store.dart';
import '../storage/settings_store.dart';
import 'friday_parser.dart';
import 'local_model_service.dart';
import 'offline_engine.dart';
import '../tasks/gold_task.dart';
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
    this.memory,
  }) : offline = offline ?? const OfflineEngine();

  final SettingsStore settings;
  final LocalModelService local;
  final OfflineEngine offline;
  final FridayParser parser;

  /// Plain-Markdown long-term memory (SOUL/MEMORY/USER.md). Optional: when
  /// null or unavailable the brain behaves exactly as before.
  final MemoryStore? memory;

  DateTime _memoryPrimedAt = DateTime.fromMillisecondsSinceEpoch(0);

  static final _rememberCmd = RegExp(
    r'^remember(?:\s+that)?\s+(.+?)[.!]?\s*$',
    caseSensitive: false,
  );
  static final _forgetCmd = RegExp(
    r'^forget(?:\s+that)?\s+(.+?)[.!]?\s*$',
    caseSensitive: false,
  );
  static final _recallCmd = RegExp(
    r'^what do you remember(?:\s+about)?\s*(.*?)[.?]*$',
    caseSensitive: false,
  );

  /// Memory commands are answered locally, never sent to a cloud model.
  Future<FridayResponse?> _handleMemory(String userText) async {
    final store = memory;
    if (store == null) return null;
    final remember = _rememberCmd.firstMatch(userText.trim());
    if (remember != null) {
      final fact = remember.group(1)!;
      // "remember to call mom" is a reminder request, not a saved fact.
      if (fact.toLowerCase().startsWith('to ')) return null;
      final saved = await store.remember(fact);
      return FridayResponse(
        reply: saved ? 'Noted. I will remember that.' : 'Could not save that.',
        source: FridaySource.offline,
      );
    }
    final forget = _forgetCmd.firstMatch(userText.trim());
    if (forget != null) {
      final removed = await store.forget(forget.group(1)!);
      return FridayResponse(
        reply: removed > 0 ? 'Forgotten.' : 'I do not have that saved.',
        source: FridaySource.offline,
      );
    }
    final recall = _recallCmd.firstMatch(userText.trim());
    if (recall != null) {
      final topic = (recall.group(1) ?? '').trim();
      final found =
          topic.isEmpty ? await store.recent() : await store.search(topic);
      final reply = found.isEmpty
          ? (topic.isEmpty
              ? 'I do not have anything saved yet.'
              : 'I do not have anything saved about that.')
          : found.map((l) => l.replaceFirst(RegExp(r'^- '), '')).join('\n');
      return FridayResponse(reply: reply, source: FridaySource.offline);
    }
    return null;
  }

  /// Saved notes join the prompt only when a bullet keyword-matches this
  /// exact request, capped to a few hundred characters - the on-device
  /// model pays nothing on ordinary messages. Memory commands above are
  /// answered locally and never reach a model at all.
  Future<String> _systemFor(String userText) async {
    final store = memory;
    if (store == null) return _system;
    try {
      if (DateTime.now().difference(_memoryPrimedAt).inMinutes >= 1) {
        await store.ensureSeeded();
        _memoryPrimedAt = DateTime.now();
      }
      final section = await store.relevantSection(userText);
      if (section.isEmpty) return _system;
      return '$_system$section';
    } catch (_) {
      return _system;
    }
  }

  static const _systemRaw = '''
You are Friday, the user's phone assistant on an Android phone. Answer briefly and helpfully.
You can run phone actions. Respond with ONLY minified JSON, no markdown, exactly this shape:
{"reply":"<short answer shown to the user>","action":{"type":"none|open_app|play_music|next_music|previous_music|stop_music|read_messages|set_reminder|torch_on|torch_off|volume_up|volume_down|wifi|bluetooth|call_contact|send_text|send_whatsapp|set_volume|set_brightness","app":"<app name if open_app, else empty>","query":"<text to search messages if read_messages, else empty>","after_minutes":<minutes from now if set_reminder, else 0>,"title":"<reminder title if set_reminder, else empty>","body":"<message text if send_text/send_whatsapp, else empty>","target":"<contact name or number for call_contact/send_text, or contact for send_whatsapp, or 0-100 percent for set_volume/set_brightness, else empty>"}}
Pick next_music/previous_music/stop_music for track next/previous/stop controls. Pick play_music to play/resume music in the last-used media app, not open_app. Pick open_app when the user wants an app launched, read_messages when they ask about messages, texts, SMS or their inbox, set_reminder when they ask to be reminded of something, torch_on/torch_off for the flashlight, volume_up/volume_down for volume changes, wifi for Wi-Fi on/off, bluetooth for Bluetooth on/off, call_contact when they want to call someone, send_whatsapp when they name WhatsApp (the message opens in WhatsApp for the user to confirm), send_text only when they say SMS or text, set_volume/set_brightness when they give an exact volume or brightness percent. Otherwise type none.
One message can ask for several things. Then replace "action" with "actions", an array of action objects in the user's order, each with its own target: "set brightness 50 and volume 20" becomes {"reply":"Setting brightness to 50% and volume to 20%.","actions":[{"type":"set_brightness","target":"50"},{"type":"set_volume","target":"20"}]}. The same for mixed requests: "flashlight off and open camera" becomes {"reply":"Turning the flashlight off and opening Camera.","actions":[{"type":"torch_off"},{"type":"open_app","app":"camera"}]}. Only set_volume/set_brightness need target. EVERY part of the message must appear in actions - never drop one.
Use ONLY values the user gave - never invent or guess a number. If the user confirms an earlier request ("do it", "yes", "both"), take the values from that earlier message. When the command already says what to change and to what value, do it - do not ask which one first. Keep the reply under two sentences.''';
  static final _system = _systemRaw.trim();

  Future<FridayResponse> ask(
    String userText, {
    List<ChatMessage> history = const [],
  }) async {
    // Memory commands are local reads/writes, not model calls.
    final memoryReply = await _handleMemory(userText);
    if (memoryReply != null) return memoryReply;
    final system = await _systemFor(userText);
    // Device actions and Oro reads must not go through cloud guessing.
    final command = offline.handle(userText);
    if (GoldTaskRequest.isAlertRequest(userText) ||
        GoldTaskRequest.isWatchLike(userText)) return command;
    if (command.allActions.any((a) => a.type != FridayActionType.none))
      return command;
    for (final provider in settings.buildProviders()) {
      try {
        final raw = await provider.complete(
          system: system,
          history: history.where((m) => !m.localOnly).take(12).toList(),
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
          system: system,
          userText: userText,
          history: history.where((m) => !m.localOnly).take(8).toList(),
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
