import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/tasks/task_service.dart';
import 'package:friday/ui/screens/background_tasks_screen.dart';

class PreviewTasks extends TaskService {
  @override
  Future<Map<String, dynamic>> state() async => {
        'mode': 'foreground',
        'runtime': 'Foreground checker running',
        'tasks': [
          {
            'direction': 'below',
            'threshold': 4150,
            'status': 'active',
            'intervalMinutes': 5,
            'lastOutcome': 'Oro quote is old; waiting for Oro to update'
          }
        ]
      };
}

void main() {
  testWidgets('task state and honest source caveat fit on a phone', (t) async {
    await t.runAsync(() async {
      final font = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
      if (await font.exists()) {
        final loader = FontLoader('Roboto')
          ..addFont(
              Future.value(ByteData.sublistView(await font.readAsBytes())));
        await loader.load();
      }
    });
    await t.binding.setSurfaceSize(const Size(412, 915));
    final key = GlobalKey();
    await t.pumpWidget(MaterialApp(
        home: RepaintBoundary(
            key: key, child: BackgroundTasksScreen(service: PreviewTasks()))));
    await t.pumpAndSettle();
    expect(find.text('Battery saver'), findsOneWidget);
    expect(find.textContaining('active | every 5 min'), findsOneWidget);
    expect(find.textContaining('old quotes cannot trigger'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/background-tasks.png')
          .writeAsBytes(data!.buffer.asUint8List());
    });
  });
}
