import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
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
    final outcome = await router.execute(response.action);
    if (outcome.isNotEmpty) reply = '$reply\n$outcome';

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
      await speech.speak(response.reply);
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
