import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
