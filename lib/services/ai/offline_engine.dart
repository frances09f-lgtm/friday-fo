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
