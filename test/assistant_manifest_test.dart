import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('assistant gesture starts overlay directly with diagnostic evidence',
      () {
    final s = File(
            'android/app/src/main/kotlin/com/friday/assistant/FridayAssistantService.kt')
        .readAsStringSync();
    expect(s, contains('setUiEnabled(false)'));
    expect(
        s,
        contains(
            'AssistantInvocation.start(context,"System assistant gesture'));
    expect(s, contains('ContextCompat.startForegroundService'));
    expect(s, contains('System created assistant session'));
  });
  test('native overlay entrypoint is retained in main Dart library', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains("import 'assistant_overlay.dart' as overlay;"));
    expect(main, contains("@pragma('vm:entry-point')"));
    expect(
        main,
        contains(
            'Future<void> assistantOverlayMain() => overlay.assistantOverlayMain();'));
  });
  test('assistant session specified by metadata must be declared and protected',
      () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final xml =
        File('android/app/src/main/res/xml/voice_interaction_service.xml')
            .readAsStringSync();
    final name =
        RegExp('android:sessionService="([^"]+)"').firstMatch(xml)!.group(1)!;
    expect(name, startsWith('com.friday.assistant.'));
    expect(
        xml,
        contains(
            'android:recognitionService="com.friday.assistant.FridayRecognitionService"'));
    final service = RegExp(
            '<service\\s[^>]*android:name="${RegExp.escape(name)}"[^>]*>',
            dotAll: true)
        .firstMatch(manifest);
    expect(service, isNotNull);
    expect(service!.group(0),
        contains('android.permission.BIND_VOICE_INTERACTION'));
  });
}
