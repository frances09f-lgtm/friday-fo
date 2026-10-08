import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:friday/services/agent/friday_agent.dart';
import 'package:friday/services/agent/agent_contract.dart';
import 'package:friday/ui/screens/agent_mode_screen.dart';

class NoBrain implements AgentBrain {
  @override
  Future<AgentAction> decide(
          AgentGoal g, Map<String, dynamic> s, List<String> h) async =>
      AgentAction(action: 'ask_confirmation');
}

class NoDevice implements AgentDevice {
  @override
  Future<Map<String, dynamic>> call(String m,
          [Map<String, dynamic> a = const {}]) async =>
      {'success': false};
}

void main() {
  testWidgets('agent mode shows real scope and visible stop while running',
      (t) async {
    await t.runAsync(() async {
      final f = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
      await (FontLoader('Roboto')
            ..addFont(
                Future.value(ByteData.sublistView(await f.readAsBytes()))))
          .load();
      final icon = File(
          '${Platform.environment['FLUTTER_ROOT'] ?? '/home/sandbox/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
      await (FontLoader('MaterialIcons')
            ..addFont(
                Future.value(ByteData.sublistView(await icon.readAsBytes()))))
          .load();
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('friday/agent'),(call)async=>{'version':'1.0.83','build':83});
    await t.binding.setSurfaceSize(const Size(412, 1050));
    final key = GlobalKey();
    final a = FridayAgent(brain: NoBrain(), device: NoDevice());
    await t.pumpWidget(ChangeNotifierProvider.value(
        value: a,
        child: RepaintBoundary(
            key: key,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData.dark(useMaterial3: true),
                home: const AgentModeScreen()))));
    await t.pumpAndSettle();
    expect(find.text('Enable Friday Accessibility'), findsOneWidget);
    a.running = true;
    a.phase = 'Observing screen';
    a.notifyListeners();
    await t.pumpAndSettle();
    expect(find.text('STOP'), findsNWidgets(2));
    a.running = false;
    a.phase = 'Stopped';
    a.result = 'Local model output rejected. Open Rejected model output below.';
    a.lastAction=AgentAction(action:'ask_confirmation',confidence:0.9,reason:'Need an observed search field');
    a.rejectedOutput =
        'Attempt 1: Unknown action\nUNTRUSTED MODEL OUTPUT:\n{"action":"open_app|tap"}';
    a.notifyListeners();
    await t.pumpAndSettle();
    expect(find.text('Rejected model output'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
    await t.runAsync(() async {
      final im = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final b = await im.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/friday-agent-mode.png')
          .writeAsBytes(b!.buffer.asUint8List());
    });
  });
}
