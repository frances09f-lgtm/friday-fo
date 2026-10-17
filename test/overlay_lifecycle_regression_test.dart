import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:friday/assistant_overlay.dart';
import 'package:friday/services/ai/ai_brain.dart';
import 'package:friday/services/ai/local_model_service.dart';
import 'package:friday/services/device/device_hub.dart';
import 'package:friday/services/device/reminder_service.dart';
import 'package:friday/services/intent_router.dart';
import 'package:friday/services/speech/speech_service.dart';
import 'package:friday/services/storage/chat_store.dart';
import 'package:friday/services/storage/settings_store.dart';
import 'package:friday/state/friday_controller.dart';

class ControlledSpeech extends SpeechService {
  final init = Completer<bool>();
  int starts = 0, stops = 0;
  bool listening = false;
  final results = <void Function(String)>[];
  final completions = <void Function()>[];

  @override
  Future<bool> initSpeech() => init.future;
  @override
  bool get isListening => listening;
  @override
  void startListening(
      {required void Function(String) onResult,
      required void Function() onDone,
      String localeId = 'en_IN'}) {
    starts++;
    listening = true;
    results.add(onResult);
    completions.add(onDone);
  }

  @override
  Future<void> stopListening() async {
    stops++;
    listening = false;
  }
}

class RecordingController extends FridayController {
  final submissions = <String>[];
  Completer<void>? sendGate;
  RecordingController(SharedPreferences prefs, ControlledSpeech speech)
      : super(
            brain: AIBrain(
                settings: SettingsStore(const FlutterSecureStorage(), prefs),
                local: LocalModelService()),
            router: IntentRouter(
                deviceHub: DeviceHub(), reminders: ReminderService()),
            chatStore: ChatStore(prefs),
            speech: speech,
            settings: SettingsStore(const FlutterSecureStorage(), prefs));
  @override
  Future<void> send(String text) async {
    submissions.add(text);
    await sendGate?.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ControlledSpeech speech;
  late RecordingController controller;
  late List<String> platformCalls;
  Future<void> mount(WidgetTester t, {bool voice = true}) async {
    SharedPreferences.setMockInitialValues({});
    speech = ControlledSpeech();
    controller =
        RecordingController(await SharedPreferences.getInstance(), speech);
    platformCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('friday/assistant'),
            (call) async {
      platformCalls.add(call.method);
      return call.method == 'launchMode' ? {'voice': voice} : null;
    });
    await t.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<FridayController>.value(value: controller),
      Provider<SpeechService>.value(value: speech),
    ], child: const AssistantOverlayApp()));
    await t.pump(const Duration(milliseconds: 300));
  }

  Future<void> unmount(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump();
  }

  testWidgets('closing while speech initializes never starts microphone later',
      (t) async {
    await mount(t);
    await t.tap(find.byTooltip('Close Friday'));
    await t.pump();
    speech.init.complete(true);
    await t.pump();
    expect(speech.starts, 0);
    await unmount(t);
  });
  testWidgets('disposing while speech initializes ignores its late completion',
      (t) async {
    await mount(t);
    await unmount(t);
    speech.init.complete(true);
    await t.pump();
    expect(speech.starts, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets('late final recognition after close never dispatches a request',
      (t) async {
    await mount(t);
    speech.init.complete(true);
    await t.pump();
    expect(speech.starts, 1);
    await t.tap(find.byTooltip('Close Friday'));
    await t.pump();
    speech.results.single('open camera');
    speech.completions.single();
    await t.pump();
    expect(controller.submissions, isEmpty);
    expect(controller.partialHeard, isEmpty);
    await unmount(t);
  });
  testWidgets('dispose stops microphone and ignores late recognition callbacks',
      (t) async {
    await mount(t);
    speech.init.complete(true);
    await t.pump();
    await unmount(t);
    speech.results.single('open camera');
    speech.completions.single();
    await t.pump();
    expect(speech.stops, greaterThan(0));
    expect(controller.submissions, isEmpty);
    expect(controller.partialHeard, isEmpty);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'busy keyboard send retains the draft instead of silently deleting it',
      (t) async {
    await mount(t, voice: false);
    controller.busy = true;
    await t.enterText(find.byType(TextField), 'next request');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pump();
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text,
        'next request');
    expect(controller.submissions, isEmpty);
    await unmount(t);
  });
  testWidgets('a fresh recognition session cannot resubmit a previous partial',
      (t) async {
    await mount(t, voice: false);
    controller.setPartialHeard('old request');
    speech.init.complete(true);
    await t.tap(find.byTooltip('Talk to Friday'));
    await t.pump();
    speech.completions.single();
    await t.pump();
    expect(controller.submissions, isEmpty);
    await unmount(t);
  });
  testWidgets(
      'duplicate final callback dispatches a recognition result only once',
      (t) async {
    await mount(t);
    speech.init.complete(true);
    await t.pump();
    speech.results.single('open camera');
    speech.completions.single();
    await t.pump();
    speech.completions.single();
    await t.pump();
    expect(controller.submissions, ['open camera']);
    await unmount(t);
  });
  testWidgets(
      'starting mic repeatedly during initialization starts only one session',
      (t) async {
    await mount(t, voice: false);
    await t.tap(find.byTooltip('Talk to Friday'));
    await t.tap(find.byTooltip('Talk to Friday'));
    speech.init.complete(true);
    await t.pump();
    expect(speech.starts, 1);
    await unmount(t);
  });
  testWidgets('recognition cannot start while controller is busy', (t) async {
    await mount(t, voice: false);
    controller.busy = true;
    speech.init.complete(true);
    await t.tap(find.byTooltip('Talk to Friday'));
    await t.pump();
    expect(speech.starts, 0);
    await unmount(t);
  });
  testWidgets(
      'accepted request finishes after immediate dismissal without replay',
      (t) async {
    await mount(t, voice: false);
    controller.sendGate = Completer<void>();
    await t.enterText(find.byType(TextField), 'open camera');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pump();
    expect(controller.submissions, ['open camera']);
    await t.tap(find.byTooltip('Close Friday'));
    await t.pump();
    expect(platformCalls, contains('hidePanelWhileBusy'));
    expect(platformCalls, isNot(contains('dismiss')));
    controller.sendGate!.complete();
    await t.pump();
    expect(platformCalls, contains('dismiss'));
    expect(controller.submissions, ['open camera']);
    await unmount(t);
  });
  testWidgets('old session callbacks cannot replace or submit a newer session',
      (t) async {
    await mount(t, voice: false);
    speech.init.complete(true);
    await t.tap(find.byTooltip('Talk to Friday'));
    await t.pump();
    speech.listening = false;
    controller.setPartialHeard('');
    await t.pump();
    await t.tap(find.byTooltip('Talk to Friday'));
    await t.pump();
    speech.results.last('new request');
    speech.results.first('old request');
    speech.completions.first();
    await t.pump();
    expect(controller.partialHeard, 'new request');
    expect(controller.submissions, isEmpty);
    speech.completions.last();
    await t.pump();
    expect(controller.submissions, ['new request']);
    await unmount(t);
  });
  testWidgets('busy send teardown retains a second typed draft', (t) async {
    await mount(t, voice: false);
    controller.sendGate = Completer<void>();
    await t.enterText(find.byType(TextField), 'first request');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pump();
    await t.enterText(find.byType(TextField), 'second request');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pump();
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text,
        'second request');
    expect(controller.submissions, ['first request']);
    controller.sendGate!.complete();
    await t.pump();
    await unmount(t);
  });
  testWidgets('failed recognizer initialization still permits typed input',
      (t) async {
    await mount(t);
    speech.init.completeError(StateError('synthetic recognizer unavailable'));
    await t.pump();
    await t.enterText(find.byType(TextField), 'typed request');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pump();
    expect(controller.submissions, ['typed request']);
    expect(t.takeException(), isNull);
    await unmount(t);
  });
  testWidgets(
      'busy state acquired during initialization prevents microphone start',
      (t) async {
    await mount(t);
    controller.busy = true;
    speech.init.complete(true);
    await t.pump();
    expect(speech.starts, 0);
    await unmount(t);
  });
  Future<void> submit(WidgetTester t) async {
    await t.enterText(find.byType(TextField), 'open camera');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pump();
  }

  testWidgets(
      'terminal command hides within one frame before slow speech finishes',
      (t) async {
    await mount(t, voice: false);
    controller.sendGate = Completer<void>();
    await submit(t);
    controller.busy = true;
    controller.setPartialHeard('working');
    await t.pump(const Duration(seconds: 5));
    expect(platformCalls, isNot(contains('hidePanelWhileBusy')));
    controller.completedCommandRevision++;
    controller.busy = false;
    controller.setPartialHeard('');
    await t.pump();
    expect(platformCalls.where((v) => v == 'hidePanelWhileBusy'), hasLength(1));
    expect(platformCalls, isNot(contains('dismiss')));
    controller.setPartialHeard(''); // duplicate terminal notification
    await t.pump();
    expect(platformCalls.where((v) => v == 'hidePanelWhileBusy'), hasLength(1));
    controller.sendGate!.complete();
    await t.pump();
    expect(platformCalls, contains('dismiss'));
    await unmount(t);
  });
  testWidgets(
      'error and unanswered confirmation stay visible with no close timer',
      (t) async {
    await mount(t, voice: false);
    await submit(t);
    await t.pump(const Duration(seconds: 95));
    expect(platformCalls, isNot(contains('hidePanelWhileBusy')));
    expect(platformCalls, isNot(contains('dismiss')));
    await unmount(t);
  });
  testWidgets('old completion after panel replacement cannot dismiss new panel',
      (t) async {
    await mount(t, voice: false);
    final old = controller;
    old.sendGate = Completer<void>();
    await submit(t);
    await unmount(t);
    await mount(t, voice: false);
    old.completedCommandRevision++;
    old.sendGate!.complete();
    old.setPartialHeard('');
    await t.pump();
    expect(platformCalls, isNot(contains('dismiss')));
    expect(platformCalls, isNot(contains('hidePanelWhileBusy')));
    expect(t.takeException(), isNull);
    await unmount(t);
  });
}
