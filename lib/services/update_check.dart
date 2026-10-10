import 'dart:convert';
import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const fridayLatestReleaseApi =
    'https://api.github.com/repos/frances09f-lgtm/friday-fo/releases/latest';
const fridayUpdatePage =
    'https://appdistribution.firebase.google.com/testerapps/1:509368336413:android:bdf178861eee975f0a46f4';
typedef BuildReader = Future<int?> Function();

int? releaseBuild(Map<String, dynamic> data) {
  if (data['draft'] != false || data['prerelease'] != false) return null;
  final tag = data['tag_name'];
  if (tag is! String) return null;
  final match = RegExp(r'^v([1-9][0-9]*)$').firstMatch(tag);
  return match == null ? null : int.tryParse(match.group(1)!);
}

Future<int?> fetchFridayLatestBuild() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client
        .getUrl(Uri.parse(fridayLatestReleaseApi))
        .timeout(const Duration(seconds: 8));
    request.followRedirects = false;
    request.headers.set('Accept', 'application/vnd.github+json');
    request.headers.set('User-Agent', 'com.friday.assistant');
    final response = await request.close().timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 8))) {
      bytes.addAll(chunk);
      if (bytes.length > 256 * 1024) return null;
    }
    final data = jsonDecode(utf8.decode(bytes));
    return data is Map<String, dynamic> ? releaseBuild(data) : null;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

class FridayUpdateCheck {
  static const checkedKey = 'friday_update_checked_at';
  static const laterKey = 'friday_update_later_until';
  static const every = Duration(hours: 6);
  static const snooze = Duration(hours: 12);
  static bool _busy = false;
  static Future<void> Function() opener = () => const AndroidIntent(
        action: 'android.intent.action.VIEW',
        data: fridayUpdatePage,
      ).launch();
  static Future<int?> installedBuild() => const MethodChannel('friday/device')
      .invokeMethod<int>('installedBuildNumber');

  static Future<void> run(
    BuildContext context, {
    BuildReader latest = fetchFridayLatestBuild,
    BuildReader installed = installedBuild,
    SharedPreferences? preferences,
  }) async {
    if (_busy) return;
    _busy = true;
    try {
      final prefs = preferences ?? await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = prefs.getInt(checkedKey) ?? 0;
      if ((now >= last && now - last < every.inMilliseconds) ||
          now < (prefs.getInt(laterKey) ?? 0)) {
        return;
      }
      final current = await installed();
      if (current == null || current <= 0) return;
      await prefs.setInt(checkedKey, now);
      final available = await latest();
      if (available == null || available <= current || !context.mounted) return;
      final update = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
                title: const Text('New version available'),
                content: Text(
                    'Friday v$available is ready. Update through Firebase App Tester.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('Later')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('Update')),
                ],
              ));
      if (update == true) {
        try {
          await opener();
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text(
                      'Could not open Firebase App Tester. Open it to update Friday.')),
            );
          }
        }
      } else {
        await prefs.setInt(laterKey,
            DateTime.now().millisecondsSinceEpoch + snooze.inMilliseconds);
      }
    } catch (_) {
      // No keys/logs/release URLs retained. Offline Friday remains usable.
    } finally {
      _busy = false;
    }
  }
}
