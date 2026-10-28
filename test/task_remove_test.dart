import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/tasks/task_service.dart';
import 'package:friday/ui/screens/background_tasks_screen.dart';

/// Stands in for the phone's saved task store.
class FakeTasks extends TaskService {
  FakeTasks(this.tasks);
  final List<Map<String, dynamic>> tasks;
  final cancelled = <Map<String, dynamic>>[];
  var cancelAllCalls = 0;
  @override
  Future<Map<String, dynamic>> state() async =>
      {'mode': 'foreground', 'runtime': 'Foreground checker running', 'tasks': [...tasks]};
  @override
  Future<String> cancel(Map task) async {
    final args = cancelArguments(task);
    cancelled.add(args);
    tasks.removeWhere((t) => taskKey(t) == taskKey(task));
    return 'Removed the gold ${task['direction']} ${task['threshold']} task.';
  }
  @override
  Future<String> cancelAll() async {
    cancelAllCalls++;
    tasks.clear();
    return 'Cancelled all gold background tasks.';
  }
}

Map<String, dynamic> gold(String id, String dir, num th) => {
      'id': id, 'direction': dir, 'threshold': th, 'status': 'active',
      'intervalMinutes': 5, 'lastOutcome': 'Waiting for first check'};

Future<FakeTasks> open(WidgetTester t, List<Map<String, dynamic>> tasks) async {
  await t.binding.setSurfaceSize(const Size(412, 2400));
  final fake = FakeTasks(tasks);
  await t.pumpWidget(MaterialApp(home: Scaffold(body: BackgroundTasksScreen(service: fake, embedded: true))));
  await t.pumpAndSettle();
  return fake;
}

void main() {
  group('remove logic', () {
    test('withoutTask drops only the matching task, by id', () {
      final state = {'mode': 'foreground', 'tasks': [gold('a', 'above', 4140), gold('b', 'below', 4150)]};
      final left = withoutTask(state, gold('a', 'above', 4140))!;
      expect((left['tasks'] as List).map((t) => t['id']), ['b']);
      expect(left['mode'], 'foreground');
      expect((state['tasks'] as List).length, 2, reason: 'input is not mutated');
    });
    test('old tasks without an id match on direction and threshold', () {
      final legacy = {'direction': 'above', 'threshold': 4140, 'status': 'active'};
      expect(taskKey(legacy), 'above-4140');
      final left = withoutTask({'tasks': [legacy, gold('b', 'above', 4140)]}, legacy)!;
      expect((left['tasks'] as List).single['id'], 'b');
      expect(cancelArguments(legacy), {'id': '', 'direction': 'above', 'threshold': 4140.0});
    });
    test('removing a task that is already gone changes nothing', () {
      final left = withoutTask({'tasks': [gold('b', 'below', 4150)]}, gold('x', 'above', 1))!;
      expect((left['tasks'] as List).length, 1);
      expect(withoutTask(null, gold('x', 'above', 1)), isNull);
    });
  });

  testWidgets('swipe left, confirm: the task is removed on the phone and stays gone', (t) async {
    final fake = await open(t, [gold('a', 'above', 4140), gold('b', 'below', 4150)]);
    expect(find.text('Gold above 4140'), findsOneWidget);
    await t.drag(find.text('Gold above 4140'), const Offset(-500, 0));
    await t.pumpAndSettle();
    expect(find.text('Remove this task?'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('confirm-remove-task')));
    await t.pumpAndSettle();
    expect(fake.cancelled.single['id'], 'a');
    expect(find.text('Gold above 4140'), findsNothing);
    expect(find.text('Gold below 4150'), findsOneWidget);
    // A later refresh reads the phone's store, which no longer has it.
    await t.tap(find.byTooltip('Refresh tasks'));
    await t.pumpAndSettle();
    expect(find.text('Gold above 4140'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('swipe then Keep leaves the task alone', (t) async {
    final fake = await open(t, [gold('a', 'above', 4140)]);
    await t.drag(find.text('Gold above 4140'), const Offset(-500, 0));
    await t.pumpAndSettle();
    await t.tap(find.text('Keep'));
    await t.pumpAndSettle();
    expect(fake.cancelled, isEmpty);
    expect(find.text('Gold above 4140'), findsOneWidget);
  });

  testWidgets('card menu has Remove task', (t) async {
    final fake = await open(t, [gold('a', 'above', 4140), gold('b', 'below', 4150)]);
    await t.tap(find.byKey(const ValueKey('task-menu-b')));
    await t.pumpAndSettle();
    await t.tap(find.text('Remove task'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('confirm-remove-task')));
    await t.pumpAndSettle();
    expect(fake.cancelled.single['id'], 'b');
    expect(find.text('Gold below 4150'), findsNothing);
    expect(find.text('Gold above 4140'), findsOneWidget);
  });

  testWidgets('long-press a card asks to remove it', (t) async {
    final fake = await open(t, [gold('a', 'above', 4140)]);
    await t.longPress(find.text('Gold above 4140'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('confirm-remove-task')));
    await t.pumpAndSettle();
    expect(fake.cancelled.single['id'], 'a');
    expect(find.text('No active tasks.'), findsOneWidget);
  });

  testWidgets('header menu removes all tasks after confirming', (t) async {
    final fake = await open(t, [gold('a', 'above', 4140), gold('b', 'below', 4150)]);
    await t.tap(find.byKey(const ValueKey('tasks-menu')));
    await t.pumpAndSettle();
    await t.tap(find.text('Remove all tasks').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('confirm-remove-all')));
    await t.pumpAndSettle();
    expect(fake.cancelAllCalls, 1);
    expect(find.text('No active tasks.'), findsOneWidget);
  });
}
