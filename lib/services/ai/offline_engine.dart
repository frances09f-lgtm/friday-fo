import '../../models/friday_response.dart';

/// The last rung of the fallback ladder: pure on-device pattern matching.
/// No model, no key, no network. Covers the core phone commands so Friday is
/// never useless: open apps, read messages, set reminders.
class OfflineEngine {
  const OfflineEngine();

  static final _open = RegExp(
    r'^(?:ok\s+)?(?:friday[,\s]+)?(?:please\s+)?(?:open|launch|start)\s+(?<app>.+?)[\s.!?]*$',
  );

  static final _readMessages = RegExp(
    r'\b(?:read|check|show|any)\b.*\b(?:messages|sms|inbox|texts)\b|^(?:any\s+)?(?:new\s+)?(?:messages|texts|sms)\s*\??$',
  );

  static final _readMessagesWithQuery = RegExp(
    r'(?:messages|texts|sms)\s+(?:from|about|containing)\s+(?<q>.+?)[\s.!?]*$',
  );

  static final _call = RegExp(
    r'^(?:please\s+)?(?:make\s+a\s+call\s+to|call|dial|phone)\s+(?<who>.+?)[\s.!?]*$',
  );

  static final _text = RegExp(
    r'^(?:send\s+)?(?:a\s+)?(?:text|sms|message)\s+(?:to\s+)?(?<who>.+?)\s+(?:saying|that)\s+(?<what>.+?)[\s.!?]*$',
    caseSensitive: false,
  );

  static final _volumePct = RegExp(
    r'(?:set\s+)?volume\s+(?:to\s+)?(?<n>\d{1,3})\s*%?',
    caseSensitive: false,
  );

  static final _brightnessPct = RegExp(
    r'brightness\s+(?:to\s+)?(?<n>\d{1,3})\s*%?',
    caseSensitive: false,
  );

  static final _remindIn = RegExp(
    r'remind me(?:\s+to)?\s+(?<task>.+?)\s+in\s+(?<n>\d+)\s*(?<unit>minutes?|mins?|hours?|hrs?)\b',
  );

  static final _remindAt = RegExp(
    r'remind me(?:\s+to)?\s+(?<task>.+?)\s+at\s+(?<h>\d{1,2})(?::(?<m>\d{2}))?\s*(?<ampm>a\.?m\.?|p\.?m\.?)?\b',
  );

  FridayResponse handle(String text, {DateTime? now}) {
    final t = text.trim().toLowerCase();
    final clock = now ?? DateTime.now();

    final open = _open.firstMatch(t);
    if (open != null) {
      final app = open.namedGroup('app')!.trim();
      return FridayResponse(
        reply: 'Opening $app.',
        action: FridayAction(type: FridayActionType.openApp, app: app),
        source: FridaySource.offline,
      );
    }

    if (_readMessages.hasMatch(t)) {
      final q = _readMessagesWithQuery.firstMatch(t);
      return FridayResponse(
        reply: 'Reading your messages.',
        action: FridayAction(
          type: FridayActionType.readMessages,
          query: q?.namedGroup('q')?.trim() ?? '',
        ),
        source: FridaySource.offline,
      );
    }

    final remindIn = _remindIn.firstMatch(t);
    if (remindIn != null) {
      final n = int.parse(remindIn.namedGroup('n')!);
      final unit = remindIn.namedGroup('unit')!;
      final minutes = unit.startsWith('h') ? n * 60 : n;
      final task = remindIn.namedGroup('task')!.trim();
      return FridayResponse(
        reply: 'Reminder set: $task in $minutes minutes.',
        action: FridayAction(
          type: FridayActionType.setReminder,
          title: task,
          afterMinutes: minutes,
        ),
        source: FridaySource.offline,
      );
    }

    final remindAt = _remindAt.firstMatch(t);
    if (remindAt != null) {
      var hour = int.parse(remindAt.namedGroup('h')!);
      final minute = int.tryParse(remindAt.namedGroup('m') ?? '') ?? 0;
      final ampm = remindAt.namedGroup('ampm')?.replaceAll('.', '') ?? '';
      if (ampm == 'pm' && hour < 12) hour += 12;
      if (ampm == 'am' && hour == 12) hour = 0;

      var when = DateTime(clock.year, clock.month, clock.day, hour, minute);
      if (!when.isAfter(clock)) {
        when = when.add(const Duration(days: 1));
      }
      final minutes = when.difference(clock).inMinutes.clamp(1, 60 * 24 * 7);
      final task = remindAt.namedGroup('task')!.trim();
      return FridayResponse(
        reply:
            'Reminder set: $task at ${when.hour}:${when.minute.toString().padLeft(2, '0')}.',
        action: FridayAction(
          type: FridayActionType.setReminder,
          title: task,
          afterMinutes: minutes,
        ),
        source: FridaySource.offline,
      );
    }

    // Device controls - handled fully on-device, never sent to a model.
    final call = _call.firstMatch(t);
    if (call != null) {
      final who = call.namedGroup('who')!.trim();
      return FridayResponse(
        reply: 'Calling $who.',
        action: FridayAction(type: FridayActionType.callContact, target: who),
        source: FridaySource.offline,
      );
    }

    // Match the raw text so the SMS body keeps the user's original case.
    final sms = _text.firstMatch(text.trim());
    if (sms != null) {
      final who = sms.namedGroup('who')!.trim();
      final what = sms.namedGroup('what')!.trim();
      return FridayResponse(
        reply: 'Texting $who.',
        action: FridayAction(
            type: FridayActionType.sendText, target: who, body: what),
        source: FridaySource.offline,
      );
    }

    final vp = _volumePct.firstMatch(text.trim());
    final bp0 = _brightnessPct.firstMatch(text.trim());
    if (vp != null && bp0 != null) {
      // Both settings in one utterance: apply each with its own value,
      // in the order the user said them.
      final vn = int.parse(vp.namedGroup('n')!).clamp(0, 100);
      final bn = int.parse(bp0.namedGroup('n')!).clamp(0, 100);
      final vol = FridayAction(
          type: FridayActionType.setVolume, target: vn.toString());
      final bri = FridayAction(
          type: FridayActionType.setBrightness, target: bn.toString());
      final ordered = bp0.start < vp.start ? [bri, vol] : [vol, bri];
      final words = ordered
          .map((a) => a.type == FridayActionType.setBrightness
              ? 'brightness to ${a.target}%'
              : 'volume to ${a.target}%')
          .join(' and ');
      return FridayResponse(
        reply: 'Setting $words.',
        action: ordered.first,
        extraActions: ordered.sublist(1),
        source: FridaySource.offline,
      );
    }
    if (vp != null) {
      final n = int.parse(vp.namedGroup('n')!).clamp(0, 100);
      return FridayResponse(
        reply: 'Setting volume to $n%.',
        action: FridayAction(
            type: FridayActionType.setVolume, target: n.toString()),
        source: FridaySource.offline,
      );
    }

    final bp = _brightnessPct.firstMatch(text.trim());
    if (bp != null) {
      final n = int.parse(bp.namedGroup('n')!).clamp(0, 100);
      return FridayResponse(
        reply: 'Setting brightness to $n%.',
        action: FridayAction(
            type: FridayActionType.setBrightness, target: n.toString()),
        source: FridaySource.offline,
      );
    }

    if (t.contains('flashlight') || t.contains('torch')) {
      final off = RegExp(r'\boff\b').hasMatch(t);
      return FridayResponse(
        reply: off ? 'Turning the flashlight off.' : 'Turning the flashlight on.',
        action: FridayAction(
            type: off ? FridayActionType.torchOff : FridayActionType.torchOn),
        source: FridaySource.offline,
      );
    }
    if (t.contains('volume') || t.contains('louder') || t.contains('quieter')) {
      final down = RegExp(r'decrease|down|lower|quieter|reduce').hasMatch(t);
      return FridayResponse(
        reply: down ? 'Turning the volume down.' : 'Turning the volume up.',
        action: FridayAction(
            type: down ? FridayActionType.volumeDown : FridayActionType.volumeUp),
        source: FridaySource.offline,
      );
    }
    if (RegExp(r'wi-?fi').hasMatch(t)) {
      return const FridayResponse(
        reply: 'Opening Wi-Fi settings.',
        action: FridayAction(type: FridayActionType.wifiSettings),
        source: FridaySource.offline,
      );
    }
    if (t.contains('bluetooth')) {
      return const FridayResponse(
        reply: 'Opening Bluetooth settings.',
        action: FridayAction(type: FridayActionType.bluetoothSettings),
        source: FridaySource.offline,
      );
    }

    return const FridayResponse(
      reply:
          "I couldn't reach the cloud and no local model is loaded. I can still run phone commands: open an app, read messages, set a reminder, flashlight, volume, Wi-Fi or Bluetooth.",
      source: FridaySource.offline,
    );
  }
}
