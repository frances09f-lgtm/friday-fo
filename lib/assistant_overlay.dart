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
  bool? _expanded;

  @override
  void initState() {
    super.initState();
    // Ready for input the moment it appears; start listening when the mic
    // is usable, fall back to a focused text field when it is not.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final speech = context.read<SpeechService>();
      try {
        final mode =
            await _channel.invokeMapMethod<String, dynamic>('launchMode');
        if (mode?['voice'] == true && await speech.initSpeech()) {
          _startListening(speech);
          return;
        }
      } catch (_) {}
      // Keyboard opens only when the input is tapped, not on assistant launch.
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
    await context.read<SpeechService>().stopListening();
    try {
      await _channel.invokeMethod<void>('dismiss');
    } catch (_) {}
  }

  Future<void> _openFullApp() async {
    await context.read<SpeechService>().stopListening();
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
    final expanded = recent.isNotEmpty || controller.partialHeard.isNotEmpty;
    if (_expanded != expanded) {
      _expanded = expanded;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) {
          try {
            await _channel
                .invokeMethod('panelExpanded', {'expanded': expanded});
          } catch (_) {}
        }
      });
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Align(
          alignment: Alignment.bottomCenter,
          child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 24, end: 0),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) =>
                  Transform.translate(offset: Offset(0, value), child: child),
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xff242328),
                      border: Border.all(color: const Color(0xff44434b)),
                      borderRadius: BorderRadius.circular(32),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                              onVerticalDragEnd: (d) {
                                if ((d.primaryVelocity ?? 0) < -200)
                                  _openFullApp();
                              },
                              child: Padding(
                                  padding:
                                      const EdgeInsets.only(top: 10, bottom: 4),
                                  child: Container(
                                      width: 30,
                                      height: 3,
                                      decoration: BoxDecoration(
                                          color: Colors.white24,
                                          borderRadius:
                                              BorderRadius.circular(3))))),
                          if (recent.isNotEmpty)
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 180),
                              child: ListView.builder(
                                shrinkWrap: true,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: recent.length,
                                itemBuilder: (_, i) {
                                  final m = recent[i];
                                  final isUser = m.role == MessageRole.user;
                                  return Align(
                                    alignment: isUser
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 2),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isUser
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primaryContainer
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(controller.partialHeard,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline,
                                        fontStyle: FontStyle.italic)),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(6, 0, 8, 12),
                            child: Row(children: [
                              PopupMenuButton<String>(
                                  tooltip: 'Friday controls',
                                  icon: const Icon(Icons.add, size: 26),
                                  onSelected: (value) async {
                                    if (value == 'open')
                                      await _openFullApp();
                                    else if (value == 'close')
                                      await _dismiss();
                                    else {
                                      await speech.stopListening();
                                      try {
                                        await _channel
                                            .invokeMethod('hideBubble');
                                      } catch (_) {}
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                        PopupMenuItem(
                                            value: 'open',
                                            child: Text('Open Friday')),
                                        PopupMenuItem(
                                            value: 'close',
                                            child: Text('Close panel')),
                                        PopupMenuItem(
                                            value: 'hide',
                                            child:
                                                Text('Hide floating assistant'))
                                      ]),
                              Expanded(
                                child: TextField(
                                  controller: _input,
                                  focusNode: _focus,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _send(),
                                  decoration: const InputDecoration(
                                    hintText: 'Ask Friday...',
                                    hintStyle: const TextStyle(
                                        fontSize: 18, color: Color(0xffd7d5df)),
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                              IconButton(
                                  tooltip: speech.isListening
                                      ? 'Stop listening'
                                      : 'Talk to Friday',
                                  style: IconButton.styleFrom(
                                      backgroundColor: const Color(0xff33466c)),
                                  icon: Icon(speech.isListening
                                      ? Icons.mic
                                      : Icons.mic_none),
                                  onPressed: () async {
                                    if (speech.isListening) {
                                      await speech.stopListening();
                                    } else if (await speech.initSpeech() &&
                                        mounted) {
                                      _startListening(speech);
                                    }
                                  }),
                              if (controller.busy)
                                const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2)),
                                )
                              else
                                IconButton(
                                    icon: const Icon(Icons.send),
                                    onPressed: _send),
                            ]),
                          ),
                        ],
                      ),
                    ),
                  )))),
    );
  }
}
