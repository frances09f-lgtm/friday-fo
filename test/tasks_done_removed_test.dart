import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/tasks/task_service.dart';
import 'package:friday/ui/screens/background_tasks_screen.dart';

class _Tasks extends TaskService {
  List<Map<String, dynamic>> tasks;
  _Tasks(this.tasks);
  @override
  Future<Map<String, dynamic>> state() async =>
      {'mode': 'foreground', 'runtime': 'Foreground checker running', 'tasks': tasks};
}

Map<String, dynamic> _t(String id, String status, num threshold) => {
      'id': id,
      'direction': 'below',
      'threshold': threshold,
      'status': status,
      'intervalMinutes': 5,
      'lastOutcome': 'x',
    };

void main() {
  test('openTasks keeps active and blocked, drops done', () {
    final open = openTasks({
      'tasks': [
        _t('a', 'active', 1),
        _t('b', 'completed', 2),
        _t('c', 'cancelled', 3),
        _t('d', 'expired', 4),
        _t('e', 'blocked', 5),
      ]
    });
    expect(open.map((t) => t['id']), ['a', 'e']);
    expect(openTasks(null), isEmpty);
    expect(isDoneTask({'status': 'Completed'}), isTrue);
    expect(isDoneTask({'status': 'active'}), isFalse);
  });

  testWidgets('done tasks leave the Tasks page on their own', (t) async {
    await t.binding.setSurfaceSize(const Size(412, 2000));
    final svc = _Tasks([
      _t('a', 'active', 4150),
      _t('b', 'completed', 4200),
      _t('c', 'cancelled', 4300),
    ]);
    await t.pumpWidget(MaterialApp(home: BackgroundTasksScreen(service: svc)));
    await t.pump();
    expect(find.text('Gold below 4150'), findsOneWidget);
    expect(find.text('Gold below 4200'), findsNothing);
    expect(find.text('Gold below 4300'), findsNothing);
    expect(find.text('completed'), findsNothing);

    // The alert fires in the background: the task completes.
    svc.tasks = [_t('a', 'completed', 4150)];
    await t.pump(BackgroundTasksScreen.refreshEvery + const Duration(seconds: 1));
    await t.pump();
    expect(find.text('Gold below 4150'), findsNothing);
    expect(find.text('No active tasks.'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
