import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/link/device_link.dart';

class DeviceLinkScreen extends StatefulWidget {
  const DeviceLinkScreen({super.key});
  @override
  State<DeviceLinkScreen> createState() => _DeviceLinkScreenState();
}

class _DeviceLinkScreenState extends State<DeviceLinkScreen> {
  final _url = TextEditingController(), _key = TextEditingController();
  String? _own;
  String? _error;
  bool _working = false;
  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final link = context.watch<DeviceLink>();
    return Scaffold(
        appBar: AppBar(title: const Text('Connect devices')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Phone + laptop, without a cloud relay',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text(
              'Use the same Wi-Fi or phone hotspot. Keep both Friday apps open. This pairing allows app launch, device controls, closing laptop windows and reading Oro data. It cannot send messages, make calls or run shell commands. Commands are encrypted. Pairing ends when Friday exits.'),
          const SizedBox(height: 16),
          Text(link.status),
          if (!link.running)
            FilledButton(
                onPressed: () async {
                  try {
                    await link.start();
                  } catch (e) {
                    if (mounted)
                      setState(
                          () => _error = 'Could not start the local link: $e');
                  }
                },
                child: const Text('Enable local link')),
          if (link.running && !link.paired) ...[
            const SizedBox(height: 12),
            const Text('1. Enable the link on both devices.'),
            const Text(
                '2. On ONE device, enter the address and pairing key shown on the other. Use the address for your shared Wi-Fi/hotspot.'),
            const SizedBox(height: 12),
            const Text(
                'This device addresses (if none appear, connect to Wi-Fi):'),
            for (final a
                in link.addresses.where((a) => !a.contains('127.0.0.1')))
              SelectableText(a),
            const SizedBox(height: 8),
            const Text(
                'This device pairing key (only share with your other Friday):'),
            SelectableText(link.pairingKey ?? ''),
            const SizedBox(height: 16),
            TextField(
                controller: _url,
                decoration: const InputDecoration(
                    labelText: 'Other device address',
                    hintText: 'http://192.168.1.5:12345')),
            TextField(
                controller: _key,
                decoration: const InputDecoration(
                    labelText: 'Other device pairing key')),
            DropdownButtonFormField<String>(
                initialValue: _own,
                items: [
                  for (final a
                      in link.addresses.where((a) => !a.contains('127.0.0.1')))
                    DropdownMenuItem(value: a, child: Text(a))
                ],
                onChanged: (v) => setState(() => _own = v),
                decoration: const InputDecoration(
                    labelText: 'My address on the shared network')),
            FilledButton(
                onPressed: _working
                    ? null
                    : () async {
                        setState(() => _working = true);
                        try {
                          await link.join(
                              _url.text.trim(), _key.text.trim(), _own ?? '');
                        } catch (_) {
                          if (mounted)
                            setState(() => _error =
                                'Pairing failed. Check the address/key, shared network and Windows Firewall (allow Friday on private networks).');
                        }
                        if (mounted) setState(() => _working = false);
                      },
                child: Text(_working ? 'Pairing...' : 'Pair')),
          ],
          if (link.paired) ...[
            const SizedBox(height: 12),
            const Text(
                'Try: "open camera on my phone" or "close all apps on my laptop". Unsaved work can be lost when closing laptop apps.')
          ],
          if (link.running)
            TextButton(
                onPressed: link.stop,
                child: const Text('Disconnect and disable link')),
          if (_error != null)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]));
  }
}
