import '../friday_motion.dart';

import 'package:flutter/material.dart';

import '../../services/device/device_hub.dart';

class BitChordControlsScreen extends StatefulWidget {
  const BitChordControlsScreen({super.key});
  @override
  State<BitChordControlsScreen> createState() => _BitChordControlsState();
}

class _BitChordControlsState extends State<BitChordControlsScreen> {
  Map<String, dynamic> state = {};
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final s = await DeviceHub().bitchordState();
    if (mounted) setState(() => state = s);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('BitChord controls')),
    body: MotionList(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Default music app: BitChord',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          'Android notification access allows Friday to find BitChord media sessions. Android grants broad notification-listener access, even though Friday ignores notification content and filters player metadata to BitChord only. Enable it only if you agree. You can revoke it in Android settings at any time.',
        ),
        const SizedBox(height: 12),
        Text(
          state['enabled'] == true
              ? 'Notification access: enabled'
              : 'Notification access: off',
        ),
        Text('BitChord sessions: ${state['bitchordSessions'] ?? "unknown"}'),
        if (state['error'] != null) Text('${state['error']}'),
        MotionPress(
          child: OutlinedButton(
            onPressed: () async {
              await DeviceHub().spotifySettings();
            },
            child: const Text('Review Android notification access'),
          ),
        ),
        MotionPress(
          child: TextButton(
            onPressed: refresh,
            child: const Text('Refresh status'),
          ),
        ),
        const Text(
          'Open BitChord and choose a track or playlist first. Play/Stop verifies playback state; Next/Previous verifies a changed track ID or title/artist/album. No metadata means no track-change success claim. BitChord may block skipping, expose no queue, or control a different connected device.',
        ),
      ],
    ),
  );
}
