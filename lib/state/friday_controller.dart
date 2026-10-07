import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../models/friday_response.dart';
import '../services/ai/ai_brain.dart';
import '../services/intent_router.dart';
import '../services/speech/speech_service.dart';
import '../services/storage/chat_store.dart';
import '../services/storage/settings_store.dart';

/// Holds the conversation and runs one turn end to end:
/// user input -> brain (cloud, then local, then offline) -> action -> reply.
class FridayController extends ChangeNotifier {
  FridayController({
    required this.brain,
    required this.router,
    required this.chatStore,
    required this.speech,
    required this.settings,
  });

  final AIBrain brain;
  final IntentRouter router;
  final ChatStore chatStore;
  final SpeechService speech;
  final SettingsStore settings;

  final List<ChatMessage> messages = [];
  bool busy = false;
  String partialHeard = '';

  Future<void> loadHistory() async {
    final saved = chatStore.load();
    if (saved.isNotEmpty) {
      messages.addAll(saved);
      notifyListeners();
    }
  }

  /// Every send speaks its reply unless the user muted Friday in Settings.
  Future<void> send(String text) async {
    final clean = text.trim();
    if (clean.isEmpty || busy) return;

    final userMessage = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: MessageRole.user,
      text: clean,
      at: DateTime.now(),
    );
    messages.add(userMessage);
    busy = true;
    notifyListeners();

    final response = await brain.ask(clean, history: List.of(messages));

    var reply = response.reply;
    // Ignore the placeholder none action - plain conversation gets no
    // okay/done wrapper.
    final actions = response.allActions
        .where((a) => a.type != FridayActionType.none)
        .toList();
    final infoOnly = actions.isNotEmpty &&
        actions.every((a) => a.type == FridayActionType.oroStatus);
    if (infoOnly) {
      // A question, not a task: no okay/done wrapper - the answer from
      // Oro's real data is the reply itself.
      reply = await router.executeAll(actions);
      if (reply.isEmpty) reply = "I couldn't read Oro's data.";
    } else if (actions.isNotEmpty) {
      // Acknowledge on acceptance, confirm on completion - the user hears
      // "okay" when Friday takes the command and "done" when it finished.
      messages.add(ChatMessage(
        id: '${DateTime.now().microsecondsSinceEpoch}a',
        role: MessageRole.friday,
        text: 'Okay.',
        at: DateTime.now(),
      ));
      notifyListeners();
      if (settings.speakReplies) {
        await speech.speak('Okay.');
      }
      final outcome = await router.executeAll(actions);
      // The router's outcome is the truth - the brain's reply only guessed
      // at the result ("Reminder set" before it was).
      reply = outcome.isEmpty ? 'Done.' : 'Done.\n$outcome';
    }

    messages.add(ChatMessage(
      id: '${DateTime.now().microsecondsSinceEpoch}r',
      role: MessageRole.friday,
      text: reply,
      at: DateTime.now(),
    ));
    busy = false;
    partialHeard = '';
    notifyListeners();

    await chatStore.save(messages);
    if (settings.speakReplies) {
      await speech.speak(reply);
    }
  }

  void setPartialHeard(String text) {
    partialHeard = text;
    notifyListeners();
  }

  Future<void> clearConversation() async {
    messages.clear();
    await chatStore.clear();
    notifyListeners();
  }
}
