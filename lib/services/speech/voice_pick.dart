import '../ai/offline_engine.dart';
import '../reminder_parser.dart';
import '../tasks/gold_task.dart';
import '../../models/friday_response.dart';

/// One way the recognizer heard the user, with its confidence (0..1, or a
/// negative number when the recognizer gave none).
class HeardText {
  const HeardText(this.text, [this.confidence = -1]);
  final String text;
  final double confidence;
}

/// Picks which of the recognizer's alternatives Friday acts on.
///
/// Android's recognizer returns up to 10 guesses for one utterance. The top
/// guess wins unless Friday cannot read it as a command and a close
/// alternative reads as one ("tell me when gold goes about 4000" vs "...
/// above 4000"). Plain conversation keeps the top guess.
class VoicePick {
  const VoicePick._();

  /// True when Friday reads [text] as a command it can act on directly.
  static bool understood(String text, {DateTime? now}) {
    final t = text.trim();
    if (t.isEmpty) return false;
    if (GoldTaskRequest.parse(t) != null) return true;
    final reminder = ReminderParser.parse(t, now ?? DateTime.now());
    if (reminder != null && reminder.ok) return true;
    try {
      return const OfflineEngine()
          .handle(t, now: now)
          .allActions
          .any((a) => a.type != FridayActionType.none);
    } catch (_) {
      return false;
    }
  }

  static Set<String> _words(String s) => s
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toSet();

  /// Share of the shorter text's words that the other text also has.
  static double overlap(String a, String b) {
    final x = _words(a), y = _words(b);
    if (x.isEmpty || y.isEmpty) return 0;
    final shared = x.intersection(y).length;
    return shared / (x.length < y.length ? x.length : y.length);
  }

  static String choose(List<HeardText> heard, {DateTime? now}) {
    final options = heard.where((h) => h.text.trim().isNotEmpty).toList();
    if (options.isEmpty) return '';
    final top = options.first;
    if (understood(top.text, now: now)) return top.text;
    HeardText? best;
    for (final h in options.skip(1)) {
      if (overlap(top.text, h.text) < 0.5) continue;
      if (!understood(h.text, now: now)) continue;
      if (best == null || h.confidence > best.confidence) best = h;
    }
    return (best ?? top).text;
  }
}

/// Words Friday's commands use, given to the recognizer as hints where it
/// takes them (Android 13+ biasing strings, Whisper's prompt).
class CommandVocabulary {
  const CommandVocabulary._();

  static const words = [
    'Friday', 'alert', 'alert me', 'notify me', 'tell me when', 'remind me',
    'gold', 'gold price', 'silver', 'nifty', 'sensex', 'price', 'above',
    'below', 'over', 'under', 'crosses', 'reaches', 'drops to', 'every',
    'minutes', 'hours', 'task', 'tasks', 'Sona', 'Lookout', 'WhatsApp',
    'volume', 'brightness', 'flashlight',
  ];

  /// A short sample of how commands are said, for Whisper's prompt.
  static const prompt =
      'Friday voice commands. Alert me when gold goes above 4,000. Tell me when gold goes below 3,950. Notify me when gold price crosses 4,100. Check gold every 10 minutes. Remind me in 30 minutes. Open WhatsApp.';
}
