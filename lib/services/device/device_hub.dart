import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import 'windows_device.dart';

class InstalledApp {
  const InstalledApp({required this.label, required this.packageName});
  final String label;
  final String packageName;
}

class SmsEntry {
  const SmsEntry({required this.sender, required this.body, required this.at});
  final String sender;
  final String body;
  final DateTime at;
}

/// Talks to the Android side over one method channel: installed-app lookup,
/// app launching, and SMS reading. The Kotlin half lives in MainActivity.kt.
class DeviceHub {
  static const _channel = MethodChannel('friday/device');

  static bool get _isWindows => !kIsWeb && Platform.isWindows;

  Future<String> musicControl(String command) async {
    try {
      return await _channel
              .invokeMethod<String>('musicControl', {'command': command}) ??
          'error';
    } catch (_) {
      return 'error';
    }
  }

  Future<String> playMusic() async {
    try {
      return await _channel.invokeMethod<String>('playMusic') ?? 'error';
    } on Exception {
      return 'error';
    }
  }

  Future<List<InstalledApp>> getInstalledApps() async {
    try {
      final raw = await _channel.invokeListMethod<dynamic>('getInstalledApps');
      if (raw == null) return const [];
      return raw
          .whereType<Map>()
          .map((m) => InstalledApp(
                label: m['label'] as String? ?? '',
                packageName: m['package'] as String? ?? '',
              ))
          .toList();
    } on Exception {
// ignore: unreachable_switch_case

      return const [];
    }
  }

  Future<bool> hasSmsPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasSmsPermission') ?? false;
    } on Exception {
// ignore: unreachable_switch_case

      return false;
    }
  }

  Future<void> requestSmsPermission() async {
    try {
      await _channel.invokeMethod<bool>('requestSmsPermission');
    } on Exception {
// ignore: unreachable_switch_case

      // The system dialog decides; the next hasSmsPermission check reads it.
    }
  }

  Future<List<SmsEntry>> readSms({String query = '', int limit = 10}) async {
    try {
      final raw = await _channel.invokeListMethod<dynamic>(
        'readSms',
        <String, dynamic>{'query': query, 'limit': limit},
      );
      if (raw == null) return const [];
      return raw.whereType<Map>().map((m) {
        final millis = (m['date'] as num?)?.toInt() ?? 0;
        return SmsEntry(
          sender: m['sender'] as String? ?? '',
          body: m['body'] as String? ?? '',
          at: DateTime.fromMillisecondsSinceEpoch(millis),
        );
      }).toList();
    } on Exception {
// ignore: unreachable_switch_case

      return const [];
    }
  }

  /// Returns calling | dialer | asked | no_match | error.
  Future<String> callContact(String who) async {
    try {
      return await _channel.invokeMethod<String>('callContact', {'who': who}) ??
          'error';
    } on Exception {
// ignore: unreachable_switch_case

      return 'error';
    }
  }

  /// Returns sent | asked | no_match | error.
  Future<String> sendText(String who, String body) async {
    try {
      return await _channel
              .invokeMethod<String>('sendText', {'who': who, 'text': body}) ??
          'error';
    } on Exception {
// ignore: unreachable_switch_case

      return 'error';
    }
  }

  /// Returns opened | asked | no_match | no_whatsapp | pick:<names> | error.
  Future<String> sendWhatsApp(String who, String body) async {
    try {
      return await _channel.invokeMethod<String>(
              'sendWhatsApp', {'who': who, 'text': body}) ??
          'error';
    } on Exception {
      return 'error';
    }
  }

  Future<bool> setVolumePercent(int percent) async {
    if (_isWindows) return WindowsDevice.setVolumePercent(percent);
    try {
      return await _channel
              .invokeMethod<bool>('setVolume', {'percent': percent}) ??
          false;
    } on Exception {
// ignore: unreachable_switch_case

      return false;
    }
  }

  /// Returns ok | asked | error.
  /// Steps brightness by exactly 5% up/down (user ask). Same 'ok' /
  /// 'asked' / 'error' contract as setBrightnessPercent.
  Future<String> adjustBrightness({required bool up}) async {
    if (_isWindows) {
      return await WindowsDevice.adjustBrightness(up: up) ? 'ok' : 'error';
    }
    try {
      return await _channel
              .invokeMethod<String>(up ? 'brightnessUp' : 'brightnessDown') ??
          'error';
    } on Exception {
// ignore: unreachable_switch_case

      return 'error';
    }
  }

  Future<String> setBrightnessPercent(int percent) async {
    if (_isWindows) {
      return await WindowsDevice.setBrightnessPercent(percent) ? 'ok' : 'error';
    }
    try {
      return await _channel
              .invokeMethod<String>('setBrightness', {'percent': percent}) ??
          'error';
    } on Exception {
// ignore: unreachable_switch_case

      return 'error';
    }
  }

  Future<bool> setTorch(bool on) async {
    try {
      return await _channel.invokeMethod<bool>('setTorch', {'on': on}) ?? false;
    } on Exception {
// ignore: unreachable_switch_case

      return false;
    }
  }

  Future<bool> adjustVolume({required bool up}) async {
    if (_isWindows) return WindowsDevice.adjustVolume(up: up);
    try {
      return await _channel
              .invokeMethod<bool>(up ? 'volumeUp' : 'volumeDown') ??
          false;
    } on Exception {
// ignore: unreachable_switch_case

      return false;
    }
  }

  Future<bool> openSystemPanel(String which) async {
    if (_isWindows) return WindowsDevice.openSettingsPanel(which);
    try {
      return await _channel.invokeMethod<bool>('openPanel', {'which': which}) ??
          false;
    } on Exception {
// ignore: unreachable_switch_case

      return false;
    }
  }

  /// Fuzzy-matches the app the user (or the model) named against the
  /// installed list, then launches it. Returns the app label, or null when
  /// nothing on the phone matches.
  /// Raw JSON snapshot from Oro's offline bridge provider, or null when
  /// Oro is not installed / has nothing yet. Phone-only by design.
  Future<String?> lookoutStatusRaw() async {
    if (_isWindows || kIsWeb) return null;
    try {
      return await _channel.invokeMethod<String>('lookoutStatus');
    } catch (_) {
      return null;
    }
  }

  Future<String?> oroStatusRaw() async {
    if (_isWindows || kIsWeb) return null;
    try {
      return await _channel.invokeMethod<String>('oroStatus');
    } catch (_) {
      return null;
    }
  }

  /// "Close all apps" (user voice ask, WINDOWS ONLY - user decision after
  /// hearing Android's honest limits). Closes visible app windows on
  /// Windows; anywhere else returns 'unsupported' for the router's honest
  /// line.
  Future<String> closeAllApps() async {
    if (_isWindows) return WindowsDevice.closeAllApps();
    return 'unsupported';
  }

  Future<bool> searchApp(String app, String query) async {
    if (_isWindows || kIsWeb) return false;
    try {
      return await _channel
              .invokeMethod<bool>('searchApp', {'app': app, 'query': query}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<InstalledApp?> openAppByName(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return null;
    if (_isWindows) {
      return await WindowsDevice.openApp(q)
          ? InstalledApp(label: query.trim(), packageName: '')
          : null;
    }
    final apps = await getInstalledApps();

    final app = matchApp(q, apps);
    return app != null && await _launch(app) ? app : null;
  }

  static const sonaPackage = 'com.ambi.gold_paper_trading';
  static const sonaAliases = {
    'sona',
    'oro',
    'oru',
    'aura',
    'auro',
    'orrow',
    'oro gold'
  };
  static InstalledApp? matchApp(String query, List<InstalledApp> apps) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return null;
    // Alias is authoritative, including when the target is absent. Never fall
    // through to another installed app with a vaguely similar label/package.
    if (sonaAliases.contains(q)) {
      for (final app in apps) {
        if (app.packageName == sonaPackage) return app;
      }
      return null;
    }
    final exact = apps
        .where((a) =>
            a.label.toLowerCase() == q || a.packageName.toLowerCase() == q)
        .toList();
    if (exact.length == 1) return exact.single;
    if (exact.length > 1) return null;
    // Conservative whole-word partial labels only, no package substrings or
    // edit-distance guesses. All requested words and at least 2/3 label words.
    final words =
        q.split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty).toSet();
    if (q.length < 4 || words.isEmpty) return null;
    final candidates = apps.where((a) {
      final labelWords = a.label
          .toLowerCase()
          .split(RegExp(r'[^a-z0-9]+'))
          .where((w) => w.isNotEmpty)
          .toSet();
      return words.every(labelWords.contains) &&
          words.length / labelWords.length >= 0.66;
    }).toList();
    return candidates.length == 1 ? candidates.single : null;
  }

  Future<bool> _launch(InstalledApp app) async {
    try {
      return await _channel.invokeMethod<bool>(
            'openApp',
            <String, dynamic>{'package': app.packageName},
          ) ??
          false;
    } on Exception {
// ignore: unreachable_switch_case

      return false;
    }
  }
}
