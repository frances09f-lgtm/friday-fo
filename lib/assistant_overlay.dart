/// The Gemini-style assistant panel: a small bar over whatever app is open,
/// shown when Friday is invoked as the phone's digital assistant (long-press
/// power). Talk or type here; the full app opens only if the user asks.
library;

import 'dart:math' as math;
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
        useMaterial3: true,
        colorScheme: scheme,
        brightness: Brightness.dark,
      ),
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
  bool _sending = false;
  bool _closeRequested = false;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'outsideTap') await _dismiss();
    });
    // Ready for input the moment it appears; start listening when the mic
    // is usable, fall back to a focused text field when it is not.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final speech = context.read<SpeechService>();
      try {
        final mode = await _channel.invokeMapMethod<String, dynamic>(
          'launchMode',
        );
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
    _channel.setMethodCallHandler(null);
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
        if (text.trim().isNotEmpty) _submit(text);
      },
    );
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    _submit(text);
  }

  Future<void> _submit(String text) async {
    final controller = context.read<FridayController>();
    if (_sending || controller.busy) return;
    final before = controller.messages.length;
    _sending = true;
    try {
      // Recognition/audio teardown must settle before Android volume writes.
      await context.read<SpeechService>().stopListening();
      await controller.send(text);
      // Give the finished response a short reading window. Failed requests and
      // questions also end this invocation; this never claims task success.
      if (mounted && controller.messages.length > before) {
        final volumeCommand = RegExp(
          r'\bvolume\b|\blouder\b|\bquieter\b',
          caseSensitive: false,
        ).hasMatch(text);
        // Leave measured volume evidence on screen for a screenshot/retry.
        if (volumeCommand && !_closeRequested) {
          _sending = false;
          return;
        }
        if (!_closeRequested)
          await Future<void>.delayed(const Duration(milliseconds: 1500));
        if (mounted) {
          _sending = false;
          await _dismiss();
        }
      }
    } finally {
      _sending = false;
      if (mounted && _closeRequested) {
        try {
          await _channel.invokeMethod<void>('dismiss');
        } catch (_) {}
      }
    }
  }

  Future<void> _dismiss() async {
    final controller = context.read<FridayController>();
    final speech = context.read<SpeechService>();
    setState(() => _closeRequested = true);
    _focus.unfocus();
    // Remove the window before waiting for speech or an in-flight request.
    try {
      await _channel.invokeMethod('hidePanelWhileBusy');
    } catch (_) {}
    if (_sending || controller.busy) {
      await speech.stopListening();
      return;
    }
    await speech.stopListening();
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
            await _channel.invokeMethod('panelExpanded', {
              'expanded': expanded,
            });
          } catch (_) {}
        }
      });
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _dismiss,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 24, end: 0),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) =>
                Transform.translate(offset: Offset(0, value), child: child),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: GestureDetector(
                onTap: () {},
                child: FridayGlowFrame(
                  active: speech.isListening || controller.busy,
                  enabled: !_closeRequested,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xff252334), Color(0xff15151e)],
                      ),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 4, 4, 0),
                            child: Row(children: [
                              Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(colors: [
                                        Color(0xffa7c9ff),
                                        Color(0xffb795ff)
                                      ]))),
                              const SizedBox(width: 8),
                              const Text('FRIDAY',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 2,
                                      color: Color(0xffddd3ff))),
                              const Spacer(),
                              IconButton(
                                  tooltip: 'Close Friday',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.close, size: 19),
                                  onPressed: _dismiss),
                            ]),
                          ),
                          if (recent.isNotEmpty)
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 180),
                              child: ListView.builder(
                                shrinkWrap: true,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
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
                                        vertical: 2,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
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
                                      child: Text(
                                        m.text,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          if (controller.partialHeard.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  controller.partialHeard,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color:
                                        Theme.of(context).colorScheme.outline,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(6, 0, 8, 12),
                            child: Row(
                              children: [
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
                                      child: Text('Open Friday'),
                                    ),
                                    PopupMenuItem(
                                      value: 'close',
                                      child: Text('Close panel'),
                                    ),
                                    PopupMenuItem(
                                      value: 'hide',
                                      child: Text('Hide floating assistant'),
                                    ),
                                  ],
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _input,
                                    focusNode: _focus,
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: (_) => _send(),
                                    decoration: const InputDecoration(
                                      hintText: 'Ask Friday...',
                                      hintStyle: const TextStyle(
                                        fontSize: 16,
                                        color: Color(0xffd7d5df),
                                      ),
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: speech.isListening
                                      ? 'Stop listening'
                                      : 'Talk to Friday',
                                  style: IconButton.styleFrom(
                                    backgroundColor: const Color(0xff33466c),
                                  ),
                                  icon: Icon(
                                    speech.isListening
                                        ? Icons.mic
                                        : Icons.mic_none,
                                  ),
                                  onPressed: () async {
                                    if (speech.isListening) {
                                      await speech.stopListening();
                                    } else if (await speech.initSpeech() &&
                                        mounted) {
                                      _startListening(speech);
                                    }
                                  },
                                ),
                                if (controller.busy)
                                  const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                else
                                  IconButton(
                                    icon: const Icon(Icons.send),
                                    onPressed: _send,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Border-only repaint: no animation-driven rebuilding of chat/input widgets.
class FridayGlowFrame extends StatefulWidget {
  final Widget child;
  final bool active;
  final bool enabled;
  const FridayGlowFrame(
      {super.key,
      required this.child,
      this.active = false,
      this.enabled = true});
  @override
  State<FridayGlowFrame> createState() => _FridayGlowFrameState();
}

class _FridayGlowFrameState extends State<FridayGlowFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController glow;
  @override
  void initState() {
    super.initState();
    glow =
        AnimationController(vsync: this, duration: const Duration(seconds: 6))
          ..repeat();
  }

  @override
  void didUpdateWidget(covariant FridayGlowFrame old) {
    super.didUpdateWidget(old);
    if (!widget.enabled) {
      glow.stop();
    } else if (!MediaQuery.disableAnimationsOf(context) && !glow.isAnimating) {
      glow.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.enabled || MediaQuery.disableAnimationsOf(context)) {
      glow.stop();
    } else if (!glow.isAnimating) {
      glow.repeat();
    }
  }

  @override
  void dispose() {
    glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
          child: CustomPaint(
        painter: _GlowPainter(glow, widget.active),
        child: Padding(padding: const EdgeInsets.all(3), child: widget.child),
      ));
}

class _GlowPainter extends CustomPainter {
  final Animation<double> phase;
  final bool active;
  _GlowPainter(this.phase, this.active) : super(repaint: phase);
  static const colors = [
    Color(0xff50dfff),
    Color(0xff708bff),
    Color(0xffae68ff),
    Color(0xffff63c4),
    Color(0xffffac77),
    Color(0xff50dfff)
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2);
    final edge = RRect.fromRectAndRadius(rect, const Radius.circular(29));
    final shader = SweepGradient(
            colors: colors,
            transform: GradientRotation(phase.value * math.pi * 2))
        .createShader(rect);
    final pulse = 0.65 + 0.15 * math.sin(phase.value * math.pi * 2);
    final bloom = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = (active ? 7.0 : 5.0)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.saveLayer(rect.inflate(16),
        Paint()..color = Color.fromRGBO(255, 255, 255, pulse));
    canvas.drawRRect(edge, bloom);
    canvas.restore();
    canvas.drawRRect(
        edge,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2);
  }

  @override
  bool shouldRepaint(covariant _GlowPainter old) =>
      old.active != active || old.phase != phase;
}
