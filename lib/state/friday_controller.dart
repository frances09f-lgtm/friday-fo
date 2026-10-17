import 'dart:io';
import '../services/agent/agent_contract.dart';
import '../services/agent/compound_command.dart';
import '../services/agent/gallery_command.dart';
import '../services/agent/workflow_planner.dart';
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
  static bool targetIsOtherDevice(String target, {required bool isAndroid}) =>
      (target.toLowerCase() == 'phone' || target.toLowerCase() == 'mobile') !=
      isAndroid;

  static String actionResultReply(String outcome) =>
      outcome.isEmpty ? 'Done.' : outcome;

  static String conciseReply(String text) =>
      text.startsWith('Reminder registered for ') ? 'Done' : text;

  /// Action speech is separate from the full on-screen result. Unknown or
  /// unverified outcomes must never sound like a completed action.
  static String spokenActionReply(String text) {
    final lines =
        text.split('\n').where((line) => line.trim().isNotEmpty).toList();
    if (lines.isEmpty || (text.trim() == 'Done.' || text.trim() == 'Done'))
      return 'Done';
    bool verified(String line) =>
        line.startsWith('Media volume verified by two readbacks.') ||
        line.startsWith('Spotify ') &&
            line.contains(' verified from playback or track state.') ||
        line.startsWith('Reminder registered for ') ||
        line.trim() == 'Done.';
    if (lines.every(verified)) return 'Done';
    final lower = text.toLowerCase();
    if (lower.contains('already at target') ||
        lower.contains('already playing') ||
        lower.contains('already paused') ||
        lower.contains('already at its limit')) return 'No change needed';
    if (lower.contains('no success claimed') ||
        lower.contains('not verified') ||
        lower.contains('could not') ||
        lower.contains("couldn't") ||
        lower.contains('refused') ||
        lower.contains('timed out') ||
        lower.contains('failed')) return "Couldn't do it";
    if (lower.contains('cancelled') ||
        lower.contains('closed before') ||
        lower.contains('stopped')) return 'Stopped';
    return 'Check the screen';
  }

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

  /// Changes only after an executed command returns a terminal result suitable
  /// for clearing the floating panel. Speech/history persistence may still run.
  int completedCommandRevision = 0;
  void _commandFinished(String outcome) {
    if (IntentRouter.completedCommandOutcome(outcome)) {
      completedCommandRevision++;
    }
  }

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
    final literalMessage = const OfflineEngine().handle(text);
    final isLiteralWhatsApp =
        literalMessage.action.type == FridayActionType.sendWhatsApp &&
            literalMessage.extraActions.isEmpty;
    final original =
        isLiteralWhatsApp ? text : text.trim().replaceAll(RegExp(r'\s+'), ' ');
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

    // An explicit WhatsApp body is literal data, not device-routing syntax or
    // another command. Parse the untouched input before whitespace cleanup or
    // task/agent routing; keep the normal native recipient confirmation path.
    if (isLiteralWhatsApp) {
      oroContext.clear();
      phase = 'Doing';
      notifyListeners();
      final outcome = await router.executeAll([literalMessage.action]);
      _commandFinished(outcome);
      final reply = actionResultReply(outcome);
      messages.add(ChatMessage(
        id: '${DateTime.now().microsecondsSinceEpoch}wa',
        role: MessageRole.friday,
        text: reply,
        at: DateTime.now(),
      ));
      busy = false;
      partialHeard = '';
      phase = 'Ready';
      notifyListeners();
      await chatStore.save(messages);
      if (settings.speakReplies) await speech.speak(spokenActionReply(reply));
      return;
    }

    final remote = RegExp(
      r'\s+(?:on|to)\s+(?:(?:my|the)\s+)?(phone|mobile|laptop|windows|computer)[.!?]*$',
      caseSensitive: false,
    ).firstMatch(clean);
    if (remote != null) {
      final target = remote.group(1)!.toLowerCase();
      final targetPhone = target == 'phone' || target == 'mobile';
      if (targetIsOtherDevice(target, isAndroid: Platform.isAndroid)) {
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
        final reply = link == null
            ? 'Pair the other device first. No action was run on this device.'
            : await link!.send(remoteText);
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
    final whatsappSearch = RegExp(
            r'^(?:please )?open whats\s*app(?: and)? search(?: for)? (.+?)[.!?]?$',
            caseSensitive: false)
        .firstMatch(localText);
    if (Platform.isAndroid && whatsappSearch != null) {
      final query = whatsappSearch[1]!.trim();
      String reply =
          'Friday v61: WhatsApp search needs screen-control access. No search run.';
      if (screenAgent != null && query.isNotEmpty && query.length <= 250) {
        await screenAgent!.start('open whatsapp and search for $query');
        reply = 'Friday v61 WhatsApp search: ${screenAgent!.result}';
        if (screenAgent!.result == 'Done' ||
            screenAgent!.result ==
                'Requested controls executed with observed screen changes. Check the final screen.') {
          completedCommandRevision++;
        }
      }
      messages.add(ChatMessage(
          id: '${DateTime.now().microsecondsSinceEpoch}wasearch',
          role: MessageRole.friday,
          text: reply,
          at: DateTime.now(),
          localOnly: true));
      busy = false;
      phase = 'Ready';
      notifyListeners();
      await chatStore.save(messages);
      if (settings.speakReplies) await speech.speak(reply);
      return;
    }
    if (Platform.isAndroid &&
        screenAgent != null &&
        RegExp(r'^play (?:the )?first video[.!?]?$', caseSensitive: false)
            .hasMatch(localText.trim())) {
      // Observe fresh underlying screen. Never infer a Gallery default or reuse
      // old search history; only a uniquely identified current YouTube query.
      await screenAgent!.start('read my screen');
      final screen = screenAgent!.observation;
      final fields = ((screen['elements'] as List?) ?? [])
          .where((e) =>
              e['editable'] == true &&
              e['text'] is String &&
              RegExp(r'search', caseSensitive: false)
                  .hasMatch('${e['resourceId']} ${e['contentDescription']}'))
          .toList();
      String reply =
          'Open YouTube search results with a visible exact search query first, or say open gallery and play first video. No video selected.';
      if (screen['package'] == 'com.google.android.youtube' &&
          fields.length == 1) {
        final query = fields.single['text'].toString().trim();
        if (query.isNotEmpty && query.length <= 200) {
          final task = 'open youtube search for $query and play first video';
          final g = AgentGoal.parse(task);
          if (g != null && WorkflowPlanner.searchResults(g, screen)) {
            await screenAgent!.start(task);
            reply = screenAgent!.result;
          }
        }
      }
      messages.add(ChatMessage(
          id: '${DateTime.now().microsecondsSinceEpoch}first',
          role: MessageRole.friday,
          text: reply,
          at: DateTime.now(),
          localOnly: true,
          transient: true));
      busy = false;
      phase = 'Ready';
      notifyListeners();
      await chatStore.save(messages);
      if (settings.speakReplies) await speech.speak(reply);
      return;
    }
    if (Platform.isAndroid &&
        screenAgent != null &&
        AgentGoal.parse(localText) != null) {
      phase = 'Screen control';
      notifyListeners();
      await screenAgent!.start(localText);
      final reply = screenAgent!.result;
      if (screenAgent!.result == 'Done' ||
          screenAgent!.result ==
              'Requested controls executed with observed screen changes. Check the final screen.') {
        completedCommandRevision++;
      }
      final privateScreen = screenAgent!.goal?.workflow == 'read';
      messages.add(ChatMessage(
          id: '${DateTime.now().microsecondsSinceEpoch}agent',
          role: MessageRole.friday,
          text: reply,
          at: DateTime.now(),
          localOnly: true,
          transient: privateScreen));
      busy = false;
      notifyListeners();
      await chatStore.save(messages);
      if (settings.speakReplies)
        await speech.speak(privateScreen ? reply : spokenActionReply(reply));
      return;
    }
    final galleryIndex = GalleryCommand.parse(localText);
    if (galleryIndex != null) {
      final reply = await router.deviceHub.galleryVideo(galleryIndex);
      messages.add(ChatMessage(
          id: '${DateTime.now().microsecondsSinceEpoch}gallery',
          role: MessageRole.friday,
          text: reply,
          at: DateTime.now(),
          localOnly: true));
      busy = false;
      phase = 'Ready';
      notifyListeners();
      await chatStore.save(messages);
      if (settings.speakReplies) await speech.speak(reply);
      return;
    }
    final compound = CompoundCommand.parse(localText);
    if (compound != null && AgentGoal.parse(localText) == null) {
      // Do not pass the entire compound string to app-name matching, or let
      // a chat model invent unsupported execution of the remaining action.
      final opened = await router.execute(
          FridayAction(type: FridayActionType.openApp, app: compound.app));
      final reply =
          '$opened The requested action "${compound.action}" is not supported for this app yet. No such action was run.';
      messages.add(ChatMessage(
          id: '${DateTime.now().microsecondsSinceEpoch}compound',
          role: MessageRole.friday,
          text: reply,
          at: DateTime.now(),
          localOnly: true));
      busy = false;
      phase = 'Ready';
      notifyListeners();
      await chatStore.save(messages);
      if (settings.speakReplies)
        await speech.speak(
            'That action is not supported yet. Check the app launch result.');
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
      _commandFinished(outcome);
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
      await speech.speak(!infoOnly && actions.isNotEmpty
          ? spokenActionReply(reply)
          : conciseReply(reply));
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
      final reply = result.isEmpty
          ? 'Action requested on this device; completion is not verified.'
          : result;
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
