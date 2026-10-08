import 'package:flutter/material.dart';

class CommandsScreen extends StatelessWidget {
  const CommandsScreen({super.key});
  static const groups = <String, List<(String, String)>>{
    'Apps and search': [
      (
        'Open YouTube / open Sona / open Lookout',
        'Request an installed app launch. Exact legacy Sona/Oro names map to Sona. Unknown/ambiguous apps fail, not a guessed launch.'
      ),
      (
        'Open YouTube and search Spider-Man',
        'Opens YouTube search through its supported URL intent. Launch request is not visual proof of results.'
      ),
      (
        'Open Chrome and search today\'s gold price',
        'Opens Chrome Google search. Uses the exact query, not a giant app name.'
      ),
      (
        'Open Instagram and search Rahul',
        'Use Agent Mode for real screen navigation. No public Instagram query-search intent is assumed.'
      ),
    ],
    'Gold and connected apps': [
      (
        'Check current gold price / check Sona status',
        'Read Sona\'s saved on-device quote with age. Does not fetch a new market price.'
      ),
      (
        'Check my open trades / my trade profit / risk / TP and SL / account balance',
        'Read Sona\'s saved positions, P/L, protection/risk and paper balance. Never trades for you.'
      ),
      (
        'Alert me when gold price goes below 4120',
        'Create a one-shot saved-quote alert, checking about every 5 minutes. Above also works. Requires notifications; stale/missing quotes do not trigger.'
      ),
      (
        'Check gold every 5 minutes and tell me if it goes below 4120',
        'Explicit cadence (5min to24h) and above/below threshold. Battery saver has best-effort15min checks.'
      ),
      (
        'Ping me when gold price reaches 4120',
        'No alert is created from ambiguous "reaches". Specify above or below. Equality alerts are not supported.'
      ),
      (
        'Cancel all gold alerts / stop gold tasks',
        'Cancel saved gold background tasks. Open Background tasks to inspect state.'
      ),
      (
        'Check Lookout status / Lookout watches',
        'Read Lookout\'s saved watch state; does not silently change watches.'
      ),
    ],
    'Reminders and phone controls': [
      (
        'Remind me to drink water in 10 minutes / at 6:30 pm',
        'Register a reminder and show the actual result. Notification/exact-alarm permissions may be needed. It is a reminder, not an Alarm-app alarm.'
      ),
      (
        'Flashlight on / flashlight off',
        'Toggle phone torch; reports inability if unsupported.'
      ),
      (
        'Volume up / volume down / set volume 40',
        'Change media volume; percent is0-100.'
      ),
      (
        'Brightness up / brightness down / set brightness 40',
        'Change display brightness. Write-settings permission may be needed.'
      ),
      (
        'Open Wi-Fi settings / Bluetooth',
        'Open system panel. Does not silently turn wireless on/off.'
      ),
      (
        'Read messages / messages from Mom',
        'Read SMS with permission. Does not read arbitrary WhatsApp/Instagram inboxes.'
      ),
      (
        'Call Mom / dial a phone number',
        'Resolve contact and call directly if call permission exists, otherwise open dialer. This chat command is not Agent Mode; check the contact before using.'
      ),
      (
        'Text Mom saying hello',
        'Send SMS directly when required phone/contact permissions are granted. A send request is not delivery proof.'
      ),
      (
        'WhatsApp Mom saying hello',
        'Resolve contact and open WhatsApp with prepared text for review. Delivery is not claimed.'
      ),
      (
        'Close all apps',
        'Windows can close visible windows; Android cannot force-stop other apps through this command.'
      ),
      (
        'Flashlight off and open camera / brightness 50 and volume 20',
        'Supported simple multi-part controls execute in order with actual results. Arbitrary multi-step tasks are not assumed.'
      ),
    ],
    'Agent Mode and pairing': [
      (
        'Agent Mode: Open YouTube and search for GTA 6',
        'Local observe/act/verify trial. Also Chrome search, Instagram search and Settings then Bluetooth. Enable Accessibility and guided local model first.'
      ),
      (
        'Stop (Agent Mode or floating Stop control)',
        'Stops future agent actions; cannot undo actions already taken. No automatic resume.'
      ),
      (
        'Open YouTube on my laptop / phone',
        'Paired same-network device launch. Pairing supports limited controls and saved Sona reads; not arbitrary remote automation.'
      ),
    ],
  };
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Commands')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Supported command patterns',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
            'Examples below match current handlers. Permission, installed app and Android limits still apply. General AI chat is not a guarantee any phone task can be executed.'),
        for (final g in groups.entries) ...[
          const SizedBox(height: 20),
          Text(g.key,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          for (final c in g.value)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.$1,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text(c.$2)
                        ])))
        ]
      ]));
}
