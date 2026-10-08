import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/ai/local_model_service.dart';
import '../../services/agent/friday_agent.dart';

class LocalModelSetupScreen extends StatefulWidget {
  const LocalModelSetupScreen({super.key});
  @override
  State<LocalModelSetupScreen> createState() => _LocalModelSetupState();
}

class _LocalModelSetupState extends State<LocalModelSetupScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<LocalModelService>().checkSetup());
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocalModelService>();
    final running = context.watch<FridayAgent>().running;
    return Scaffold(
        appBar: AppBar(title: const Text('Local model setup')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Qwen 2.5 · 0.5B',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'Public Apache 2.0 model, converted by LiteRT community for Android CPU inference. No account or API key needed. Uses Friday\'s existing local engine, not Replier\'s GGUF files.'),
          const SizedBox(height: 12),
          const Text(
              'Download: 547 MB. Allow about 1.4 GB free storage during setup and at least 3 GB phone RAM. Keep Friday open; Wi-Fi recommended. Download can resume after interruption. Once installed, screen inference stays on your phone.'),
          const SizedBox(height: 16),
          Text(l.setupStatus),
          if (l.setupBusy) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
                value: l.downloaded > 0
                    ? l.downloaded / LocalModelService.modelBytes
                    : null),
            Text('${(l.downloaded / 1000000).toStringAsFixed(1)} / 546.7 MB'),
            TextButton(
                onPressed: l.cancelSetup, child: const Text('Cancel download'))
          ],
          const SizedBox(height: 12),
          FilledButton(
              onPressed: l.setupBusy || running ? null : l.downloadGuided,
              child: const Text('Download and test local model')),
          OutlinedButton(
              onPressed: l.setupBusy || running ? null : l.loadAndTest,
              child: const Text('Load and test installed model')),
          const SizedBox(height: 12),
          const Text(
              'SHA-256 and exact size are checked before installation. A real inference test follows loading. That test proves the engine responded, not that every agent decision is right. Try YouTube search first. Setup errors do not claim readiness or fall back to cloud.'),
          const SizedBox(height: 12),
          const SelectableText(
              'Source: huggingface.co/litert-community/Qwen2.5-0.5B-Instruct'),
        ]));
  }
}
