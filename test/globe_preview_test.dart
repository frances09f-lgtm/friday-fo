// Actual changed Friday UI, rendered with explicitly simulated voice states.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:friday/services/link/device_link.dart';
import 'package:friday/ui/responsive_globe.dart';
import 'package:friday/app.dart';

class PreviewSpeech extends SpeechService {
  bool active = false;
  int starts = 0;
  @override
  Future<bool> initSpeech() async => true;
  @override
  bool get isListening => active;
  @override
  void startListening(
      {required void Function(String) onResult,
      required void Function() onDone,
      String localeId = 'en_IN'}) {
    starts++;
    active = true;
    activity.value = SpeechActivity.listening;
  }

  @override
  Future<void> stopListening() async {
    active = false;
    activity.value = SpeechActivity.idle;
  }

  @override
  Future<void> stopSpeaking() async {
    activity.value = SpeechActivity.idle;
  }
}

class PreviewController extends FridayController {
  PreviewController(SharedPreferences prefs, PreviewSpeech speech,
      SettingsStore settings, LocalModelService local)
      : super(
            brain: AIBrain(settings: settings, local: local),
            router: IntentRouter(
                deviceHub: DeviceHub(), reminders: ReminderService()),
            chatStore: ChatStore(prefs),
            speech: speech,
            settings: settings);
  void working(bool value) {
    busy = value;
    phase = value ? 'Thinking…' : 'Ready';
    notifyListeners();
  }
}

void main() {
  testWidgets('capture genuine Flutter globe interaction preview', (t) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsStore(const FlutterSecureStorage(), prefs);
    final speech = PreviewSpeech(), local = LocalModelService();
    final controller = PreviewController(prefs, speech, settings, local);
    await t.runAsync(() async {
      for (final name in ['Inter', 'SpaceGrotesk', 'JetBrainsMono']) {
        final l = FontLoader(name)
          ..addFont(Future.value(ByteData.sublistView(
              await File('assets/fonts/$name.ttf').readAsBytes())));
        await l.load();
      }
      final icons = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(await File(
                '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
            .readAsBytes())));
      await icons.load();
    });
    final out =
        Directory(Platform.environment['GLOBE_OUTPUT'] ?? '/tmp/friday-globe')
          ..createSync(recursive: true);
    await t.binding.setSurfaceSize(const Size(412, 892));
    final key = GlobalKey();
    await t.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<FridayController>.value(value: controller),
      Provider<SpeechService>.value(value: speech),
      ChangeNotifierProvider<SettingsStore>.value(value: settings),
      ChangeNotifierProvider<LocalModelService>.value(value: local),
      ChangeNotifierProvider<DeviceLink>(create: (_) => DeviceLink()),
    ], child: RepaintBoundary(key: key, child: const FridayApp())));
    await t.pumpAndSettle();
    var frame = 0;
    Future<void> capture(String stage, int frames) async {
      for (var i = 0; i < frames; i++) {
        await t.pump(const Duration(milliseconds: 83));
        expect(t.takeException(), isNull);
        await t.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1.5);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
                  '${out.path}/frame-${(frame++).toString().padLeft(3, '0')}-$stage.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    }

    await capture('idle', 8);
    await t.tap(find.byType(ResponsiveGlobe));
    await capture('listening', 20);
    expect(speech.starts, 1);
    await speech.stopListening();
    controller.working(true);
    await capture('thinking', 20);
    controller.working(false);
    speech.activity.value = SpeechActivity.speaking;
    await capture('speaking', 20);
    // Tap stops only speech, never starts another microphone session.
    await t.tap(find.byType(ResponsiveGlobe));
    await t.pump();
    expect(speech.starts, 1);
    final origin = t.getCenter(find.byType(ResponsiveGlobe));
    final gesture = await t.startGesture(origin);
    await gesture.moveBy(const Offset(22, 0));
    await t.pump();
    for (var i = 0; i < 18; i++) {
      await gesture.moveBy(const Offset(7, -1));
      await capture('drag-to-rotate', 1);
    }
    await gesture.up();
    await t.pump();
    expect(speech.starts, 1);
    await capture('idle-after-drag', 8);
    await t.pumpWidget(const SizedBox());
    await t.binding.setSurfaceSize(null);
  });
}
