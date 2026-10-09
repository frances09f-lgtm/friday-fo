import 'dart:io';
import '../services/link/device_link.dart';
import '../services/ai/offline_engine.dart';
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
  // Nonempty execution results include failures and pending prompts.
  // Never prepend success to them.
  static bool targetIsOtherDevice(String target, {required bool isAndroid}) =>
      (target.toLowerCase() == 'phone' || target.toLowerCase() == 'mobile') != isAndroid;

  static String actionResultReply(String outcome) =>
      outcome.isEmpty ? 'Done.' : outcome;

  FridayController({
    required this.brain,
    required this.router,
    required this.chatStore,
    required this.speech,
    required this.settings,
    this.link,
  });

  final DeviceLink? link;
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

    final remote = RegExp(
            r'\s+(?:on|to)\s+(?:(?:my|the)\s+)?(phone|mobile|laptop|windows|computer)[.!?]*$',
            caseSensitive: false)
        .firstMatch(clean);
    if (remote != null) {
      final target = remote.group(1)!.toLowerCase();
      final targetPhone = target == 'phone' || target == 'mobile';
      if (targetIsOtherDevice(target, isAndroid: Platform.isAndroid)) {
        final reply = link == null ? 'Pair the other device first. No action was run on this device.' : await link!.send(clean.substring(0, remote.start));
        messages.add(ChatMessage(
            id: '${DateTime.now().microsecondsSinceEpoch}r',
            role: MessageRole.friday,
            text: reply,
            at: DateTime.now()));
        busy = false;
        notifyListeners();
        await chatStore.save(messages);
        if (settings.speakReplies) await speech.speak(reply);
        return;
      }
    }
    final localText = remote == null ? clean : clean.substring(0, remote.start);
    final response = await brain.ask(localText, history: List.of(messages));

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
      reply = actionResultReply(outcome);
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

  Future<String> receiveRemote(String text) async {
    if (busy) return 'Friday is busy. Try again in a moment.';
    final response = const OfflineEngine().handle(text);
    const allowed = {
      FridayActionType.openApp,
      FridayActionType.oroStatus,
      FridayActionType.closeAllApps,
      FridayActionType.torchOn,
      FridayActionType.torchOff,
      FridayActionType.volumeUp,
      FridayActionType.volumeDown,
      FridayActionType.setVolume,
      FridayActionType.setBrightness,
      FridayActionType.brightnessUp,
      FridayActionType.brightnessDown,
      FridayActionType.wifiSettings,
      FridayActionType.bluetoothSettings
    };
    final actions = response.allActions
        .where((a) => a.type != FridayActionType.none)
        .toList();
    if (actions.isEmpty || actions.any((a) => !allowed.contains(a.type)))
      return 'Remote command not supported. Use app launch, device controls or Oro questions.';
    if (actions.any((a) =>
        a.type == FridayActionType.openApp &&
        !RegExp(r'^[a-zA-Z0-9 ._-]{1,60}$').hasMatch(a.app))) {
      return 'Use a plain app name for remote launch.';
    }
    busy = true;
    notifyListeners();
    try {
      final result = await router.executeAll(actions);
      final reply = result.isEmpty ? 'Action requested on this device; completion is not verified.' : result;
      messages.add(ChatMessage(
          id: '${DateTime.now().microsecondsSinceEpoch}remote',
          role: MessageRole.friday,
          text: 'From paired device: $text\n$reply',
          at: DateTime.now()));
      await chatStore.save(messages);
      return reply;
    } catch (_) {
      return 'The command failed on the other device.';
    } finally {
      busy = false;
      notifyListeners();
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
