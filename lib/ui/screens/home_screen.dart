import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/speech/speech_service.dart';
import '../../state/friday_controller.dart';
import '../widgets/chat_bubble.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _speechReady = false;

  @override
  void initState() {
    super.initState();
    context.read<SpeechService>().initSpeech().then((ok) {
      if (mounted) setState(() => _speechReady = ok);
    });
  }

  void _send() {
    final controller = context.read<FridayController>();
    final text = _input.text;
    _input.clear();
    controller.send(text).then((_) => _scrollDown());
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toggleMic() {
    final speech = context.read<SpeechService>();
    final controller = context.read<FridayController>();
    if (speech.isListening) {
      speech.stopListening();
    } else {
      speech.startListening(
        onResult: (t) => controller.setPartialHeard(t),
        onDone: () {
          final text = controller.partialHeard;
          if (text.trim().isNotEmpty) {
            controller.send(text).then((_) => _scrollDown());
          }
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FridayController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friday'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: controller.messages.isEmpty
                ? _EmptyState(onSuggestion: (s) {
                    _input.text = s;
                    _send();
                  })
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: controller.messages.length,
                    itemBuilder: (context, i) {
                      final m = controller.messages[i];
                      return ChatBubble(
                        message: m,
                        source: m.source,
                      );
                    },
                  ),
          ),
          if (controller.partialHeard.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${controller.partialHeard}...',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Ask Friday anything, or say what to do',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                if (_speechReady)
                  IconButton(
                    icon: Icon(
                      Icons.mic,
                      color: context.read<FridayController>().partialHeard.isNotEmpty
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    tooltip: 'Push to talk',
                    onPressed: _toggleMic,
                  ),
                IconButton(
                  icon: const Icon(Icons.send),
                  tooltip: 'Send',
                  onPressed: controller.busy ? null : _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onSuggestion});

  final void Function(String) onSuggestion;

  static const _suggestions = [
    'Open WhatsApp',
    'Read my messages',
    'Remind me to stretch in 30 minutes',
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Hi, I am Friday.',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Ask me anything. I run on your API key first,\nthen the on-device model, then pure offline.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            children: [
              for (final s in _suggestions)
                OutlinedButton(onPressed: () => onSuggestion(s), child: Text(s)),
            ],
          ),
        ],
      ),
    );
  }
}
