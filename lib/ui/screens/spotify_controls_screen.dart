import 'package:flutter/material.dart';
import '../../services/device/device_hub.dart';

class SpotifyControlsScreen extends StatefulWidget {
  const SpotifyControlsScreen({super.key});
  @override
  State<SpotifyControlsScreen> createState() => _SpotifyControlsState();
}

class _SpotifyControlsState extends State<SpotifyControlsScreen> {
  Map<String, dynamic> state = {};
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final s = await DeviceHub().spotifyState();
    if (mounted) setState(() => state = s);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Spotify controls')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Direct Spotify player control',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text(
            'Android notification access allows Friday to find Spotify media sessions. Android grants broad notification-listener access, even though Friday ignores notification content and filters player metadata to Spotify only. Enable it only if you agree. You can revoke it in Android settings at any time.'),
        const SizedBox(height: 12),
        Text(state['enabled'] == true
            ? 'Notification access: enabled'
            : 'Notification access: off'),
        Text('Spotify sessions: ${state['spotifySessions'] ?? "unknown"}'),
        if (state['error'] != null) Text('${state['error']}'),
        OutlinedButton(
            onPressed: () async {
              await DeviceHub().spotifySettings();
            },
            child: const Text('Review Android notification access')),
        TextButton(onPressed: refresh, child: const Text('Refresh status')),
        const Text(
            'Open Spotify and choose a track or playlist first. Play/Stop verifies playback state; Next/Previous verifies a changed track ID or title/artist/album. No metadata means no track-change success claim. Spotify may block skipping, expose no queue, or control a different connected device.'),
      ]));
}
