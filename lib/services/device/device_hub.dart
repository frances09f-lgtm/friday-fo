import 'package:flutter/services.dart';

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
    } on PlatformException {
      return const [];
    }
  }

  Future<bool> hasSmsPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasSmsPermission') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> requestSmsPermission() async {
    try {
      await _channel.invokeMethod<bool>('requestSmsPermission');
    } on PlatformException {
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
    } on PlatformException {
      return const [];
    }
  }

  /// Fuzzy-matches the app the user (or the model) named against the
  /// installed list, then launches it. Returns the app label, or null when
  /// nothing on the phone matches.
  Future<InstalledApp?> openAppByName(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return null;
    final apps = await getInstalledApps();

    for (final app in apps) {
      if (app.label.toLowerCase() == q ||
          app.packageName.toLowerCase() == q) {
        return await _launch(app) ? app : null;
      }
    }
    for (final app in apps) {
      if (app.label.toLowerCase().contains(q) ||
          app.packageName.toLowerCase().contains(q)) {
        return await _launch(app) ? app : null;
      }
    }
    // Word overlap: "play store" matches "Play Store".
    final words = q.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
    if (words.isNotEmpty) {
      for (final app in apps) {
        final label = app.label.toLowerCase();
        if (words.every(label.contains)) {
          return await _launch(app) ? app : null;
        }
      }
    }
    return null;
  }

  Future<bool> _launch(InstalledApp app) async {
    try {
      return await _channel.invokeMethod<bool>(
            'openApp',
            <String, dynamic>{'package': app.packageName},
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }
}
