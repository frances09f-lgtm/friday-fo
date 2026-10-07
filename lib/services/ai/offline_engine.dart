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

  static final _whatsApp = RegExp(
    r'^(?:send\s+)?(?:a\s+)?whatsapp(?:\s+message)?\s+(?:to\s+)?(?<who>.+?)\s+(?:saying|that)\s+(?<what>.+?)[\s.!?]*$',
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

  // Friday + Oro (user project: connect the apps, offline-first). These
  // questions are answered from Oro's on-device snapshot, never invented.
  static final _oroPrice = RegExp(
    r'gold.*(price|rate|cost|trading)|(price|rate|cost).*(gold|xau)|\bxau\b|gold (?:rate|price|at)|how.?s gold',
    caseSensitive: false,
  );

  static final _oroTrades = RegExp(
    r'(open|running|current|active|my)\s+(trades?|positions?)|(trades?|positions?).*(open|running|now|active)',
    caseSensitive: false,
  );

  static final _oroTpsl = RegExp(
    r'\b(tp|sl|take.?profit|stop.?loss)\b|(target|stop).*(trade|gold|buy|sell|position)',
    caseSensitive: false,
  );

  static final _oroBalance = RegExp(
    r'(paper|trading|oro|account)\s+balance|balance.*(paper|trading|oro)|how.*(trading|paper).*(doing|going)',
    caseSensitive: false,
  );

  // "Close all apps" (user voice ask, phone + Windows).
  static final _closeAllApps = RegExp(
    r'\b(close|clear|kill)\b.*\b(all|background|every|running)\b.*\bapps?\b|\bclose everything\b',
    caseSensitive: false,
  );

  static final _openAnywhere = RegExp(
    r'(?:\band\b|\bthen\b|,)\s*(?:please\s+)?(?:open|launch|start)\s+(?<app>[a-z0-9][a-z0-9 .+]*?)(?=\s*(?:\band\b|\bthen\b|,|\.|!|$))',
    caseSensitive: false,
  );

  /// Multi-part commands: "flashlight off and open camera", "set volume
  /// 40 and open WhatsApp", "brightness 50 and volume 20". Collect every
  /// clause we can match; two or more become an action list in the order
  /// the user said them. Returns null when fewer than two parts match -
  /// the single-command ladder below handles those.
  FridayResponse? _multiActions(String t, String raw) {
    final found = <({int pos, FridayAction action, String words})>[];

    // Leading "open X and ..." - the app name ends at the connector.
    final lead = _open.firstMatch(t);
    if (lead != null) {
      var app = lead.namedGroup('app')!.trim();
      final cut = RegExp(r'\s+(?:and|then)\s+|,').firstMatch(app);
      if (cut != null) app = app.substring(0, cut.start).trim();
      if (app.isNotEmpty) {
        found.add((
          pos: 0,
          action: FridayAction(type: FridayActionType.openApp, app: app),
          words: 'open $app'
        ));
      }
    }

    final om = _openAnywhere.firstMatch(t);
    if (om != null) {
      final app = om.namedGroup('app')!.trim();
      if (app.isNotEmpty) {
        found.add((
          pos: om.start,
          action: FridayAction(type: FridayActionType.openApp, app: app),
          words: 'open $app'
        ));
      }
    }
    if (t.contains('flashlight') || t.contains('torch')) {
      final off = RegExp(r'\boff\b').hasMatch(t);
      found.add((
        pos: t.indexOf(t.contains('flashlight') ? 'flashlight' : 'torch'),
        action: FridayAction(
            type: off ? FridayActionType.torchOff : FridayActionType.torchOn),
        words: 'flashlight ${off ? 'off' : 'on'}'
      ));
    }
    final vp = _volumePct.firstMatch(raw);
    if (vp != null) {
      final n = int.parse(vp.namedGroup('n')!).clamp(0, 100);
      found.add((
        pos: vp.start,
        action: FridayAction(
            type: FridayActionType.setVolume, target: n.toString()),
        words: 'volume to $n%'
      ));
    }
    final bp = _brightnessPct.firstMatch(raw);
    if (bp != null) {
      final n = int.parse(bp.namedGroup('n')!).clamp(0, 100);
      found.add((
        pos: bp.start,
        action: FridayAction(
            type: FridayActionType.setBrightness, target: n.toString()),
        words: 'brightness to $n%'
      ));
    }

    if (found.length < 2) return null;
    found.sort((a, b) => a.pos.compareTo(b.pos));
    final words = found.map((e) => e.words).join(' and ');
    return FridayResponse(
      reply: 'Doing both: $words.',
      action: found.first.action,
      extraActions: found.sublist(1).map((e) => e.action).toList(),
      source: FridaySource.offline,
    );
  }

  FridayResponse handle(String text, {DateTime? now}) {
    final t = text.trim().toLowerCase();
    final clock = now ?? DateTime.now();

    // Multi-part commands first - the single ladder swallows one half.
    final multi = _multiActions(t, text.trim());
    if (multi != null) return multi;

    // Oro trade questions - answered from the on-device bridge.
    if (_oroTpsl.hasMatch(t)) {
      return const FridayResponse(
        reply: 'Checking Oro.',
        action: FridayAction(type: FridayActionType.oroStatus, target: 'tpsl'),
        source: FridaySource.offline,
      );
    }
    if (_oroTrades.hasMatch(t)) {
      return const FridayResponse(
        reply: 'Checking Oro.',
        action:
            FridayAction(type: FridayActionType.oroStatus, target: 'trades'),
        source: FridaySource.offline,
      );
    }
    if (_oroBalance.hasMatch(t)) {
      return const FridayResponse(
        reply: 'Checking Oro.',
        action:
            FridayAction(type: FridayActionType.oroStatus, target: 'balance'),
        source: FridaySource.offline,
      );
    }
    if (_oroPrice.hasMatch(t)) {
      return const FridayResponse(
        reply: 'Checking Oro.',
        action: FridayAction(type: FridayActionType.oroStatus, target: 'price'),
        source: FridaySource.offline,
      );
    }

    // Close all background apps (phone) / app windows (Windows).
    if (_closeAllApps.hasMatch(t)) {
      return const FridayResponse(
        reply: 'Closing all apps.',
        action: FridayAction(type: FridayActionType.closeAllApps),
        source: FridaySource.offline,
      );
    }

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

    // WhatsApp named explicitly: route to WhatsApp, never to SMS.
    final wa = _whatsApp.firstMatch(text.trim());
    if (wa != null) {
      final who = wa.namedGroup('who')!.trim();
      final what = wa.namedGroup('what')!.trim();
      return FridayResponse(
        reply: 'Opening WhatsApp for $who.',
        action: FridayAction(
            type: FridayActionType.sendWhatsApp, target: who, body: what),
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
    // "increase brightness" / "decrease brightness" - 5% steps (user ask).
    // Exact percents ("brightness 40") are matched earlier, so any
    // brightness phrase reaching here is an up/down step.
    if (t.contains('brightness') || t.contains('brighter') || t.contains('dim')) {
      final down = RegExp(r'decrease|down|lower|dim|reduce').hasMatch(t);
      return FridayResponse(
        reply:
            down ? 'Turning the brightness down.' : 'Turning the brightness up.',
        action: FridayAction(
            type: down
                ? FridayActionType.brightnessDown
                : FridayActionType.brightnessUp),
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
          "I couldn't reach the cloud and no local model is loaded. I can still run phone commands: open an app, read messages, set a reminder, flashlight, volume, Wi-Fi or Bluetooth, close all apps, or answer gold price and open trades from Oro.",
      source: FridaySource.offline,
    );
  }
}
