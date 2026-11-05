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
import 'package:friday/ui/screens/home_screen.dart';
import 'package:friday/ui/stitch_style.dart';
import 'package:friday/ui/widgets/listening_bubble.dart';

class DraftSpeech extends SpeechService {
  bool active = false;
  void Function(String)? result;
  void Function()? done;
  @override
  Future<bool> initSpeech() async => true;
  @override
  bool get isListening => active;
  @override
  void startListening(
      {required void Function(String) onResult,
      required void Function() onDone,
      String localeId = ''}) {
    active = true;
    result = onResult;
    done = onDone;
  }

  @override
  Future<void> stopListening() async {
    active = false;
    done?.call();
  }
}

void main() {
  for (final dark in [true, false]) {
    testWidgets('voice bubble lifecycle and visual dark=$dark', (t) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsStore(const FlutterSecureStorage(), prefs);
      final speech = DraftSpeech();
      final c = FridayController(
          brain: AIBrain(settings: settings, local: LocalModelService()),
          router: IntentRouter(
              deviceHub: DeviceHub(), reminders: ReminderService()),
          chatStore: ChatStore(prefs),
          speech: speech,
          settings: settings);
      await t.runAsync(() async {
        for (final e in {
          'Roboto': 'assets/fonts/Inter.ttf',
          'Inter': 'assets/fonts/Inter.ttf',
          'SpaceGrotesk': 'assets/fonts/SpaceGrotesk.ttf',
          'JetBrainsMono': 'assets/fonts/JetBrainsMono.ttf',
          'MaterialIcons':
              '${Platform.environment['FLUTTER_ROOT'] ?? '/tmp/flutter-sdk'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
        }.entries) {
          final l = FontLoader(e.key)
            ..addFont(Future.value(
                ByteData.sublistView(await File(e.value).readAsBytes())));
          await l.load();
        }
      });
      await t.binding.setSurfaceSize(const Size(412, 892));
      final key = GlobalKey();
      await t.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<FridayController>.value(value: c),
            Provider<SpeechService>.value(value: speech)
          ],
          child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: ThemeData(
                      brightness: dark ? Brightness.dark : Brightness.light),
                  home: const HomeScreen()))));
      await t.pumpAndSettle();
      Future<void> shot(String stage) async {
        await t.pump(const Duration(milliseconds: 400));
        await t.runAsync(() async {
          final im = await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
          final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/friday168-$stage-${dark ? 'dark' : 'light'}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          im.dispose();
        });
      }

      await t.tap(find.byTooltip('Push to talk'));
      await t.pump();
      expect(find.text('Listening'), findsOneWidget);
      expect(find.byType(ListeningBubble), findsOneWidget);
      expect(c.messages, isEmpty);
      await shot('listening');
      speech.result!('Remind me to stretch in thirty');
      await t.pump();
      expect(find.text('Listening'), findsNothing);
      expect(
          find.textContaining('Remind me to stretch in thirty',
              findRichText: true),
          findsOneWidget);
      expect(speech.isListening, isTrue);
      expect(c.messages, isEmpty);
      await shot('speaking');
      speech.result!(
          'Remind me to stretch in thirty minutes and then remind me to drink water after lunch tomorrow');
      await t.pump();
      expect(t.takeException(), isNull);
      await shot('long');
      final stale = speech.result!;
      await t.tap(find.byTooltip('Cancel listening'));
      await t.pump();
      expect(find.byType(ListeningBubble), findsNothing);
      expect(c.partialHeard, isEmpty);
      expect(c.messages, isEmpty);
      stale('late buy');
      await t.pump();
      expect(c.partialHeard, isEmpty);
      expect(c.messages, isEmpty);
      await t.tap(find.byTooltip('Push to talk'));
      await t.pump();
      speech.result!('unconfirmed partial');
      speech.lastSttError = 'Voice input stopped.';
      speech.done!();
      await t.pump();
      expect(find.byType(ListeningBubble), findsNothing);
      expect(c.messages, isEmpty);
      expect(c.partialHeard, isEmpty);
      speech.lastSttError = null;
      await t.tap(find.byTooltip('Push to talk'));
      await t.pump();
      speech.done!();
      await t.pump();
      expect(find.byType(ListeningBubble), findsNothing);
      expect(c.messages, isEmpty);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.binding.setSurfaceSize(null);
    });
  }
}
