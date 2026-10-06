import '../models/friday_response.dart';
import 'device/device_hub.dart';
import 'device/reminder_service.dart';

/// Carries out the phone action a brain decided on, and returns a short
/// human line about what happened (or why it could not).
class IntentRouter {
  IntentRouter({required this.deviceHub, required this.reminders});

  final DeviceHub deviceHub;
  final ReminderService reminders;

  Future<String> execute(FridayAction action) async {
    switch (action.type) {
      case FridayActionType.openApp:
        return _openApp(action.app);
      case FridayActionType.readMessages:
        return _readMessages(query: action.query);
      case FridayActionType.setReminder:
        return _setReminder(action);
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
