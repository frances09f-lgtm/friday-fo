import 'package:flutter/material.dart';
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
import 'package:friday/models/chat_message.dart';

class SilentSpeech extends SpeechService {
  @override
  Future<bool> initSpeech() async => false;
}

void main() {
  late FridayController controller;
  late SilentSpeech speech;
  late ChatStore store;

  ChatMessage message(int i, {String? text}) => ChatMessage(
        id: 'message-$i',
        role: MessageRole.user,
        text: text ??
            'Message $i\n${'Variable height saved text.\n' * (i % 9 + 1)}',
        at: DateTime(2026),
      );

  Widget root({Widget? home}) => MultiProvider(
        providers: [
          ChangeNotifierProvider<FridayController>.value(value: controller),
          Provider<SpeechService>.value(value: speech),
        ],
        child: MaterialApp(home: home ?? const HomeScreen()),
      );

  ListView list(WidgetTester t) => t.widget<ListView>(find.byType(ListView));
  void append(ChatMessage m) {
    controller.messages.add(m);
    controller.notifyListeners();
  }

  void expectLatestVisible(WidgetTester t, String text) {
    expect(find.text(text).hitTestable(), findsOneWidget);
    final viewport = t.getRect(find.byType(ListView));
    final latest = t.getRect(find.text(text));
    expect(latest.bottom, lessThanOrEqualTo(viewport.bottom));
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsStore(const FlutterSecureStorage(), prefs);
    speech = SilentSpeech();
    store = ChatStore(prefs);
    controller = FridayController(
      brain: AIBrain(settings: settings, local: LocalModelService()),
      router:
          IntentRouter(deviceHub: DeviceHub(), reminders: ReminderService()),
      chatStore: store,
      speech: speech,
      settings: settings,
    );
  });

  testWidgets(
      'opens long variable-height saved history at the actual latest message',
      (t) async {
    controller.messages.addAll(List.generate(199, message));
    controller.messages.add(message(199, text: 'Actual newest saved message'));
    await t.pumpWidget(root());
    await t.pumpAndSettle();
    expectLatestVisible(t, 'Actual newest saved message');
    expect(find.text(controller.messages.first.text), findsNothing);
  });

  testWidgets(
      'lands at latest when saved history arrives after the first frame',
      (t) async {
    await store.save([
      ...List.generate(199, message),
      message(199, text: 'Newest loaded asynchronously'),
    ]);
    await t.pumpWidget(root());
    await t.pumpAndSettle();
    expect(find.text('Start a conversation'), findsOneWidget);
    await controller.loadHistory();
    await t.pumpAndSettle();
    expectLatestVisible(t, 'Newest loaded asynchronously');
  });

  testWidgets('follows new replies but leaves manual history reading alone',
      (t) async {
    controller.messages.addAll(List.generate(100, message));
    await t.pumpWidget(root());
    await t.pumpAndSettle();
    append(message(100, text: 'New reply at bottom'));
    await t.pumpAndSettle();
    expectLatestVisible(t, 'New reply at bottom');
    await t.drag(find.byType(ListView), const Offset(0, 500));
    await t.pumpAndSettle();
    final scroll = list(t).controller!;
    final before = scroll.offset;
    expect(before, greaterThan(80));
    append(message(101, text: 'Reply while reading history'));
    await t.pumpAndSettle();
    expect(scroll.offset, closeTo(before, 1));
    expect(
        find.text('Reply while reading history').hitTestable(), findsNothing);
    // Returning to the bottom enables following subsequent streamed text.
    scroll.jumpTo(scroll.position.minScrollExtent);
    await t.pumpAndSettle();
    controller.messages[controller.messages.length - 1] =
        message(101, text: 'Updated streaming reply\n' * 30);
    controller.notifyListeners();
    await t.pumpAndSettle();
    expect(scroll.position.extentBefore, lessThan(1));
  });

  testWidgets('reopening history does not restore an old scrolled-up offset',
      (t) async {
    controller.messages.addAll(List.generate(199, message));
    controller.messages.add(message(199, text: 'Newest on reopening'));
    await t.pumpWidget(root(home: Builder(builder: (context) {
      return Scaffold(
        body: TextButton(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute<void>(builder: (_) => const HomeScreen())),
          child: const Text('Open chat'),
        ),
      );
    })));
    await t.tap(find.text('Open chat'));
    await t.pumpAndSettle();
    await t.drag(find.byType(ListView), const Offset(0, 600));
    await t.pumpAndSettle();
    Navigator.of(t.element(find.byType(HomeScreen))).pop();
    await t.pumpAndSettle();
    await t.tap(find.text('Open chat'));
    await t.pumpAndSettle();
    expectLatestVisible(t, 'Newest on reopening');
  });

  testWidgets('switching session view to history opens full history at latest',
      (t) async {
    controller.messages.addAll(List.generate(100, message));
    await t.pumpWidget(root(home: const HomeScreen(sessionOnly: true)));
    await t.pumpAndSettle();
    expect(find.text('Your current session appears here.'), findsOneWidget);
    append(message(100, text: 'New session message'));
    await t.pumpAndSettle();
    expectLatestVisible(t, 'New session message');
    await t.pumpWidget(root(home: const HomeScreen()));
    await t.pumpAndSettle();
    expectLatestVisible(t, 'New session message');
  });

  testWidgets('messages stay chronological and newest stays visible on resize',
      (t) async {
    controller.messages.addAll([
      message(0, text: 'Older message'),
      message(1, text: 'Newest short message'),
    ]);
    await t.pumpWidget(root());
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.text('Older message')).dy,
        lessThan(t.getTopLeft(find.text('Newest short message')).dy));
    await t.binding.setSurfaceSize(const Size(360, 450));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpAndSettle();
    expectLatestVisible(t, 'Newest short message');
    expect(t.takeException(), isNull);
  });

  testWidgets('empty and single-message conversations need no scroll retry',
      (t) async {
    await t.pumpWidget(root());
    await t.pumpAndSettle();
    expect(find.text('Start a conversation'), findsOneWidget);
    append(message(0, text: 'Only message'));
    await t.pumpAndSettle();
    expectLatestVisible(t, 'Only message');
    expect(t.takeException(), isNull);
  });
}
