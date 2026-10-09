import 'dart:io';
import '../services/agent/agent_contract.dart';
import '../services/agent/friday_agent.dart';

import '../services/context/oro_context.dart';
import '../services/tasks/gold_task.dart';
import '../services/tasks/task_service.dart';
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
  static String actionResultReply(String outcome) =>
      outcome.isEmpty ? 'Done.' : outcome;

  static String conciseReply(String text) =>
      text.startsWith('Reminder registered for ') ? 'Done' : text;

  FridayController({
    required this.brain,
    required this.router,
    required this.chatStore,
    required this.speech,
    required this.settings,
    this.link,
    this.agentRunning,
    this.screenAgent,
  });

  final FridayAgent? screenAgent;
  final DeviceLink? link;
  final bool Function()? agentRunning;
  final AIBrain brain;
  final IntentRouter router;
  final ChatStore chatStore;
  final SpeechService speech;
  final SettingsStore settings;

  final List<ChatMessage> messages = [];
  bool busy = false;
  String phase = 'Ready';
  String partialHeard = '';
  final oroContext = OroContext();

  Future<void> loadHistory() async {
    final saved = chatStore.load();
    if (saved.isNotEmpty) {
      messages.addAll(saved);
      notifyListeners();
    }
  }

  /// Every send speaks its reply unless the user muted Friday in Settings.
  Future<void> send(String text) async {
    if (text.trim().isEmpty || busy || agentRunning?.call() == true) return;
    try {
      await _send(text);
    } catch (_) {
      messages.add(
        ChatMessage(
          id: '${DateTime.now().microsecondsSinceEpoch}failure',
          role: MessageRole.friday,
          text:
              'This request did not finish cleanly. A started action may already have happened; check before retrying.',
          at: DateTime.now(),
        ),
      );
      try {
        await chatStore.save(messages);
      } catch (_) {}
    } finally {
      busy = false;
      phase = 'Ready';
      partialHeard = '';
      notifyListeners();
    }
  }

  Future<void> _send(String text) async {
    final original = text.trim();
    if (original.isEmpty || busy) return;
    final clean = oroContext.resolve(original, DateTime.now()) ?? original;

    final userMessage = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: MessageRole.user,
      text: original,
      at: DateTime.now(),
    );
    messages.add(userMessage);
    busy = true;
    phase = 'Thinking';
    notifyListeners();

    if (Platform.isAndroid &&
        screenAgent != null &&
        AgentGoal.parse(clean) != null) {
      phase = 'Screen control';
      notifyListeners();
      await screenAgent!.start(clean);
      final reply = screenAgent!.result;
      final privateScreen = screenAgent!.goal?.workflow == 'read';
      messages.add(ChatMessage(
          id: '${DateTime.now().microsecondsSinceEpoch}agent',
          role: MessageRole.friday,
          text: privateScreen
              ? 'Screen read completed. Open Agent Mode to see the transient result.'
              : reply,
          at: DateTime.now(),
          localOnly: true));
      busy = false;
      notifyListeners();
      await chatStore.save(messages);
      if (settings.speakReplies) await speech.speak(reply);
      return;
    }
    final goldTask = GoldTaskRequest.parse(clean);
    final cancelGold = RegExp(
      r'^(?:cancel|stop) (?:all |my )?gold (?:alerts|tasks|checks)[.!]?$',
      caseSensitive: false,
    ).hasMatch(clean);
    if (goldTask != null || cancelGold) {
      oroContext.clear();
      String reply;
      try {
        reply = goldTask != null
            ? await TaskService().create(goldTask)
            : await TaskService().cancelAll();
      } catch (_) {
        reply =
            'Could not update background tasks. Open Background tasks to check their saved state.';
      }
      messages.add(
        ChatMessage(
          id: '${DateTime.now().microsecondsSinceEpoch}task',
          role: MessageRole.friday,
          text: reply,
          at: DateTime.now(),
        ),
      );
      busy = false;
      phase = 'Ready';
      notifyListeners();
      await chatStore.save(messages);
      if (settings.speakReplies) await speech.speak(conciseReply(reply));
      return;
    }

    final remote = RegExp(
      r'\s+(?:on|to)\s+(?:my|the)\s+(phone|mobile|laptop|windows|computer)[.!?]*$',
      caseSensitive: false,
    ).firstMatch(clean);
    if (remote != null && link != null) {
      final target = remote.group(1)!.toLowerCase();
      final targetPhone = target == 'phone' || target == 'mobile';
      if (targetPhone != Platform.isAndroid) {
        final remoteText = clean.substring(0, remote.start);
        final isOro = const OfflineEngine()
            .handle(remoteText)
            .allActions
            .any((a) => a.type == FridayActionType.oroStatus);
        if (isOro)
          oroContext.remember(
            DateTime.now(),
            device: targetPhone ? 'phone' : 'laptop',
          );
        else
          oroContext.clear();
        final reply = await link!.send(remoteText);
        messages.add(
          ChatMessage(
            id: '${DateTime.now().microsecondsSinceEpoch}r',
            role: MessageRole.friday,
            text: reply,
            at: DateTime.now(),
          ),
        );
        busy = false;
        phase = 'Ready';
        notifyListeners();
        await chatStore.save(messages);
        if (settings.speakReplies) await speech.speak(conciseReply(reply));
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
        actions.every((a) =>
            a.type == FridayActionType.oroStatus ||
            a.type == FridayActionType.lookoutStatus);
    if (infoOnly) {
      if (actions.any((a) => a.type == FridayActionType.oroStatus)) {
        oroContext.remember(DateTime.now());
      } else {
        oroContext.clear();
      }
      // A question, not a task: no okay/done wrapper - the answer from
      // Oro's real data is the reply itself.
      reply = await router.executeAll(actions);
      if (reply.isEmpty) reply = "I couldn't read Sona's saved data.";
    } else if (actions.isNotEmpty) {
      oroContext.clear();
      // One final result, not a second acknowledgement bubble.
      phase = 'Doing';
      notifyListeners();
      final outcome = await router.executeAll(actions);
      // The router's outcome is the truth - the brain's reply only guessed
      // at the result ("Reminder set" before it was).
      reply = actionResultReply(outcome);
    }

    if (!infoOnly && actions.isEmpty) oroContext.clear();
    messages.add(
      ChatMessage(
        id: '${DateTime.now().microsecondsSinceEpoch}r',
        role: MessageRole.friday,
        text: reply,
        localOnly: infoOnly,
        at: DateTime.now(),
      ),
    );
    busy = false;
    partialHeard = '';
    notifyListeners();

    await chatStore.save(messages);
    if (settings.speakReplies) {
      await speech.speak(conciseReply(reply));
    }
  }

  Future<String> receiveRemote(String text) async {
    if (busy || agentRunning?.call() == true)
      return 'Friday is busy. Try again in a moment.';
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
      FridayActionType.bluetoothSettings,
    };
    final actions = response.allActions
        .where((a) => a.type != FridayActionType.none)
        .toList();
    if (actions.isEmpty || actions.any((a) => !allowed.contains(a.type)))
      return 'Remote command not supported. Use app launch, device controls or Oro questions.';
    if (actions.any(
      (a) =>
          a.type == FridayActionType.openApp &&
          !RegExp(r'^[a-zA-Z0-9 ._-]{1,60}$').hasMatch(a.app),
    )) {
      return 'Use a plain app name for remote launch.';
    }
    busy = true;
    phase = 'Thinking';
    notifyListeners();
    try {
      final result = await router.executeAll(actions);
      final reply = result.isEmpty ? 'Done on this device.' : result;
      messages.add(
        ChatMessage(
          id: '${DateTime.now().microsecondsSinceEpoch}remote',
          role: MessageRole.friday,
          text: 'From paired device: $text\n$reply',
          at: DateTime.now(),
        ),
      );
      await chatStore.save(messages);
      return reply;
    } catch (_) {
      return 'The command failed on the other device.';
    } finally {
      busy = false;
      phase = 'Ready';
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
