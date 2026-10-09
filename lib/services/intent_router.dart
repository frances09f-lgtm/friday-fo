import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/friday_response.dart';
import 'device/device_hub.dart';
import 'oro/oro_bridge.dart';
import 'lookout_bridge.dart';
import 'device/reminder_service.dart';
import 'usage_reporter.dart';

/// Carries out the phone action a brain decided on, and returns a short
/// human line about what happened (or why it could not).
class IntentRouter {
  IntentRouter({required this.deviceHub, required this.reminders});

  final DeviceHub deviceHub;
  final ReminderService reminders;

  /// Runs every action from one message, in order, and merges the
  /// per-action outcomes into one reply (one line per action).
  Future<String> executeAll(List<FridayAction> actions) async {
    final outcomes = <String>[];
    for (final a in actions) {
      final o = await execute(a);
      if (o.isNotEmpty) outcomes.add(o);
    }
    return outcomes.join('\n');
  }

  /// Phone hardware actions (calls, SMS, torch, Android panels, exact
  /// volume/brightness) only exist on Android/iOS. On desktop, say so
  /// honestly instead of failing deep inside a missing plugin.
  static const _phoneOnly = {
    FridayActionType.playMusic,
    FridayActionType.nextMusic,
    FridayActionType.previousMusic,
    FridayActionType.stopMusic,
    FridayActionType.searchApp,
    FridayActionType.readMessages,
    FridayActionType.callContact,
    FridayActionType.sendText,
    FridayActionType.sendWhatsApp,
    FridayActionType.torchOn,
    FridayActionType.torchOff,
    FridayActionType.volumeUp,
    FridayActionType.volumeDown,
    FridayActionType.wifiSettings,
    FridayActionType.bluetoothSettings,
    FridayActionType.setVolume,
    FridayActionType.setBrightness,
    FridayActionType.brightnessUp,
    FridayActionType.brightnessDown,
    FridayActionType.openApp,
    FridayActionType.oroStatus,
    FridayActionType.lookoutStatus,
  };

  static bool get _isPhone => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static bool get _isWindows => !kIsWeb && Platform.isWindows;

  /// System controls the laptop build handles itself (via PowerShell).
  static const _windowsCapable = {
    FridayActionType.openApp,
    FridayActionType.volumeUp,
    FridayActionType.volumeDown,
    FridayActionType.setVolume,
    FridayActionType.setBrightness,
    FridayActionType.brightnessUp,
    FridayActionType.brightnessDown,
    FridayActionType.wifiSettings,
    FridayActionType.bluetoothSettings,
    FridayActionType.closeAllApps,
  };

  Future<String> execute(FridayAction action) async {
    if (action.type != FridayActionType.none &&
        action.type != FridayActionType.oroStatus &&
        action.type != FridayActionType.lookoutStatus) {
      UsageReporter.report('action', {'type': action.type.name});
    }
    if (!_isPhone &&
        _phoneOnly.contains(action.type) &&
        !(_isWindows && _windowsCapable.contains(action.type))) {
      return "That phone feature isn't available in the Windows version of Friday.";
    }
    switch (action.type) {
      case FridayActionType.nextMusic:
      case FridayActionType.previousMusic:
      case FridayActionType.stopMusic:
        final command = action.type == FridayActionType.nextMusic
            ? 'next'
            : action.type == FridayActionType.previousMusic
                ? 'previous'
                : 'stop';
        final outcome = await deviceHub.musicControl(command);
        if (outcome == 'stopped')
          return 'Audio changed from active to inactive after Stop. Track/session state is not available.';
        if (outcome == 'inactive')
          return 'No active audio to stop. No change made.';
        return outcome == 'error'
            ? "I couldn't send that media command."
            : 'Requested $command, but the player or track change could not be verified. No completion claimed.';
      case FridayActionType.playMusic:
        switch (await deviceHub.playMusic()) {
          case 'already_active':
            return 'Audio was already active. No new playback change verified.';
          case 'playing':
            return 'Audio changed from inactive to active after Play. Track/session identity is not available.';
          case 'requested':
            return 'Requested Play, but audio did not start. Open your media app and choose a track or queue.';
          default:
            return "I couldn't send the music playback request.";
        }
      case FridayActionType.searchApp:
        return await deviceHub.searchApp(action.app, action.query)
            ? 'Requested ${action.app} search for "${action.query}". Check the opened search screen.'
            : 'Could not open that search. Install the target app or use Agent Mode with a local model.';
      case FridayActionType.openApp:
        return _openApp(action.app);
      case FridayActionType.readMessages:
        return _readMessages(query: action.query);
      case FridayActionType.setReminder:
        return _setReminder(action);
      // Simple device controls: success is silent so the confirmation is
      // just "Done." - the user asked that Friday not echo the command back.
      // Errors and permission asks still say exactly what happened.
      case FridayActionType.torchOn:
        return await deviceHub.setTorch(true)
            ? ''
            : "I couldn't control the flashlight on this device.";
      case FridayActionType.torchOff:
        return await deviceHub.setTorch(false)
            ? ''
            : "I couldn't control the flashlight on this device.";
      case FridayActionType.volumeUp:
        return deviceHub.verifiedVolumeStep(true);
      case FridayActionType.volumeDown:
        return deviceHub.verifiedVolumeStep(false);
      case FridayActionType.brightnessUp:
        return _adjustBrightness(up: true);
      case FridayActionType.brightnessDown:
        return _adjustBrightness(up: false);
      case FridayActionType.wifiSettings:
        return await deviceHub.openSystemPanel('wifi')
            ? ''
            : "I couldn't open Wi-Fi settings.";
      case FridayActionType.bluetoothSettings:
        return await deviceHub.openSystemPanel('bluetooth')
            ? ''
            : "I couldn't open Bluetooth settings.";
      case FridayActionType.callContact:
        return _callContact(action);
      case FridayActionType.sendText:
        return _sendText(action);
      case FridayActionType.sendWhatsApp:
        return _sendWhatsApp(action);
      case FridayActionType.setVolume:
        return _setVolume(action);
      case FridayActionType.setBrightness:
        return _setBrightness(action);
      case FridayActionType.lookoutStatus:
        return LookoutBridge.answer(await deviceHub.lookoutStatusRaw());
      case FridayActionType.oroStatus:
        return _oroStatus(action);
      case FridayActionType.closeAllApps:
        return _closeAllApps();
      case FridayActionType.none:
        return '';
    }
  }

  /// Friday + Oro offline bridge (user project): the answer is built
  /// entirely from Oro's real on-device snapshot - quote, balance, open
  /// positions - with its age disclosed. Never invented numbers.
  Future<String> _oroStatus(FridayAction action) async {
    final snapshot = await OroBridge(deviceHub).read();
    return OroBridge.answer(
        action.target.isEmpty ? 'price' : action.target, snapshot);
  }

  /// "Close all apps" (user voice ask, WINDOWS ONLY - user decision after
  /// hearing Android's limits). Silent on success - "Done." says it.
  Future<String> _closeAllApps() async {
    switch (await deviceHub.closeAllApps()) {
      case 'requested':
        return 'Asked the app windows to close. Save or cancel any unsaved-work prompts.';
      case 'none':
        return 'No app windows to close.';
      case 'unsupported':
        return 'Closing all apps works on the laptop - Android does not let an app remove other apps properly.';
      default:
        return "I couldn't close the app windows.";
    }
  }

  Future<String> _openApp(String appQuery) async {
    final app = await deviceHub.openAppByName(appQuery);
    return appLaunchResult(appQuery, app);
  }

  static String appLaunchResult(String appQuery, InstalledApp? app) {
    if (app == null)
      return "I couldn't find or launch a unique app matching \"$appQuery\". Say its exact name.";
    final label = app.packageName == DeviceHub.sonaPackage ? 'Sona' : app.label;
    return 'Launch requested for $label. I cannot verify it became visible.';
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
    final callResult = await deviceHub.callContact(who);
    if (callResult.startsWith('pick:')) {
      return 'I found a few contacts: ${callResult.substring(5).split('|').join(', ')}. Say the full name and I will call the right one.';
    }
    switch (callResult) {
      case 'calling':
        return ''; // existing single-confirmation call behavior
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
    final textResult = await deviceHub.sendText(who, action.body);
    if (textResult.startsWith('pick:')) {
      return 'I found a few contacts: ${textResult.substring(5).split('|').join(', ')}. Say the full name and I will text the right one.';
    }
    switch (textResult) {
      case 'sent':
        return '';
      case 'asked':
        return 'I need contacts and SMS permission to send texts. Allow it and ask again.';
      case 'no_match':
        return "I couldn't find a contact or number for $who.";
      default:
        return "I couldn't send the text.";
    }
  }

  Future<String> _sendWhatsApp(FridayAction action) async {
    final who = action.target.isNotEmpty ? action.target : action.query;
    if (who.isEmpty || action.body.isEmpty) {
      return 'Tell me who to message on WhatsApp and what to say.';
    }
    final result = await deviceHub.sendWhatsApp(who, action.body);
    if (result.startsWith('pick:')) {
      return 'I found a few contacts: ${result.substring(5).split('|').join(', ')}. Say the full name and I will open WhatsApp for the right one.';
    }
    switch (result) {
      case 'opened':
        return '';
      case 'asked':
        return 'I need contacts permission to message on WhatsApp. Allow it and ask again.';
      case 'no_match':
        return "I couldn't find a contact or number for $who.";
      case 'no_whatsapp':
        return "WhatsApp doesn't seem to be installed on this phone.";
      default:
        return "I couldn't open WhatsApp.";
    }
  }

  Future<String> _setVolume(FridayAction action) async {
    final n = int.tryParse(action.target);
    if (n == null) return 'Tell me the volume percent, like "set volume 30%".';
    return deviceHub.verifiedVolumeSet(n.clamp(0, 100));
  }

  Future<String> _adjustBrightness({required bool up}) async {
    switch (await deviceHub.adjustBrightness(up: up)) {
      case 'ok':
        return '';
      case 'asked':
        return 'I need permission to change brightness - allow Friday on the screen that just opened, then ask again.';
      default:
        return "I couldn't change the brightness.";
    }
  }

  Future<String> _setBrightness(FridayAction action) async {
    final n = int.tryParse(action.target);
    if (n == null)
      return 'Tell me the brightness percent, like "brightness 40%".';
    switch (await deviceHub.setBrightnessPercent(n.clamp(0, 100))) {
      case 'ok':
        return '';
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
    final absolute = DateTime.tryParse(action.target);
    final after = absolute == null
        ? Duration(minutes: action.afterMinutes)
        : absolute.difference(DateTime.now());
    if (after <= Duration.zero)
      return 'That reminder time has passed. Please choose a future time.';
    final ok = await reminders.schedule(
      title: action.title,
      body: action.title,
      after: after,
    );
    if (!ok)
      return 'I could not schedule the reminder. Allow Friday notifications in Android app settings, then try again.';
    final when = reminders.lastRegisteredAt ??
        DateTime.now().add(Duration(minutes: action.afterMinutes));
    return 'Reminder registered for ${when.day}/${when.month} ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}: ${action.title}. ${reminders.lastRegisteredId == null ? '' : 'ID ${reminders.lastRegisteredId}. '}Open Background tasks for gold checks; reminders appear in Android notifications.';
  }
}
