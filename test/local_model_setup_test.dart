import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:friday/services/ai/local_model_service.dart';
import 'package:friday/services/agent/friday_agent.dart';
import 'package:friday/services/agent/agent_contract.dart';
import 'package:friday/ui/screens/local_model_setup_screen.dart';

class IdleBrain implements AgentBrain {
  @override
  Future<AgentAction> decide(
          AgentGoal g, Map<String, dynamic> s, List<String> h) async =>
      AgentAction(action: 'ask_confirmation');
}

class IdleDevice implements AgentDevice {
  @override
  Future<Map<String, dynamic>> call(String m,
          [Map<String, dynamic> a = const {}]) async =>
      {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('catalog pins exact Android file and integrity', () {
    expect(
        LocalModelService.modelUrl, contains(LocalModelService.modelRevision));
    expect(LocalModelService.modelUrl, endsWith('.task'));
    expect(LocalModelService.modelBytes, 546660344);
    expect(LocalModelService.modelSha.length, 64);
  });
  test('storage failure blocks before download and makes no readiness claim',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('friday/device'),
            (call) async => {'freeBytes': 1, 'totalRam': 8000000000});
    final l = LocalModelService();
    expect(await l.downloadGuided(), false);
    expect(l.setupStatus, contains('free storage'));
    expect(l.isReady, false);
    expect(l.setupBusy, false);
  });
  test('setup state blocks inference generation', () async {
    final l = LocalModelService()..setupBusy = true;
    expect(() => l.generate(system: '', userText: 'x'), throwsException);
  });
  testWidgets('guided download shows size progress and cancellation',
      (t) async {
    await t.runAsync(() async {
      final f = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
      await (FontLoader('Roboto')
            ..addFont(
                Future.value(ByteData.sublistView(await f.readAsBytes()))))
          .load();
    });
    final l = LocalModelService();
    await t.binding.setSurfaceSize(const Size(412, 1050));
    final key = GlobalKey();
    await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: l),
          ChangeNotifierProvider.value(
              value: FridayAgent(brain: IdleBrain(), device: IdleDevice()))
        ],
        child: RepaintBoundary(
            key: key,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData.dark(useMaterial3: true),
                home: const LocalModelSetupScreen()))));
    await t.pumpAndSettle();
    expect(find.text('Download and test local model'), findsOneWidget);
    l.setupBusy = true;
    l.downloaded = 120000000;
    l.setupStatus = 'Downloading Qwen 0.5B (547 MB). Keep Friday open.';
    l.notifyListeners();
    await t.pump();
    expect(find.text('Cancel download'), findsOneWidget);
    await t.runAsync(() async {
      final im = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final b = await im.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/friday-model-setup.png')
          .writeAsBytes(b!.buffer.asUint8List());
    });
  });
}
