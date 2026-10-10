import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/friday_controller.dart';
import '../../services/speech/speech_service.dart';
import '../../services/storage/settings_store.dart';
import '../../services/agent/friday_agent.dart';
import '../stitch_style.dart';

class ImmersiveVoiceScreen extends StatefulWidget {
  const ImmersiveVoiceScreen({super.key});
  @override
  State<ImmersiveVoiceScreen> createState() => _ImmersiveVoiceState();
}

class _ImmersiveVoiceState extends State<ImmersiveVoiceScreen> {
  bool ready = false;
  String? error;
  @override
  void initState() {
    super.initState();
    context.read<SpeechService>().initSpeech().then((ok) {
      if (mounted) setState(() => ready = ok);
    });
  }

  Future<void> toggle() async {
    final s = context.read<SpeechService>(),
        c = context.read<FridayController>();
    if (s.isListening) {
      await s.stopListening();
      if (mounted) setState(() {});
      return;
    }
    if (c.busy || (context.read<FridayAgent?>()?.running ?? false)) return;
    if (!ready) {
      setState(() => error = 'Microphone not ready. Check Assistant setup.');
      return;
    }
    c.setPartialHeard('');
    s.startListening(onResult: (t) {
      c.setPartialHeard(t);
      if (mounted) setState(() {});
    }, onDone: () {
      if (mounted) {
        setState(() => error = s.lastSttError);
        if (c.partialHeard.trim().isNotEmpty) c.send(c.partialHeard);
      }
    });
    setState(() => error = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<FridayController>(),
        settings = context.watch<SettingsStore>();
    final s = context.read<SpeechService>();
    return Scaffold(
        appBar: const StitchHeader(title: 'Live Voice Session', back: true),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Align(
              alignment: Alignment.centerLeft,
              child: StitchBadge('VOICE INPUT · SYSTEM SPEECH')),
          const SizedBox(height: 10),
          Text('Push to talk · Qwen .task model retained',
              style: Stitch.mono()),
          const SizedBox(height: 34),
          const Center(child: FridayOrb(size: 290, voice: true)),
          const SizedBox(height: 12),
          Center(
              child: StitchBadge(s.isListening
                  ? 'LISTENING...'
                  : c.busy
                      ? c.phase.toUpperCase()
                      : 'READY TO LISTEN')),
          const SizedBox(height: 24),
          Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (int i = 0; i < 17; i++)
              Container(
                  width: 4,
                  height: s.isListening
                      ? ([22.0, 31.0, 18.0, 36.0, 42.0][i % 5])
                      : 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                      color: i % 3 == 0
                          ? Stitch.blue
                          : Stitch.cyan
                              .withValues(alpha: s.isListening ? 1 : .35),
                      borderRadius: BorderRadius.circular(3)))
          ])),
          const SizedBox(height: 8),
          Center(
              child: Text('Voice activity · not an audio-level meter',
                  style: Stitch.mono(9))),
          const SizedBox(height: 24),
          StitchCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('LIVE TRANSCRIPTION', style: Stitch.mono(11, Stitch.cyan)),
                const SizedBox(height: 16),
                Text(
                    c.partialHeard.isEmpty
                        ? 'Tap the microphone and speak. Your words appear here.'
                        : c.partialHeard,
                    style: Stitch.title(22)),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: const TextStyle(color: Color(0xFFFFB4AB)))
                ]
              ])),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            IconButton.filledTonal(
                style: IconButton.styleFrom(
                    backgroundColor: Stitch.high,
                    foregroundColor: Stitch.muted),
                tooltip: 'Stop listening',
                onPressed: () async {
                  await s.stopListening();
                  if (mounted) setState(() {});
                },
                icon: const Icon(Icons.mic_off)),
            FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Stitch.cyan,
                    foregroundColor: const Color(0xFF002C72),
                    padding: const EdgeInsets.all(24),
                    shape: const CircleBorder()),
                onPressed: toggle,
                child: Icon(s.isListening ? Icons.stop : Icons.mic, size: 36)),
            IconButton.filledTonal(
                style: IconButton.styleFrom(
                    backgroundColor: Stitch.high,
                    foregroundColor: Stitch.muted),
                tooltip: 'Spoken responses',
                onPressed: () =>
                    settings.setSpeakReplies(!settings.speakReplies),
                icon: Icon(
                    settings.speakReplies ? Icons.volume_up : Icons.volume_off))
          ]),
          const SizedBox(height: 24),
          TextButton.icon(
              onPressed: () async {
                await s.stopSpeaking();
                if (s.isListening) await s.stopListening();
                if (!mounted) return;
                final a = context.read<FridayAgent?>();
                if (a?.running == true) a!.stop();
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.pan_tool_alt),
              label: const Text('Stop voice / screen task')),
          if (c.messages.isNotEmpty) ...[
            const SizedBox(height: 12),
            StitchCard(child: SelectableText(c.messages.last.text))
          ]
        ]));
  }
}
