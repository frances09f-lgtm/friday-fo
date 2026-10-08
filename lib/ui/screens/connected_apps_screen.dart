import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/friday_controller.dart';
import '../../models/chat_message.dart';

class ConnectedAppsScreen extends StatelessWidget {
  const ConnectedAppsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<FridayController>();
    final result =
        c.messages.where((m) => m.role == MessageRole.friday).lastOrNull;
    Widget command(String title, String phrase) => OutlinedButton(
        onPressed: c.busy ? null : () => c.send(phrase), child: Text(title));
    return Scaffold(
        appBar: AppBar(title: const Text('Connected apps')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text(
              'Same Android phone. No pairing or cloud relay. Open Oro and Lookout once after installing their updates.'),
          const SizedBox(height: 16),
          const Text('Oro', style: TextStyle(fontSize: 22)),
          const Text(
              'Reads saved quote and paper account data with age. It never places or closes a trade.'),
          Wrap(spacing: 8, children: [
            command('Gold price', 'gold price'),
            command('Paper balance', 'oro balance'),
            command('Open trades', 'my open trades'),
            command('TP / SL', 'my trade tp sl'),
            command('Paper P/L', 'my total trade pnl'),
            command('Open Oro', 'open Oro')
          ]),
          const SizedBox(height: 16),
          const Text('Lookout', style: TextStyle(fontSize: 22)),
          const Text(
              'Reads saved watch status, last-check age and saved values. No fresh website fetch, creation, pause or deletion in this version.'),
          Wrap(spacing: 8, children: [
            command('Watch status', 'Lookout status'),
            command('Open Lookout', 'open Lookout')
          ]),
          const SizedBox(height: 16),
          const Text(
              'You can type these commands in Chat, or tap the Home orb and say them. Reading saved app data is offline; voice recognition may need internet.'),
          const SizedBox(height: 16),
          if (c.busy) const LinearProgressIndicator(),
          if (result != null)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(result.text))),
        ]));
  }
}
