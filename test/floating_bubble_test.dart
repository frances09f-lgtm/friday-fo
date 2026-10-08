import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:friday/services/storage/chat_store.dart';

void main() {
  test('overlay chat cannot overwrite full-app history', () async {
    SharedPreferences.setMockInitialValues(
        {'friday_chat_log': 'existing conversation'});
    final p = await SharedPreferences.getInstance();
    await ChatStore(p, storageKey: 'friday_overlay_log').save([]);
    expect(p.getString('friday_chat_log'), 'existing conversation');
    expect(p.getString('friday_overlay_log'), '[]');
  });
  test('global bubble reuses overlay service and distinguishes tap from hold',
      () {
    final s = File(
            'android/app/src/main/kotlin/com/friday/assistant/AssistantOverlayService.kt')
        .readAsStringSync();
    for (final t in [
      'TYPE_APPLICATION_OVERLAY',
      'showPanel(false)',
      'showPanel(true)',
      'postDelayed(hold!!,600)',
      'openFriday();showBubble()',
      'Settings.canDrawOverlays',
      'START_NOT_STICKY',
      'clearBubble();clearPanel()'
    ]) expect(s, contains(t));
    final d =
        File('android/app/src/main/kotlin/com/friday/assistant/DeviceBridge.kt')
            .readAsStringSync();
    expect(d, contains('permission_required'));
    expect(d, contains('"bubbleStop"'));
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(
        'android:name=".AssistantOverlayService"'.allMatches(manifest).length,
        1);
  });
}
