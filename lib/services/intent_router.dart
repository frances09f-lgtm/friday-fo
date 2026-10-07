import '../models/friday_response.dart';
import 'device/device_hub.dart';
import 'device/reminder_service.dart';
import 'usage_reporter.dart';

/// Carries out the phone action a brain decided on, and returns a short
/// human line about what happened (or why it could not).
class IntentRouter {
  IntentRouter({required this.deviceHub, required this.reminders});

  final DeviceHub deviceHub;
  final ReminderService reminders;

  Future<String> execute(FridayAction action) async {
    if (action.type != FridayActionType.none) {
      UsageReporter.report('action', {'type': action.type.name});
    }
    switch (action.type) {
      case FridayActionType.openApp:
        return _openApp(action.app);
      case FridayActionType.readMessages:
        return _readMessages(query: action.query);
      case FridayActionType.setReminder:
        return _setReminder(action);
      case FridayActionType.torchOn:
        return await deviceHub.setTorch(true)
            ? 'Flashlight is on.'
            : "I couldn't control the flashlight on this device.";
      case FridayActionType.torchOff:
        return await deviceHub.setTorch(false)
            ? 'Flashlight is off.'
            : "I couldn't control the flashlight on this device.";
      case FridayActionType.volumeUp:
        return await deviceHub.adjustVolume(up: true)
            ? 'Volume up.'
            : "I couldn't change the volume.";
      case FridayActionType.volumeDown:
        return await deviceHub.adjustVolume(up: false)
            ? 'Volume down.'
            : "I couldn't change the volume.";
      case FridayActionType.wifiSettings:
        return await deviceHub.openSystemPanel('wifi')
            ? 'Opening Wi-Fi settings - Android only lets apps change Wi-Fi from the system panel.'
            : "I couldn't open Wi-Fi settings.";
      case FridayActionType.bluetoothSettings:
        return await deviceHub.openSystemPanel('bluetooth')
            ? 'Opening Bluetooth settings - Android only lets apps change Bluetooth from the system panel.'
            : "I couldn't open Bluetooth settings.";
      case FridayActionType.callContact:
        return _callContact(action);
      case FridayActionType.sendText:
        return _sendText(action);
      case FridayActionType.setVolume:
        return _setVolume(action);
      case FridayActionType.setBrightness:
        return _setBrightness(action);
      case FridayActionType.none:
        return '';
    }
  }

  Future<String> _openApp(String appQuery) async {
    final app = await deviceHub.openAppByName(appQuery);
    if (app == null) {
      return "I couldn't find an app matching \"$appQuery\" on this phone.";
    }
    return 'Opened ${app.label}.';
  }

  Future<String> _readMessages({String query = ''}) async {
    if (!await deviceHub.hasSmsPermission()) {
      await deviceHub.requestSmsPermission();
      if (!await deviceHub.hasSmsPermission()) {
        return 'I need the SMS permission to read messages. Allow it in Settings > Apps > Friday > Permissions, then ask again.';
      }
    }
    final messages = await deviceHub.readSms(query: query, limit: 10);
    if (messages.isEmpty) {
      return query.isEmpty
          ? 'No messages in the inbox.'
          : 'No messages matching "$query".';
    }
    final lines = <String>[
      for (final m in messages.take(3))
        '${m.sender}: ${m.body.length > 80 ? '${m.body.substring(0, 80)}...' : m.body}',
    ];
    return '${messages.length} recent message${messages.length == 1 ? '' : 's'}'
        '${query.isEmpty ? '' : ' matching "$query"'}. Latest: ${lines.join(' | ')}';
  }

  Future<String> _callContact(FridayAction action) async {
    final who = action.target.isNotEmpty ? action.target : action.query;
    if (who.isEmpty) return 'Who should I call?';
    switch (await deviceHub.callContact(who)) {
      case 'calling':
        return 'Calling $who.';
      case 'dialer':
        return 'Opening the dialer with $who - tap the call button. Grant the call permission and I can dial directly.';
      case 'asked':
        return 'I need contacts and phone permission for calls. Allow it and ask again.';
      case 'no_match':
        return "I couldn't find a contact or number for $who.";
      default:
        return "I couldn't place the call.";
    }
  }

  Future<String> _sendText(FridayAction action) async {
    final who = action.target.isNotEmpty ? action.target : action.query;
    if (who.isEmpty || action.body.isEmpty) {
      return 'Tell me who to text and what to say.';
    }
    switch (await deviceHub.sendText(who, action.body)) {
      case 'sent':
        return 'Text sent to $who.';
      case 'asked':
        return 'I need contacts and SMS permission to send texts. Allow it and ask again.';
      case 'no_match':
        return "I couldn't find a contact or number for $who.";
      default:
        return "I couldn't send the text.";
    }
  }

  Future<String> _setVolume(FridayAction action) async {
    final n = int.tryParse(action.target);
    if (n == null) return 'Tell me the volume percent, like "set volume 30%".';
    final ok = await deviceHub.setVolumePercent(n.clamp(0, 100));
    return ok ? 'Volume set to ${n.clamp(0, 100)}%.' : "I couldn't set the volume.";
  }

  Future<String> _setBrightness(FridayAction action) async {
    final n = int.tryParse(action.target);
    if (n == null) return 'Tell me the brightness percent, like "brightness 40%".';
    switch (await deviceHub.setBrightnessPercent(n.clamp(0, 100))) {
      case 'ok':
        return 'Brightness set to ${n.clamp(0, 100)}%.';
      case 'asked':
        return 'I need permission to change brightness - allow Friday on the screen that just opened, then ask again.';
      default:
        return "I couldn't set the brightness.";
    }
  }

  Future<String> _setReminder(FridayAction action) async {
    if (action.afterMinutes <= 0) {
      return 'I need a time for that reminder.';
    }
    final ok = await reminders.schedule(
      title: action.title,
      body: action.title,
      after: Duration(minutes: action.afterMinutes),
    );
    if (!ok) return 'I could not schedule the reminder.';
    return 'Reminder set: ${action.title.isEmpty ? 'reminder' : action.title} in ${action.afterMinutes} minutes.';
  }
}
