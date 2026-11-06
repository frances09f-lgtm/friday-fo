import 'dart:async';
import 'dart:io';
import '../services/agent/agent_contract.dart';
import '../services/agent/compound_command.dart';
import '../services/agent/gallery_command.dart';
import '../services/agent/workflow_planner.dart';
import '../services/agent/friday_agent.dart';

import '../services/context/oro_context.dart';
import '../services/context/price_subject_context.dart';
import '../services/oro/trade_command.dart';
import '../services/oro/trade_flow.dart';
import '../services/oro/oro_bridge.dart';
import '../services/tasks/gold_task.dart';
import '../services/tasks/task_service.dart';
import '../services/link/device_link.dart';
import '../services/reminder_parser.dart';
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
        (line.startsWith('Spotify ') || line.startsWith('BitChord ')) &&
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
    OroTradeDesk? tradeDesk,
    Duration tradeTimeout = const Duration(seconds: 45),
    Duration tradePoll = const Duration(milliseconds: 700),
    this.requestTimeout = const Duration(seconds: 60),
  })  : _tradeDesk = tradeDesk,
        _tradeTimeout = tradeTimeout,
        _tradePoll = tradePoll;

  /// Longest a single model answer may take before the request is stopped
  /// with an honest failure instead of spinning forever.
  final Duration requestTimeout;

  /// Sona paper-order path (see trade_flow.dart). Built on first use.
  OroTradeDesk? _tradeDesk;
  OroTradeDesk get tradeDesk =>
      _tradeDesk ??= DeviceOroTradeDesk(router.deviceHub);
  final Duration _tradeTimeout;
  final Duration _tradePoll;
  PendingTrade? _pendingTrade;
  TradeDraft? _tradeDraft;
  DateTime? _tradeDraftAt;

  /// The trade confirmation currently waiting for Confirm/Cancel, if any.
  PendingTrade? get pendingTrade =>
      _pendingTrade != null && !_pendingTrade!.expired(DateTime.now())
          ? _pendingTrade
          : null;

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

  /// Bumped by every send and by cancel(), so a late completion from a
  /// cancelled or superseded request can never reset state or post its reply.
  int _requestGeneration = 0;
  Completer<void>? _abort;
  Future<void>? _stopping;

  Future<T> _wait<T>(Future<T> work, int generation) async {
    if (generation != _requestGeneration) throw const _RequestCancelled();
    final abort = _abort!;
    final value = await Future.any<T>([
      work,
      abort.future.then<T>((_) => throw const _RequestCancelled()),
    ]);
    if (generation != _requestGeneration) throw const _RequestCancelled();
    return value;
  }

  Future<String> _runActions(List<FridayAction> actions, int generation) async {
    final outcomes = <String>[];
    for (final action in actions) {
      if (generation != _requestGeneration) throw const _RequestCancelled();
      final result = await _wait(router.executeAll([action]), generation);
      if (result.isNotEmpty) outcomes.add(result);
    }
    return outcomes.join('\n');
  }

  void _stopWork() {
    _abort?.complete();
    _abort = null;
    screenAgent?.stop();
    _stopping = brain.cancel().catchError((Object _) {});
  }

  /// True while a confirmed order is inside OroTradeExecutor (already handed
  /// to Sona). Cancel then only stops waiting - Sona's real result is still
  /// reported when it arrives, never a fake "cancelled".
  bool _tradeInFlight = false;

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
  bool voiceDraftActive = false;
  void beginVoiceDraft() {
    voiceDraftActive = true;
    partialHeard = '';
    notifyListeners();
  }

  void endVoiceDraft() {
    voiceDraftActive = false;
    partialHeard = '';
    notifyListeners();
  }

  final oroContext = OroContext();
  final priceSubjectContext = PriceSubjectContext();

  /// Stops the running request, if any. An order already handed to Sona
  /// cannot be unsent: then this only stops the wait, and Sona's real result
  /// is still reported when it arrives.
  void cancel() {
    if (!busy) return;
    unawaited(router.deviceHub.cancelMusicSearch());
    _requestGeneration++;
    if (_abort?.isCompleted == false) _stopWork();
    final inFlight = _tradeInFlight;
    final mayHaveActed = phase != 'Thinking' && phase != 'Checking Sona';
    _pendingTrade = null;
    _tradeDraft = null;
    _tradeDraftAt = null;
    _pendingAlert = null;
    messages.add(ChatMessage(
      id: '${DateTime.now().microsecondsSinceEpoch}cancel',
      role: MessageRole.friday,
      text: inFlight
          ? 'Stopped waiting. The order may already be with Sona. Its result will be reported if received; check Sona before retrying.'
          : mayHaveActed
              ? 'Cancelled. A phone action that already started may still have completed - check the screen before retrying.'
              : 'Cancelled. Nothing was done.',
      at: DateTime.now(),
    ));
    busy = false;
    phase = 'Ready';
    partialHeard = '';
    notifyListeners();
    unawaited(chatStore.save(messages));
    if (settings.speakReplies) unawaited(speech.speak('Cancelled'));
  }

  Future<void> _tradeReply(String text, {String? spoken, String? id}) async {
    final msg = ChatMessage(
      id: id ?? '${DateTime.now().microsecondsSinceEpoch}trade',
      role: MessageRole.friday,
      text: text,
      at: DateTime.now(),
    );
    messages.add(msg);
    busy = false;
    partialHeard = '';
    phase = 'Ready';
    notifyListeners();
    await chatStore.save(messages);
    if (settings.speakReplies) await speech.speak(spoken ?? text);
  }

  /// Returns true when [text] was a trade command or a reply to a pending
  /// trade confirmation and has been answered here.
  Future<bool> _handleTrade(String text, int generation) async {
    final now = DateTime.now();
    final pending = _pendingTrade;
    if (pending != null) {
      final reply = TradeFlow.classifyReply(text);
      if (pending.expired(now)) {
        _pendingTrade = null;
        if (reply != TradeReply.other) {
          await _tradeReply(
              'That trade confirmation expired after 2 minutes. No order was sent - say the trade again.',
              spoken: 'That confirmation expired. No order was sent.');
          return true;
        }
      } else if (reply == TradeReply.confirm) {
        _pendingTrade = null;
        oroContext.clear();
        phase = 'Sending to Sona';
        notifyListeners();
        _tradeInFlight = true;
        String result;
        try {
          result = await OroTradeExecutor(tradeDesk,
                  timeout: _tradeTimeout, poll: _tradePoll)
              .execute(pending);
        } finally {
          _tradeInFlight = false;
        }
        if (generation == _requestGeneration) {
          await _tradeReply(result, spoken: TradeFlow.spokenResult(result));
        } else {
          messages.add(ChatMessage(
              id: '${DateTime.now().microsecondsSinceEpoch}sonalate',
              role: MessageRole.friday,
              text: result,
              at: DateTime.now()));
          notifyListeners();
          await chatStore.save(messages);
        }
        return true;
      } else if (reply == TradeReply.cancel) {
        _pendingTrade = null;
        await _tradeReply('Cancelled. No order was sent to Sona.',
            spoken: 'Cancelled');
        return true;
      } else {
        // Anything else drops the confirmation; never keep an order armed
        // behind an unrelated request.
        _pendingTrade = null;
        messages.add(ChatMessage(
          id: '${DateTime.now().microsecondsSinceEpoch}tradedrop',
          role: MessageRole.friday,
          text: 'Dropped the pending trade confirmation. No order was sent.',
          at: DateTime.now(),
        ));
        notifyListeners();
      }
    }

    TradeCommand? command;
    final draft = _tradeDraft;
    if (draft != null) {
      _tradeDraft = null;
      final fresh = _tradeDraftAt != null &&
          now.difference(_tradeDraftAt!) <= PendingTrade.ttl;
      final size = fresh ? TradeCommandParser.parseSizeReply(text) : null;
      if (size != null) {
        if (size.error != null) {
          _tradeDraft = draft;
          _tradeDraftAt = now;
          await _tradeReply(size.error!);
          return true;
        }
        command = TradeCommand.open(
            side: draft.side, lots: size.lots!, tp: draft.tp, sl: draft.sl);
      } else if (fresh && TradeFlow.classifyReply(text) == TradeReply.cancel) {
        await _tradeReply('Okay, no trade.', spoken: 'Okay');
        return true;
      }
    }

    if (command == null) {
      final parsed = TradeCommandParser.parse(text);
      if (parsed == null) return false;
      // "buy gold" buys: no size said -> the Default trade size from
      // Settings, shown on the confirm card.
      final sized = parsed.withDefaultSize(settings.defaultTradeLots);
      if (sized != null) {
        command = sized;
      } else if (parsed.command == null) {
        _tradeDraft = parsed.draft;
        _tradeDraftAt = parsed.draft == null ? null : now;
        oroContext.clear();
        await _tradeReply(parsed.question!);
        return true;
      } else {
        command = parsed.command;
      }
    }
    oroContext.clear();
    phase = 'Checking Sona';
    notifyListeners();
    final support = await tradeDesk
        .support()
        .timeout(const Duration(seconds: 10), onTimeout: () => 'error');
    if (generation != _requestGeneration) return true;
    if (support != 'ok') {
      await _tradeReply(TradeFlow.supportAnswer(support));
      return true;
    }
    final snapshot = await tradeDesk
        .snapshot()
        .timeout(const Duration(seconds: 10), onTimeout: () => null);
    if (generation != _requestGeneration) return true;
    final plan = TradeFlow.plan(command!, snapshot,
        nowMs: DateTime.now().millisecondsSinceEpoch);
    if (!plan.ready) {
      await _tradeReply(plan.text);
      return true;
    }
    final id = '${DateTime.now().microsecondsSinceEpoch}tradeconfirm';
    _pendingTrade = PendingTrade(
      id: 'f${DateTime.now().microsecondsSinceEpoch}',
      command: command,
      targets: plan.targets,
      at: DateTime.now(),
      messageId: id,
    );
    await _tradeReply(plan.text, spoken: plan.spoken, id: id);
    return true;
  }

  Future<void> loadHistory() async {
    final saved = chatStore.load();
    if (saved.isNotEmpty) {
      messages.addAll(saved);
      notifyListeners();
    }
  }

  /// The gold alert waiting for Yes / Edit after a "Did you mean" question.
  PendingAlert? _pendingAlert;
  PendingAlert? get pendingAlert => _pendingAlert;

  /// Sona's latest saved gold price, when it is recent enough to tell which
  /// way an alert has to move. Null when Sona has no usable quote.
  Future<double?> _goldQuote() async {
    try {
      final s = await OroBridge(router.deviceHub)
          .read()
          .timeout(const Duration(seconds: 3));
      if (s == null) return null;
      return GoldTaskRequest.usableQuote(
          s.bid, s.ask, s.quoteAt, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      return null;
    }
  }

  Future<String> _createGoldAlert(
      GoldTaskRequest request, int generation) async {
    final current = await _wait(_goldQuote(), generation);
    final resolved = request.resolve(current);
    try {
      final native = await TaskService().create(resolved);
      return resolved.createdReply(native, currentPrice: current);
    } catch (_) {
      return 'Could not update background tasks. Open Background tasks to check their saved state.';
    }
  }

  Future<String> _cancelGoldAlerts() async {
    try {
      return await TaskService().cancelAll();
    } catch (_) {
      return 'Could not update background tasks. Open Background tasks to check their saved state.';
    }
  }

  Future<void> _goldReply(String reply, {String? id, String? spoken}) async {
    messages.add(
      ChatMessage(
        id: id ?? '${DateTime.now().microsecondsSinceEpoch}task',
        role: MessageRole.friday,
        text: reply,
        at: DateTime.now(),
      ),
    );
    busy = false;
    phase = 'Ready';
    notifyListeners();
    await chatStore.save(messages);
    if (settings.speakReplies)
      await speech.speak(spoken ?? conciseReply(reply));
  }

  /// Answers a Yes / No to a pending "Did you mean" gold alert. Returns
  /// true when [text] was that answer.
  Future<bool> _handleAlertGuess(String text, int generation) async {
    final pending = _pendingAlert;
    if (pending == null) return false;
    _pendingAlert = null;
    if (PendingAlert.isYes(text)) {
      oroContext.clear();
      final reply = await _wait(
          _createGoldAlert(pending.request, generation), generation);
      await _goldReply(reply);
      return true;
    }
    if (PendingAlert.isNo(text)) {
      await _goldReply(
          'Okay, no alert was set. Say it again, or tap your message to edit it.');
      return true;
    }
    return false;
  }

  /// Every send speaks its reply unless the user muted Friday in Settings.
  Future<void> send(String text) async {
    if (text.trim().isEmpty || busy || agentRunning?.call() == true) return;
    if (_tradeInFlight) return;
    await _stopping;
    if (busy) return;
    _abort = Completer<void>();
    final generation = ++_requestGeneration;
    try {
      await _send(text, generation).timeout(requestTimeout);
    } on _RequestCancelled {
      return;
    } on TimeoutException {
      if (generation != _requestGeneration) return;
      _requestGeneration++;
      if (_abort?.isCompleted == false) _stopWork();
      busy = false;
      phase = 'Ready';
      partialHeard = '';
      notifyListeners();
      messages.add(
        ChatMessage(
          id: '${DateTime.now().microsecondsSinceEpoch}timeout',
          role: MessageRole.friday,
          text:
              'This request timed out. Further steps were stopped. An action already handed to another app may still finish; check that app before retrying.',
          at: DateTime.now(),
        ),
      );
      try {
        await chatStore.save(messages);
      } catch (_) {}
      if (settings.speakReplies) {
        try {
          await speech.speak("Couldn't do it");
        } catch (_) {}
      }
    } catch (_) {
      if (generation != _requestGeneration) return;
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
      if (generation == _requestGeneration) {
        busy = false;
        phase = 'Ready';
        partialHeard = '';
        notifyListeners();
      }
    }
  }

  Future<void> _send(String text, int generation) async {
    final literalMessage = const OfflineEngine().handle(text);
    final isLiteralWhatsApp =
        literalMessage.action.type == FridayActionType.sendWhatsApp &&
            literalMessage.extraActions.isEmpty;
    final original =
        isLiteralWhatsApp ? text : text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (original.isEmpty || busy) return;
    final now = DateTime.now();
    final clean = priceSubjectContext.resolve(original, now) ??
        oroContext.resolve(original, now) ??
        original;
    // Context is one-turn and must be earned again by an observed result.
    priceSubjectContext.clear();

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
      final outcome = await _wait(
          _runActions([literalMessage.action], generation), generation);
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
      await _wait(chatStore.save(messages), generation);
      if (settings.speakReplies) await speech.speak(spokenActionReply(reply));
      return;
    }

    // Sona paper trades: confirmation first, never an ambiguous order.
    if (await _wait(_handleTrade(clean, generation), generation)) return;
    // Yes / No to a "Did you mean" gold alert.
    if (await _wait(_handleAlertGuess(clean, generation), generation)) return;

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
            : await _wait(link!.send(remoteText), generation);
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
        await _wait(chatStore.save(messages), generation);
        if (settings.speakReplies) await speech.speak(conciseReply(reply));
        return;
      }
    }
    final localText = remote == null ? clean : clean.substring(0, remote.start);
    // Simple reminders ("remind me to X at 9:42", "in 10 minutes") are read
    // with plain code and saved here, before any model is asked. The floating
    // bar sends through this same method, so it gets the same behaviour.
    final reminder = ReminderParser.parseForChat(localText, DateTime.now());
    if (reminder != null) {
      oroContext.clear();
      String reply;
      if (!reminder.ok) {
        reply = reminder.error!;
      } else {
        phase = 'Doing';
        notifyListeners();
        String outcome;
        try {
          outcome = await _wait(
              _runActions([reminder.toAction()], generation), generation);
        } on _RequestCancelled {
          rethrow;
        } catch (_) {
          outcome =
              'I could not schedule the reminder. Allow Friday notifications in Android app settings, then try again.';
        }
        reply = outcome.startsWith('Reminder registered for ')
            ? 'Reminder registered for ${ReminderParser.describe(reminder.when!)}: ${reminder.task}.'
            : (outcome.isEmpty
                ? 'I could not schedule the reminder.'
                : outcome);
      }
      // No panel auto-close here: the reply carries the task and exact time.
      messages.add(ChatMessage(
          id: '${DateTime.now().microsecondsSinceEpoch}reminder',
          role: MessageRole.friday,
          text: reply,
          at: DateTime.now(),
          localOnly: true));
      busy = false;
      phase = 'Ready';
      notifyListeners();
      await _wait(chatStore.save(messages), generation);
      if (settings.speakReplies) {
        await speech.speak(reply.startsWith('Reminder registered for ')
            ? 'Reminder set'
            : reply);
      }
      return;
    }
    final whatsappSearch = RegExp(
            r'^(?:please )?open whats\s*app(?: and)? search(?: for)? (.+?)[.!?]?$',
            caseSensitive: false)
        .firstMatch(localText);
    if (Platform.isAndroid && whatsappSearch != null) {
      final query = whatsappSearch[1]!.trim();
      String reply =
          'Friday v61: WhatsApp search needs screen-control access. No search run.';
      if (screenAgent != null && query.isNotEmpty && query.length <= 250) {
        await _wait(screenAgent!.start('open whatsapp and search for $query'),
            generation);
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
      await _wait(chatStore.save(messages), generation);
      if (settings.speakReplies) await speech.speak(reply);
      return;
    }
    if (Platform.isAndroid &&
        screenAgent != null &&
        RegExp(r'^play (?:the )?first video[.!?]?$', caseSensitive: false)
            .hasMatch(localText.trim())) {
      // Observe fresh underlying screen. Never infer a Gallery default or reuse
      // old search history; only a uniquely identified current YouTube query.
      await _wait(screenAgent!.start('read my screen'), generation);
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
            await _wait(screenAgent!.start(task), generation);
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
      await _wait(chatStore.save(messages), generation);
      if (settings.speakReplies) await speech.speak(reply);
      return;
    }
    if (Platform.isAndroid &&
        screenAgent != null &&
        AgentGoal.parse(localText) != null) {
      phase = 'Screen control';
      notifyListeners();
      await _wait(screenAgent!.start(localText), generation);
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
      await _wait(chatStore.save(messages), generation);
      if (settings.speakReplies)
        await speech.speak(privateScreen ? reply : spokenActionReply(reply));
      return;
    }
    final galleryIndex = GalleryCommand.parse(localText);
    if (galleryIndex != null) {
      final reply =
          await _wait(router.deviceHub.galleryVideo(galleryIndex), generation);
      messages.add(ChatMessage(
          id: '${DateTime.now().microsecondsSinceEpoch}gallery',
          role: MessageRole.friday,
          text: reply,
          at: DateTime.now(),
          localOnly: true));
      busy = false;
      phase = 'Ready';
      notifyListeners();
      await _wait(chatStore.save(messages), generation);
      if (settings.speakReplies) await speech.speak(reply);
      return;
    }
    final compound = CompoundCommand.parse(localText);
    if (compound != null && AgentGoal.parse(localText) == null) {
      // Do not pass the entire compound string to app-name matching, or let
      // a chat model invent unsupported execution of the remaining action.
      final opened = await _runActions(
          [FridayAction(type: FridayActionType.openApp, app: compound.app)],
          generation);
      if (generation != _requestGeneration) return;
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
      await _wait(chatStore.save(messages), generation);
      if (settings.speakReplies)
        await speech.speak(
            'That action is not supported yet. Check the app launch result.');
      return;
    }
    final directionQuestion = GoldTaskRequest.directionQuestion(clean);
    if (directionQuestion != null) {
      oroContext.clear();
      priceSubjectContext.remember('gold', DateTime.now());
      await _goldReply(directionQuestion);
      return;
    }
    final goldReading = GoldTaskRequest.read(clean);
    final goldTask =
        goldReading != null && goldReading.certain ? goldReading.request : null;
    final cancelGold = RegExp(
      r'^(?:cancel|stop) (?:all |my )?gold (?:alerts|tasks|checks)[.!]?$',
      caseSensitive: false,
    ).hasMatch(clean);
    if (goldTask != null || cancelGold) {
      oroContext.clear();
      final reply = goldTask != null
          ? await _wait(_createGoldAlert(goldTask, generation), generation)
          : await _wait(_cancelGoldAlerts(), generation);
      if (generation != _requestGeneration) return;
      await _goldReply(reply);
      return;
    }
    // A gold alert Friday could only read with a sound-alike guess (or an
    // interval the phone cannot run): ask, never refuse and never guess.
    if (goldReading != null) {
      oroContext.clear();
      final id = '${DateTime.now().microsecondsSinceEpoch}alertguess';
      _pendingAlert = PendingAlert(id, goldReading.request);
      await _goldReply(
        'Did you mean: ${goldReading.request.readable}? Tap Yes to set it, or Edit to fix it.',
        id: id,
        spoken:
            'Did you mean, ${goldReading.request.readable}? Say yes to set it.',
      );
      return;
    }
    if (GoldTaskRequest.isAssetlessAlert(clean)) {
      oroContext.clear();
      await _goldReply(
        'Which one should I watch? Friday can watch gold, for example: "alert me when gold goes above 4000".',
      );
      return;
    }

    final response = await _wait(
        brain.ask(localText, history: List.of(messages)), generation);

    // Cancelled while the model thought: never run the actions its late
    // answer asked for, and never show the answer.
    if (generation != _requestGeneration) return;

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
      reply = await _wait(_runActions(actions, generation), generation);
      if (reply.isEmpty) reply = "I couldn't read Sona's saved data.";
      if (actions.length == 1 &&
          actions.single.type == FridayActionType.oroStatus &&
          (actions.single.target.isEmpty || actions.single.target == 'price') &&
          reply.startsWith('Gold is at ')) {
        priceSubjectContext.remember('gold', DateTime.now());
      }
    } else if (actions.isNotEmpty) {
      oroContext.clear();
      // One final result, not a second acknowledgement bubble.
      phase = 'Doing';
      notifyListeners();
      final outcome = await _wait(_runActions(actions, generation), generation);
      // The router's outcome is the truth - the brain's reply only guessed
      // at the result ("Reminder set" before it was).
      _commandFinished(outcome);
      reply = actionResultReply(outcome);
    }

    if (!infoOnly && actions.isEmpty) oroContext.clear();
    // A cancelled request drops the late model answer; the Cancel message
    // already told the user nothing was done.
    if (generation != _requestGeneration) return;
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

    await _wait(chatStore.save(messages), generation);
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

class _RequestCancelled implements Exception {
  const _RequestCancelled();
}
