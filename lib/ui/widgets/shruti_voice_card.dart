import 'package:flutter/material.dart';

import '../stitch_style.dart';

/// Settings > Voice card for the optional Shruti offline voice input. Pure
/// presentation: the owning screen wires the toggle into SettingsStore and
/// the download buttons into ShrutiStt, so this card stays testable without
/// platform channels.
class ShrutiVoiceCard extends StatelessWidget {
  const ShrutiVoiceCard({
    super.key,
    required this.enabled,
    required this.onToggle,
    required this.modelReady,
    required this.downloading,
    required this.downloadedBytes,
    this.error,
    this.onDownload,
    this.onDelete,
  });

  final bool enabled;
  final ValueChanged<bool> onToggle;
  final bool modelReady;
  final bool downloading;
  final int downloadedBytes;
  final String? error;
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;

  static const totalMb = '29.5';

  @override
  Widget build(BuildContext context) {
    final mb = (downloadedBytes / (1024 * 1024)).toStringAsFixed(1);
    final String subtitle;
    if (downloading) {
      subtitle = 'Downloading model: $mb of $totalMb MB';
    } else if (modelReady) {
      subtitle = 'Model on this phone ($totalMb MB). Works offline.';
    } else if (error != null) {
      subtitle = error!;
    } else {
      subtitle = 'Needs a one-time $totalMb MB model download';
    }
    return StitchCard(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(children: [
          SwitchListTile(
              title: const Text('Offline voice input (Shruti)'),
              subtitle: const Text(
                  'Understands English, Hindi and Marathi on the phone'),
              value: enabled,
              onChanged: onToggle),
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(children: [
                Expanded(
                    child: Text(subtitle,
                        style: const TextStyle(
                            color: Stitch.muted, fontSize: 12.5))),
                if (!modelReady && !downloading)
                  TextButton(
                      onPressed: onDownload, child: const Text('Download')),
                if (modelReady)
                  TextButton(onPressed: onDelete, child: const Text('Delete')),
              ])),
        ]));
  }
}
