/// Friday assistant overlay, scaled to 70% without changing interaction handlers.
library;
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'friday_services.dart';
import 'models/chat_message.dart';
import 'services/speech/speech_service.dart';
import 'state/friday_controller.dart';
import 'ui/orion_style.dart';

@pragma('vm:entry-point')
Future<void> assistantOverlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await createFridayServices(loadHistory: false);
  runApp(MultiProvider(providers: services.providers, child: const AssistantOverlayApp()));
}
class AssistantOverlayApp extends StatefulWidget {
  const AssistantOverlayApp({super.key});
  @override
  State<AssistantOverlayApp> createState() => _AssistantOverlayAppState();
}
class _AssistantOverlayAppState extends State<AssistantOverlayApp> {
  ThemeMode mode = ThemeMode.system;
  @override
  void initState() { super.initState(); _loadMode(); }
  Future<void> _loadMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('orion_theme_mode');
      if (!mounted) return;
      if (saved == 'light' || saved == 'dark') {
        setState(() => mode = saved == 'dark' ? ThemeMode.dark : ThemeMode.light);
      }
    } catch (_) {}
  }
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Friday', debugShowCheckedModeBanner: false,
    theme: Orion.light(), darkTheme: Orion.dark(), themeMode: mode,
    home: const CompactAssistantViewport(child: AssistantPanel()),
  );
}
/// Scales visual dimensions, typography, padding and hit testing together.
/// The native window uses the same scale, so other apps retain more space.
class CompactAssistantViewport extends StatelessWidget {
  static const scale = 0.7;
  final Widget child;
  const CompactAssistantViewport({super.key, required this.child});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, bounds) {
    final media = MediaQuery.of(context);
    final size = Size(bounds.maxWidth / scale, bounds.maxHeight / scale);
    return FittedBox(fit: BoxFit.contain, alignment: Alignment.bottomCenter,
      child: SizedBox(width: size.width, height: size.height,
        child: MediaQuery(data: media.copyWith(size: size,
          padding: media.padding / scale, viewPadding: media.viewPadding / scale,
          viewInsets: media.viewInsets / scale), child: child)));
  });
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
  bool _initializingSpeech = false;
  int _listenGeneration = 0;
  late final SpeechService _speech;
  @override
  void initState() {
    super.initState();
    _speech = context.read<SpeechService>();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'outsideTap') await _dismiss();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final speech = context.read<SpeechService>();
      try {
        final mode = await _channel.invokeMapMethod<String, dynamic>('launchMode');
        if (mounted && !_closeRequested && mode?['voice'] == true) {
          await _beginListening(speech);
          return;
        }
      } catch (_) {}
      // Keyboard opens only when input is tapped.
    });
  }
  @override
  void dispose() {
    _closeRequested = true;
    _invalidateListening();
    unawaited(_speech.stopListening().catchError((Object _) {}));
    _channel.setMethodCallHandler(null);
    _input.dispose(); _focus.dispose(); super.dispose();
  }
  void _invalidateListening() => _listenGeneration++;
  Future<void> _beginListening(SpeechService speech) async {
    if (!mounted || _closeRequested || _sending || _initializingSpeech) return;
    final controller = context.read<FridayController>();
    if (controller.busy) return;
    final generation = ++_listenGeneration;
    _initializingSpeech = true;
    try {
      final ready = await speech.initSpeech();
      if (!ready || !mounted || _closeRequested || _sending || controller.busy || generation != _listenGeneration) return;
      controller.setPartialHeard('');
      bool current() => mounted && !_closeRequested && generation == _listenGeneration;
      speech.startListening(
        onResult: (text) { if (current()) controller.setPartialHeard(text); },
        onDone: () {
          if (!current()) return;
          final text = controller.partialHeard;
          _invalidateListening();
          if (text.trim().isNotEmpty) _submit(text);
        },
      );
    } catch (_) {
      // Unavailable recognizer leaves text input usable.
    } finally { _initializingSpeech = false; }
  }
  void _send() {
    if (!mounted || _closeRequested || _sending || context.read<FridayController>().busy) return;
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear(); _submit(text);
  }
  Future<void> _submit(String text) async {
    if (!mounted || _closeRequested || text.trim().isEmpty) return;
    final controller = context.read<FridayController>();
    if (_sending || controller.busy) return;
    final revision = controller.completedCommandRevision;
    _sending = true;
    _invalidateListening();
    var hiddenForCompletion = false;
    void completed() {
      if (!mounted || _closeRequested || hiddenForCompletion || controller.busy || controller.completedCommandRevision == revision) return;
      hiddenForCompletion = true;
      unawaited(_dismiss());
    }
    controller.addListener(completed);
    try {
      await _speech.stopListening();
      await controller.send(text);
      completed();
    } finally {
      controller.removeListener(completed);
      _sending = false;
      if (mounted && _closeRequested) {
        try { await _channel.invokeMethod<void>('dismiss'); } catch (_) {}
      }
    }
  }
  Future<void> _dismiss() async {
    if (!mounted) return;
    _invalidateListening();
    final controller = context.read<FridayController>();
    final speech = context.read<SpeechService>();
    setState(() => _closeRequested = true);
    _focus.unfocus();
    try { await _channel.invokeMethod('hidePanelWhileBusy'); } catch (_) {}
    if (_sending || controller.busy) { await speech.stopListening(); return; }
    await speech.stopListening();
    try { await _channel.invokeMethod<void>('dismiss'); } catch (_) {}
  }
  Future<void> _openFullApp() async {
    _closeRequested = true;
    _invalidateListening();
    await context.read<SpeechService>().stopListening();
    try { await _channel.invokeMethod<void>('openFriday'); } catch (_) {}
  }
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FridayController>();
    final speech = context.watch<SpeechService>();
    final recent = controller.messages.length <= 6 ? controller.messages : controller.messages.sublist(controller.messages.length - 6);
    final expanded = recent.isNotEmpty || controller.partialHeard.isNotEmpty;
    if (_expanded != expanded) {
      _expanded = expanded;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) {
          try { await _channel.invokeMethod('panelExpanded', {'expanded': expanded}); } catch (_) {}
        }
      });
    }
    final cs = Theme.of(context).colorScheme;
    return Scaffold(backgroundColor: Colors.transparent,
      body: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _dismiss,
        child: Align(alignment: Alignment.bottomCenter,
          child: TweenAnimationBuilder<double>(tween: Tween(begin: 24, end: 0),
            duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic,
            builder: (context, value, child) => Transform.translate(offset: Offset(0, value), child: child),
            child: Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: GestureDetector(onTap: () {},
                child: FridayGlowFrame(active: speech.isListening || controller.busy, enabled: !_closeRequested,
                  child: Container(decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(29)),
                    child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (recent.isNotEmpty) ConstrainedBox(constraints: const BoxConstraints(maxHeight: 180),
                        child: ListView.builder(shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: recent.length, itemBuilder: (_, i) {
                            final m = recent[i]; final isUser = m.role == MessageRole.user;
                            return Align(alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(margin: const EdgeInsets.symmetric(vertical: 2),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(color: isUser ? cs.primaryContainer : cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
                                child: Text(m.text, style: TextStyle(fontSize: 13, color: isUser ? cs.onPrimaryContainer : cs.onSurface))));
                          })),
                      if (controller.partialHeard.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Align(alignment: Alignment.centerLeft,
                          child: Text(controller.partialHeard, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, fontStyle: FontStyle.italic)))),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8), child: Row(children: [
                        PopupMenuButton<String>(tooltip: 'Friday controls', color: cs.surfaceContainerHigh,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: FridayWave(active: speech.isListening, enabled: !_closeRequested)),
                          onSelected: (value) async {
                            if (value == 'open') { await _openFullApp(); }
                            else if (value == 'close') { await _dismiss(); }
                            else {
                              _closeRequested = true; _invalidateListening(); await speech.stopListening();
                              try { await _channel.invokeMethod('hideBubble'); } catch (_) {}
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'open', child: Text('Open Friday')),
                            PopupMenuItem(value: 'close', child: Text('Close panel')),
                            PopupMenuItem(value: 'hide', child: Text('Hide floating assistant')),
                          ]),
                        Expanded(child: TextField(controller: _input, focusNode: _focus,
                          textInputAction: TextInputAction.send, onSubmitted: (_) => _send(),
                          decoration: InputDecoration(hintText: 'Ask Friday anything...',
                            hintStyle: TextStyle(fontSize: 14, color: cs.onSurfaceVariant), isDense: true,
                            filled: true, fillColor: cs.surfaceContainerLowest,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none)))),
                        const SizedBox(width: 4),
                        IconButton.filledTonal(tooltip: speech.isListening ? 'Stop listening' : 'Talk to Friday',
                          style: IconButton.styleFrom(backgroundColor: speech.isListening ? cs.primary : cs.secondaryContainer,
                            foregroundColor: speech.isListening ? cs.onPrimary : cs.onSecondaryContainer,
                            minimumSize: const Size(40, 40), padding: const EdgeInsets.all(8)),
                          icon: Icon(speech.isListening ? Icons.mic : Icons.mic_none),
                          onPressed: () async { if (speech.isListening) { await speech.stopListening(); } else { await _beginListening(speech); } }),
                        if (controller.busy) const Padding(padding: EdgeInsets.all(10),
                          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                        else IconButton.filled(tooltip: 'Send',
                          style: IconButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.onPrimary,
                            minimumSize: const Size(40, 40), padding: const EdgeInsets.all(8)),
                          icon: const Icon(Icons.send, size: 20), onPressed: _send),
                        IconButton(tooltip: 'Close Friday', style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant,
                          minimumSize: const Size(32, 40), padding: const EdgeInsets.all(4)),
                          icon: const Icon(Icons.close, size: 18), onPressed: _dismiss),
                      ])),
                    ])),
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
class FridayGlowFrame extends StatelessWidget {
  final Widget child;
  final bool active, enabled;
  const FridayGlowFrame({super.key, required this.child, this.active = false, this.enabled = true});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(32),
        border: Border.all(color: active ? cs.primary : cs.outlineVariant, width: active ? 2 : 1),
        boxShadow: [BoxShadow(color: cs.shadow.withValues(alpha: 0.16), blurRadius: 14, offset: const Offset(0, 4))]),
      child: child);
  }
}
class FridayWave extends StatefulWidget {
  final bool active, enabled;
  const FridayWave({super.key, required this.active, required this.enabled});
  @override
  State<FridayWave> createState() => _FridayWaveState();
}
class _FridayWaveState extends State<FridayWave> with SingleTickerProviderStateMixin {
  late final AnimationController wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
  void sync() {
    if (widget.active && widget.enabled && !MediaQuery.disableAnimationsOf(context)) {
      if (!wave.isAnimating) wave.repeat();
    } else { wave.stop(); }
  }
  @override
  void didChangeDependencies() { super.didChangeDependencies(); sync(); }
  @override
  void didUpdateWidget(covariant FridayWave old) { super.didUpdateWidget(old); sync(); }
  @override
  void dispose() { wave.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(width: 40, height: 40, alignment: Alignment.center,
      decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
      child: SizedBox(width: 32, height: 32, child: CustomPaint(painter: _WavePainter(wave, widget.active, cs.onPrimaryContainer))));
  }
}
class _WavePainter extends CustomPainter {
  final Animation<double> phase;
  final bool active;
  final Color color;
  _WavePainter(this.phase, this.active, this.color) : super(repaint: phase);
  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 5; i++) {
      final pulse = (math.sin(phase.value * math.pi * 2 + i * 0.95) + 1) / 2;
      final height = active ? 6 + 22 * pulse : [8.0, 15.0, 22.0, 15.0, 8.0][i];
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(i * 6.0 + 2, (size.height - height) / 2, 3, height), const Radius.circular(2));
      canvas.drawRRect(r, Paint()..color = color);
    }
  }
  @override
  bool shouldRepaint(covariant _WavePainter old) => old.active != active || old.color != color;
}
