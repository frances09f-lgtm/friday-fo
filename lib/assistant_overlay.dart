/// The Gemini-style assistant panel: a small bar over whatever app is open,
/// shown when Friday is invoked as the phone's digital assistant (long-press
/// power). Talk or type here; the full app opens only if the user asks.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'friday_services.dart';
import 'models/chat_message.dart';
import 'services/speech/speech_service.dart';
import 'state/friday_controller.dart';

@pragma('vm:entry-point')
Future<void> assistantOverlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await createFridayServices(loadHistory: false);
  runApp(
    MultiProvider(
      providers: services.providers,
      child: const AssistantOverlayApp(),
    ),
  );
}

class AssistantOverlayApp extends StatelessWidget {
  const AssistantOverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Friday',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          useMaterial3: true, colorScheme: scheme, brightness: Brightness.dark),
      home: const AssistantPanel(),
    );
  }
}

class AssistantPanel extends StatefulWidget {
  const AssistantPanel({super.key});

  @override
  State<AssistantPanel> createState() => _AssistantPanelState();
}

class _AssistantPanelState extends State<AssistantPanel> {
  static const _channel = MethodChannel('friday/assistant');
  final _input = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Ready for input the moment it appears; start listening when the mic
    // is usable, fall back to a focused text field when it is not.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final speech = context.read<SpeechService>();
      try {
        if (await speech.initSpeech()) {
          _startListening(speech);
          return;
        }
      } catch (_) {}
      _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startListening(SpeechService speech) {
    final controller = context.read<FridayController>();
    speech.startListening(
      onResult: (t) => controller.setPartialHeard(t),
      onDone: () {
        final text = controller.partialHeard;
        if (text.trim().isNotEmpty) controller.send(text);
      },
    );
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    context.read<FridayController>().send(text);
  }

  Future<void> _dismiss() async {
    try {
      await _channel.invokeMethod<void>('dismiss');
    } catch (_) {}
  }

  Future<void> _openFullApp() async {
    try {
      await _channel.invokeMethod<void>('openFriday');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FridayController>();
    final speech = context.watch<SpeechService>();
    final recent = controller.messages.length <= 6
        ? controller.messages
        : controller.messages.sublist(controller.messages.length - 6);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const SizedBox(width: 16),
                Text('Friday',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.open_in_full, size: 20),
                  tooltip: 'Open Friday',
                  onPressed: _openFullApp,
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Close',
                  onPressed: _dismiss,
                ),
              ]),
              if (recent.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: recent.length,
                    itemBuilder: (_, i) {
                      final m = recent[i];
                      final isUser = m.role == MessageRole.user;
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isUser
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(m.text,
                              style: const TextStyle(fontSize: 13)),
                        ),
                      );
                    },
                  ),
                ),
              if (controller.partialHeard.isNotEmpty)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(controller.partialHeard,
                        style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.outline,
                            fontStyle: FontStyle.italic)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Row(children: [
                  IconButton(
                    icon: Icon(speech.isListening ? Icons.mic : Icons.mic_none),
                    onPressed: () {
                      if (speech.isListening) {
                        speech.stopListening();
                      } else {
                        _startListening(speech);
                      }
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Ask Friday...',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  if (controller.busy)
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else
                    IconButton(
                        icon: const Icon(Icons.send), onPressed: _send),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
