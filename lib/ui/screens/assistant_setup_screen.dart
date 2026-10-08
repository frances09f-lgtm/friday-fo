import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AssistantSetupScreen extends StatefulWidget {
  const AssistantSetupScreen({super.key});
  @override
  State<AssistantSetupScreen> createState() => _AssistantSetupScreenState();
}

class _AssistantSetupScreenState extends State<AssistantSetupScreen>
    with WidgetsBindingObserver {
  static const channel = MethodChannel('friday/device');
  Map<String, dynamic>? state;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh() async {
    try {
      final s =
          await channel.invokeMapMethod<String, dynamic>('assistantState');
      if (mounted)
        setState(() {
          state = s;
          error = null;
        });
    } catch (_) {
      if (mounted)
        setState(
            () => error = 'Assistant setup is available on the Android phone.');
    }
  }

  Future<void> action(String method) async {
    try {
      final outcome = await channel.invokeMethod(method);
      if (method == 'bubbleStart' && outcome != 'requested') {
        if (mounted)
          setState(() => error = outcome == 'permission_required'
              ? 'Allow display over other apps first.'
              : 'Could not start floating assistant.');
        return;
      }
      if (method == 'assistantSessionTest' && outcome != 'requested') {
        if (mounted)
          setState(() => error = outcome == 'not_active'
              ? 'Friday voice service is not active. Choose None, then Friday again in default assistant settings.'
              : 'System session test failed. Refresh and read invocation details.');
        return;
      }
      await refresh();
    } catch (_) {
      if (mounted)
        setState(() => error =
            'Could not open this setup step. Check Android app settings.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Assistant setup'), actions: [
        IconButton(onPressed: refresh, icon: const Icon(Icons.refresh))
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
            'Enable a global Friday bubble over other apps. Tap opens the command panel, hold starts voice, swipe sideways opens full Friday. Android requires display-over-apps permission.'),
        const SizedBox(height: 16),
        Text(
            'Display over other apps: ${state == null ? 'Not checked' : state!['overlay'] == true ? 'Allowed' : 'Not allowed'}'),
        OutlinedButton(
            onPressed: () => action('assistantOverlayPermission'),
            child: const Text('Allow display over other apps')),
        Text(
            'Microphone: ${state == null ? 'Not checked' : state!['microphone'] == true ? 'Allowed' : 'Not allowed'}'),
        OutlinedButton(
            onPressed: () => action('assistantMicPermission'),
            child: const Text('Allow microphone')),
        Text(
            'Default assistant: ${state == null ? 'Not checked' : state!['selected'] == true ? 'Friday selected' : 'Friday not selected'}'),
        OutlinedButton(
            onPressed: () => action('assistantSettings'),
            child: const Text('Choose Friday as assistant')),
        const Text(
            'On OxygenOS, also set the power button press-and-hold action to the digital assistant in phone settings. Friday cannot change this system preference.'),
        const SizedBox(height: 16),
        FilledButton(
            onPressed: state?['overlay'] == true && state?['microphone'] == true
                ? () => action('assistantPreview')
                : null,
            child: const Text('Test floating bar')),
        const SizedBox(height: 12),
        Text(
            'Floating assistant: ${state?['bubble'] == true ? 'Service running' : 'Off'}'),
        FilledButton(
            onPressed:
                state?['overlay'] == true ? () => action('bubbleStart') : null,
            child: const Text('Show floating bubble')),
        OutlinedButton(
            onPressed: () => action('bubbleStop'),
            child: const Text('Hide floating bubble')),
        const Text(
            'A persistent Android notification stays visible while enabled. Hide here, in the panel, or from that notification. It does not auto-start at boot; Android may end the service. Enable microphone before holding for voice.'),
        const Text(
            'Then open another app and hold the power button. The bar should appear over it and listen. You can close it with the X.'),
        const SizedBox(height: 12),
        Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Power-button diagnostic',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                          'Voice service: ${state?['serviceReady'] == true ? 'Ready' : 'Not active'}'),
                      SelectableText(
                          'Android voice service: ${state?['voiceService'] ?? 'Not checked'}'),
                      SelectableText(
                          'Android assist app: ${state?['assistComponent'] ?? 'Not checked'}'),
                      OutlinedButton(
                          onPressed: () => action('assistantSessionTest'),
                          child: const Text('Test system assistant session')),
                      const Text(
                          'This tests the Android session, not just the floating bar. If not active after an update, select None then Friday in default assistant settings.'),
                    ]))),
        const Text('Last assistant invocation'),
        SelectableText(state?['invocation']?.toString() ?? 'Not checked'),
        const Text(
            'If holding power does nothing, refresh this screen and send the invocation line. It shows whether Android called Friday or failed to open the overlay.'),
        if ((state?['invocationHistory']?.toString() ?? '').isNotEmpty)
          ExpansionTile(title: const Text('Invocation history'), children: [
            SelectableText(state!['invocationHistory'].toString())
          ]),
        if (error != null) Text(error!),
      ]));
}
