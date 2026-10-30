import '../stitch_style.dart';
import '../friday_motion.dart';
import 'immersive_voice_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/speech/speech_service.dart';
import '../../state/friday_controller.dart';
import '../widgets/chat_bubble.dart';
import '../../models/chat_message.dart';
import '../../services/agent/friday_agent.dart';
import 'agent_mode_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.showHeader = true, this.sessionOnly = false});
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
  bool _followBottom = true;
  String _messageRevision = '';
  @override
  void dispose() { _input.dispose(); _scroll.dispose(); _inputFocus.dispose(); super.dispose(); }
  @override
  void initState() {
    super.initState();
    if (widget.sessionOnly) _olderMessageIds.addAll(context.read<FridayController>().messages.map((m) => m.id));
    _scroll.addListener(() { if (_scroll.hasClients) _followBottom = _scroll.position.extentBefore < 80; });
    context.read<SpeechService>().initSpeech().then((ok) { if (mounted) setState(() => _speechReady = ok); });
  }
  void _send() {
    final controller = context.read<FridayController>();
    final text = _input.text; _input.clear(); controller.send(text);
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
      if (mounted && _scroll.hasClients && _followBottom) _scroll.jumpTo(_scroll.position.minScrollExtent);
    });
  }
  void _toggleMic() {
    final speech = context.read<SpeechService>();
    final controller = context.read<FridayController>();
    if (speech.isListening) { speech.stopListening(); setState(() {}); }
    else {
      speech.startListening(onResult: (t) => controller.setPartialHeard(t), onDone: () {
        final err = speech.lastSttError;
        final text = controller.partialHeard;
        if (mounted) {
          setState(() {});
          if (err != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
        }
        if (text.trim().isNotEmpty) controller.send(text);
      });
      setState(() {});
    }
  }
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FridayController>();
    final agent = context.watch<FridayAgent?>();
    final visibleMessages = widget.sessionOnly ? controller.messages.where((m) => !_olderMessageIds.contains(m.id)).toList() : controller.messages;
    final revision = visibleMessages.map((m) => '${m.id}:${m.text}:${m.source}').join('\u0000');
    if (revision != _messageRevision) { _messageRevision = revision; if (_followBottom) _scrollDown(); }
    return Scaffold(
      appBar: widget.showHeader ? StitchHeader(title: 'Conversation', back: true,
        onVoice: () => Navigator.push(context, MotionRoute(builder: (_) => const ImmersiveVoiceScreen())),
        onSettings: () => Navigator.pushNamed(context, '/settings')) : null,
      body: Column(children: [
        if (agent?.running == true)
          MotionPress(child: ListTile(title: Text(agent!.phase), subtitle: Text('Step ${agent.steps}/${agent.maxSteps} · ${agent.currentApp}'),
            trailing: MotionPress(child: TextButton(onPressed: agent.stop, child: const Text('STOP'))),
            onTap: () => Navigator.push(context, MotionRoute(builder: (_) => const AgentModeScreen())))),
        Expanded(child: visibleMessages.isEmpty
          ? widget.sessionOnly ? const Center(child: Text('Your current session appears here.'))
            : _EmptyState(onSuggestion: (s) { _input.text = s; _send(); })
          : ListView.builder(controller: _scroll, reverse: true,
            padding: const EdgeInsets.symmetric(vertical: 8), itemCount: visibleMessages.length,
            findChildIndexCallback: (key) {
              if (key is! ValueKey<String>) return null;
              final i = visibleMessages.indexWhere((m) => m.id == key.value);
              return i < 0 ? null : visibleMessages.length - 1 - i;
            },
            itemBuilder: (context, i) {
              final m = visibleMessages[visibleMessages.length - 1 - i];
              return MotionEntrance(key: ValueKey(m.id), index: i, scale: .88,
                child: GestureDetector(
                  // Tap what you said (or what Friday heard) to fix it and send again.
                  onTap: m.role == MessageRole.user ? () => _edit(m.text) : null,
                  child: ChatBubble(message: m, source: m.source,
                  actions: controller.pendingTrade?.messageId == m.id ? TradeConfirmButtons(
                    busy: controller.busy,
                    onConfirm: () => controller.send('Confirm'),
                    onCancel: () => controller.send('Cancel'))
                    : controller.pendingAlert?.messageId == m.id ? AlertGuessButtons(
                    busy: controller.busy,
                    onYes: () => controller.send('Yes'),
                    onEdit: () => _edit(controller.pendingAlert!.request.canonical)) : null)));
            })),
        if (controller.partialHeard.isNotEmpty)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Align(alignment: Alignment.centerLeft,
            child: Text('${controller.partialHeard}...', style: Theme.of(context).textTheme.bodySmall))),
        Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: StitchCard(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: SafeArea(top: false,
            child: Row(children: [
              Expanded(child: Padding(padding: const EdgeInsets.only(left: 12), child: TextField(controller: _input, focusNode: _inputFocus,
                textInputAction: TextInputAction.send, onSubmitted: (_) => _send(),
                decoration: const InputDecoration(hintText: 'Ask or instruct Friday...', border: InputBorder.none)))),
              if (_speechReady) MotionPress(scale: .88, child: IconButton(icon: Icon(Icons.mic,
                color: context.read<SpeechService>().isListening || context.read<FridayController>().partialHeard.isNotEmpty ? Theme.of(context).colorScheme.primary : null),
                tooltip: 'Push to talk', onPressed: _toggleMic)),
              MotionPress(scale: .88, enabled: !controller.busy, child: IconButton(icon: const Icon(Icons.send), tooltip: 'Send', onPressed: controller.busy ? null : _send))
            ]))))
      ]));
  }
}
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onSuggestion});
  final void Function(String) onSuggestion;
  static const _suggestions = ['Open WhatsApp','Read my messages','Remind me to stretch in 30 minutes'];
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Text('Start a conversation', style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 8),
    Text('Ask a question or tell Friday what to do.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 24),
    Wrap(spacing: 8, children: [for (final s in _suggestions) MotionPress(scale: .93, child: OutlinedButton(onPressed: () => onSuggestion(s), child: Text(s)))])
  ]));
}

/// Confirm / Cancel under a pending Sona paper-trade confirmation.
class TradeConfirmButtons extends StatelessWidget {
  const TradeConfirmButtons({super.key, required this.onConfirm, required this.onCancel, this.busy = false});
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool busy;
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: FilledButton.icon(key: const ValueKey('trade-confirm'), onPressed: busy ? null : onConfirm,
      icon: const Icon(Icons.check, size: 18), label: const Text('Confirm'))),
    const SizedBox(width: 10),
    Expanded(child: OutlinedButton.icon(key: const ValueKey('trade-cancel'), onPressed: busy ? null : onCancel,
      icon: const Icon(Icons.close, size: 18), label: const Text('Cancel'))),
  ]);
}

/// Yes / Edit under a "Did you mean ...?" gold alert.
class AlertGuessButtons extends StatelessWidget {
  const AlertGuessButtons({super.key, required this.onYes, required this.onEdit, this.busy = false});
  final VoidCallback onYes;
  final VoidCallback onEdit;
  final bool busy;
  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
    MotionPress(scale: .93, enabled: !busy, child: FilledButton.icon(onPressed: busy ? null : onYes,
      icon: const Icon(Icons.check, size: 18), label: const Text('Yes'))),
    MotionPress(scale: .93, child: OutlinedButton.icon(onPressed: onEdit,
      icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Edit'))),
  ]);
}
