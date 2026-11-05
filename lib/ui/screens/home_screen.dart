import 'dart:async';
import '../stitch_style.dart';
import '../friday_motion.dart';
import 'immersive_voice_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/speech/speech_service.dart';
import '../../state/friday_controller.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/listening_bubble.dart';
import '../../models/chat_message.dart';
import '../../services/agent/friday_agent.dart';
import 'agent_mode_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen(
      {super.key, this.showHeader = true, this.sessionOnly = false});
  final bool showHeader;
  final bool sessionOnly;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _input = TextEditingController();
  // The latest message remains the layout anchor, including during animation.
  final _scroll = ScrollController(keepScrollOffset: false);
  final Set<String> _olderMessageIds = {};
  bool _speechReady = false;
  int _listenGeneration = 0;
  late final SpeechService _speech;
  late final FridayController _controller;
  bool _followBottom = true;
  String _messageRevision = '';
  @override
  void dispose() {
    _listenGeneration++;
    unawaited(_speech.stopListening());
    _controller.voiceDraftActive = false;
    _controller.partialHeard = '';
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _speech = context.read<SpeechService>();
    _controller = context.read<FridayController>();
    if (widget.sessionOnly)
      _olderMessageIds
          .addAll(context.read<FridayController>().messages.map((m) => m.id));
    _scroll.addListener(() {
      if (_scroll.hasClients)
        _followBottom = _scroll.position.extentBefore < 80;
    });
    context.read<SpeechService>().initSpeech().then((ok) {
      if (mounted) setState(() => _speechReady = ok);
    });
  }

  void _send() {
    final controller = context.read<FridayController>();
    _listenGeneration++;
    controller.endVoiceDraft();
    unawaited(_speech.stopListening());
    final text = _input.text;
    _input.clear();
    controller.send(text);
  }

  final _inputFocus = FocusNode();

  /// Puts [text] in the box to fix and send again.
  void _edit(String text) {
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
    _inputFocus.requestFocus();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients && _followBottom)
        _scroll.jumpTo(_scroll.position.minScrollExtent);
    });
  }

  void _toggleMic() {
    final speech = _speech;
    final controller = _controller;
    if (controller.voiceDraftActive || _speech.isListening) {
      _listenGeneration++;
      controller.endVoiceDraft();
      unawaited(speech.stopListening());
      return;
    }
    if (controller.busy) return;
    final generation = ++_listenGeneration;
    controller.beginVoiceDraft();
    speech.startListening(onResult: (text) {
      if (mounted && generation == _listenGeneration)
        controller.setPartialHeard(text);
    }, onDone: () {
      if (!mounted || generation != _listenGeneration) return;
      _listenGeneration++;
      final err = speech.lastSttError;
      final text = controller.partialHeard;
      controller.endVoiceDraft();
      if (err != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
      } else if (text.trim().isNotEmpty) {
        controller.send(text);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FridayController>();
    final agent = context.watch<FridayAgent?>();
    final visibleMessages = widget.sessionOnly
        ? controller.messages
            .where((m) => !_olderMessageIds.contains(m.id))
            .toList()
        : controller.messages;
    final revision =
        '${controller.voiceDraftActive}:${controller.partialHeard}:' +
            visibleMessages
                .map((m) => '${m.id}:${m.text}:${m.source}')
                .join('\u0000');
    if (revision != _messageRevision) {
      _messageRevision = revision;
      if (_followBottom) _scrollDown();
    }
    return Scaffold(
        appBar: widget.showHeader
            ? StitchHeader(
                title: 'Conversation',
                back: true,
                onVoice: () => Navigator.push(context,
                    MotionRoute(builder: (_) => const ImmersiveVoiceScreen())),
                onSettings: () => Navigator.pushNamed(context, '/settings'))
            : null,
        body: Column(children: [
          if (agent?.running == true)
            MotionPress(
                child: ListTile(
                    title: Text(agent!.phase),
                    subtitle: Text(
                        'Step ${agent.steps}/${agent.maxSteps} · ${agent.currentApp}'),
                    trailing: MotionPress(
                        child: TextButton(
                            onPressed: agent.stop, child: const Text('STOP'))),
                    onTap: () => Navigator.push(context,
                        MotionRoute(builder: (_) => const AgentModeScreen())))),
          Expanded(
              child: visibleMessages.isEmpty && !controller.voiceDraftActive
                  ? widget.sessionOnly
                      ? const Center(
                          child: Text('Your current session appears here.'))
                      : _EmptyState(onSuggestion: (s) {
                          _input.text = s;
                          _send();
                        })
                  : ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: visibleMessages.length +
                          (controller.voiceDraftActive ? 1 : 0),
                      findChildIndexCallback: (key) {
                        if (key is! ValueKey<String>) return null;
                        final i = visibleMessages
                            .indexWhere((m) => m.id == key.value);
                        return i < 0
                            ? null
                            : visibleMessages.length -
                                1 -
                                i +
                                (controller.voiceDraftActive ? 1 : 0);
                      },
                      itemBuilder: (context, i) {
                        if (controller.voiceDraftActive && i == 0)
                          return ListeningBubble(text: controller.partialHeard);
                        final offset = controller.voiceDraftActive ? 1 : 0;
                        final m = visibleMessages[
                            visibleMessages.length - 1 - (i - offset)];
                        return MotionEntrance(
                            key: ValueKey(m.id),
                            index: i,
                            scale: .88,
                            child: GestureDetector(
                                // Tap what you said (or what Friday heard) to fix it and send again.
                                onTap: m.role == MessageRole.user
                                    ? () => _edit(m.text)
                                    : null,
                                child: ChatBubble(
                                    message: m,
                                    source: m.source,
                                    actions: controller
                                                .pendingTrade?.messageId ==
                                            m.id
                                        ? TradeConfirmButtons(
                                            busy: controller.busy,
                                            onConfirm: () =>
                                                controller.send('Confirm'),
                                            onCancel: () =>
                                                controller.send('Cancel'))
                                        : controller.pendingAlert?.messageId ==
                                                m.id
                                            ? AlertGuessButtons(
                                                busy: controller.busy,
                                                onYes: () =>
                                                    controller.send('Yes'),
                                                onEdit: () => _edit(controller
                                                    .pendingAlert!
                                                    .request
                                                    .canonical))
                                            : null)));
                      })),
          if (controller.busy)
            Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Row(children: [
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text('${controller.phase}...',
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis)),
                  TextButton.icon(
                      key: const ValueKey('request-cancel'),
                      onPressed: controller.cancel,
                      icon: const Icon(Icons.stop, size: 18),
                      label: const Text('Cancel')),
                ])),
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: StitchCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: SafeArea(
                      top: false,
                      child: Row(children: [
                        Expanded(
                            child: Padding(
                                padding: const EdgeInsets.only(left: 12),
                                child: TextField(
                                    controller: _input,
                                    focusNode: _inputFocus,
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: (_) => _send(),
                                    decoration: const InputDecoration(
                                        hintText: 'Ask or instruct Friday...',
                                        border: InputBorder.none)))),
                        if (_speechReady)
                          MotionPress(
                              scale: .88,
                              child: IconButton(
                                  icon: Icon(Icons.mic,
                                      color: controller.voiceDraftActive ||
                                              _speech.isListening
                                          ? Stitch.cyan
                                          : null),
                                  tooltip: controller.voiceDraftActive
                                      ? 'Cancel listening'
                                      : 'Push to talk',
                                  onPressed: _toggleMic)),
                        MotionPress(
                            scale: .88,
                            enabled: !controller.busy,
                            child: IconButton(
                                icon: const Icon(Icons.send),
                                tooltip: 'Send',
                                onPressed: controller.busy ? null : _send))
                      ]))))
        ]));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onSuggestion});
  final void Function(String) onSuggestion;
  static const _suggestions = [
    'Open WhatsApp',
    'Read my messages',
    'Remind me to stretch in 30 minutes'
  ];
  @override
  Widget build(BuildContext context) => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('Start a conversation',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('Ask a question or tell Friday what to do.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 24),
        Wrap(spacing: 8, children: [
          for (final s in _suggestions)
            MotionPress(
                scale: .93,
                child: OutlinedButton(
                    onPressed: () => onSuggestion(s), child: Text(s)))
        ])
      ]));
}

/// Confirm / Cancel under a pending Sona paper-trade confirmation.
class TradeConfirmButtons extends StatelessWidget {
  const TradeConfirmButtons(
      {super.key,
      required this.onConfirm,
      required this.onCancel,
      this.busy = false});
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool busy;
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: FilledButton.icon(
                key: const ValueKey('trade-confirm'),
                onPressed: busy ? null : onConfirm,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Confirm'))),
        const SizedBox(width: 10),
        Expanded(
            child: OutlinedButton.icon(
                key: const ValueKey('trade-cancel'),
                onPressed: busy ? null : onCancel,
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Cancel'))),
      ]);
}

/// Yes / Edit under a "Did you mean ...?" gold alert.
class AlertGuessButtons extends StatelessWidget {
  const AlertGuessButtons(
      {super.key,
      required this.onYes,
      required this.onEdit,
      this.busy = false});
  final VoidCallback onYes;
  final VoidCallback onEdit;
  final bool busy;
  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 8, runSpacing: 8, children: [
        MotionPress(
            scale: .93,
            enabled: !busy,
            child: FilledButton.icon(
                onPressed: busy ? null : onYes,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Yes'))),
        MotionPress(
            scale: .93,
            child: OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'))),
      ]);
}
