import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:friday/services/ai/offline_engine.dart';
import 'package:friday/models/friday_response.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:friday/services/ai/ai_brain.dart';
import 'package:friday/services/ai/local_model_service.dart';
import 'package:friday/services/device/device_hub.dart';
import 'package:friday/services/device/reminder_service.dart';
import 'package:friday/services/intent_router.dart';
import 'package:friday/services/speech/speech_service.dart';
import 'package:friday/services/storage/chat_store.dart';
import 'package:friday/services/storage/settings_store.dart';
import 'package:friday/state/friday_controller.dart';
import 'package:friday/assistant_overlay.dart';

class QuietSpeech extends SpeechService {
  final List<String> stages;
  QuietSpeech(this.stages);
  @override
  Future<void> stopListening() async {
    stages.add('stopped');
  }

  @override
  Future<void> speak(String text, {String locale = 'en-IN'}) async {}
}

class TestAndroidRouter extends IntentRouter {
  TestAndroidRouter()
      : super(deviceHub: DeviceHub(), reminders: ReminderService());
  @override
  Future<String> executeAll(List<FridayAction> actions) async {
    expect(actions.length, 1);
    expect(actions.single.type, FridayActionType.setVolume);
    expect(actions.single.target, '40');
    return deviceHub.verifiedVolumeSet(int.parse(actions.single.target));
  }
}

void main() {
  test('empty or bare completion cannot prove volume', () {
    for (final v in [null, '', 'done', 'Done.', 'ok', 'success']) {
      expect(DeviceHub.volumeEvidence(v), contains('No success claimed'));
    }
  });
  test('exact bar percentage parsing reaches target 40', () {
    expect(
        const OfflineEngine().handle('Set volume to 40').action.target, '40');
  });
  testWidgets(
      'Set volume to 40 from bar stops input and retains measured result',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    final s = SettingsStore(const FlutterSecureStorage(), p);
    await s.setSpeakReplies(false);
    final stages = <String>[];
    final speech = QuietSpeech(stages);
    final c = FridayController(
        brain: AIBrain(settings: s, local: LocalModelService()),
        router: TestAndroidRouter(),
        chatStore: ChatStore(p),
        speech: speech,
        settings: s);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('friday/assistant'),
            (call) async =>
                call.method == 'launchMode' ? {'voice': false} : null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('friday/device'),
            (call) async {
      expect(call.method, 'volumeSetVerified');
      expect(call.arguments, {'percent': 40});
      expect(stages, ['stopped']);
      stages.add('write');
      return 'Media volume not verified. No success claimed. Friday 1.0.108; media stream; requested 40; before 10/15; target 6/15; audio mode 0; output types 2. Readbacks 10/15, 10/15; route stable. This is phone media volume, not a remote cast speaker’s volume.';
    });
    await t.runAsync(() async {
      await (FontLoader('Roboto')
            ..addFont(Future.value(ByteData.sublistView(
                await File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')
                    .readAsBytes()))))
          .load();
    });
    await t.runAsync(() async {
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(ByteData.sublistView(await File(
                    '${Platform.environment['FLUTTER_ROOT'] ?? '/home/sandbox/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
                .readAsBytes()))))
          .load();
    });
    final key = GlobalKey();
    await t.binding.setSurfaceSize(const Size(412, 360));
    await t.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider.value(value: c),
      Provider<SpeechService>.value(value: speech)
    ], child: RepaintBoundary(key: key, child: const AssistantOverlayApp())));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Set volume to 40');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pumpAndSettle();
    expect(stages, ['stopped', 'write'],
        reason: c.messages.map((m) => m.text).join('|'));
    expect(c.messages.last.text, contains('No success claimed'));
    expect(c.messages.last.text, isNot('Done.'));
    expect(t.takeException(), isNull);
    await t.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/friday-v49-volume-bar.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    });
  });
}
