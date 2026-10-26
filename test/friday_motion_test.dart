import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/ui/friday_motion.dart';
Widget host(Widget child, {bool reduced = false}) => MaterialApp(home: MediaQuery(data: MediaQueryData(disableAnimations: reduced), child: Scaffold(body: child)));
Finder inside(Type type) => find.descendant(of: find.byType(MotionPress), matching: find.byType(type));
class Counter extends StatefulWidget { const Counter({super.key}); @override State<Counter> createState() => CounterState(); }
class CounterState extends State<Counter> { int value = 0; @override Widget build(BuildContext c) => TextButton(onPressed: () => setState(() => value++), child: Text('count $value')); }
void main() {
 testWidgets('press release and cancel leave native callbacks in charge', (t) async {
  var calls = 0; await t.pumpWidget(host(Center(child: MotionPress(child: FilledButton(onPressed: () => calls++, child: const Text('go'))))));
  final gesture = await t.startGesture(t.getCenter(find.text('go'))); await t.pump(); expect(t.widget<AnimatedScale>(inside(AnimatedScale)).scale, .94);
  await gesture.cancel(); await t.pumpAndSettle(); expect(calls, 0); expect(t.widget<AnimatedScale>(inside(AnimatedScale)).scale, 1);
  await t.tap(find.text('go')); await t.pumpAndSettle(); expect(calls, 1);
  final scroll = await t.startGesture(t.getCenter(find.text('go'))); await scroll.moveBy(const Offset(0, 30)); await t.pump(); expect(t.widget<AnimatedScale>(inside(AnimatedScale)).scale, 1); await scroll.cancel(); await t.pumpAndSettle(); expect(calls, 1);
 });
 testWidgets('disabled and reduced-motion presses never scale', (t) async {
  await t.pumpWidget(host(const Center(child: MotionPress(enabled: false, child: FilledButton(onPressed: null, child: Text('go'))))));
  var g = await t.startGesture(t.getCenter(find.text('go'))); await t.pump(); expect(t.widget<AnimatedScale>(inside(AnimatedScale)).scale, 1); await g.cancel();
  await t.pumpWidget(host(Center(child: MotionPress(child: FilledButton(onPressed: () {}, child: const Text('go')))), reduced: true));
  g = await t.startGesture(t.getCenter(find.text('go'))); await t.pump(); expect(t.widget<AnimatedScale>(inside(AnimatedScale)).scale, 1); await g.cancel(); await t.pumpAndSettle();
 });
 testWidgets('switch retains native callback, value and semantics', (t) async {
  final semantics = t.ensureSemantics();
  var on = false, calls = 0;
  await t.pumpWidget(host(StatefulBuilder(builder: (c, set) => MotionSwitchTile(title: const Text('Voice'), value: on, onChanged: (v) => set(() { on = v; calls++; })))));
  expect(t.widget<Switch>(find.byType(Switch)).value, false);
  await t.tap(find.byType(Switch)); await t.pumpAndSettle(); expect(on, true); expect(calls, 1); expect(t.widget<Switch>(find.byType(Switch)).value, true);
  expect(find.bySemanticsLabel(RegExp('Voice')), findsWidgets);
  await t.tap(find.text('Voice')); await t.pumpAndSettle(); expect(on, false); expect(calls, 2);
  await t.pumpWidget(host(const MotionSwitch(value: true, onChanged: null), reduced: true)); await t.pump(); expect(t.widget<Switch>(find.byType(Switch)).onChanged, isNull); expect(t.takeException(), isNull);
  semantics.dispose();
 });
 testWidgets('stagger completes and pending delays cancel on disposal', (t) async {
  await t.pumpWidget(host(const MotionList(children: [Text('one'), Text('two'), Text('three')]))); await t.pump(const Duration(milliseconds: 20));
  final opacity = find.descendant(of: find.byType(MotionEntrance).at(1), matching: find.byType(Opacity)); expect(t.widget<Opacity>(opacity).opacity, 0);
  await t.pumpAndSettle(const Duration(milliseconds: 50)); for (final o in t.widgetList<Opacity>(find.byType(Opacity))) { expect(o.opacity, 1); }
  await t.pumpWidget(host(const MotionEntrance(index: 7, child: Text('late')))); await t.pumpWidget(const SizedBox.shrink()); await t.pump(const Duration(seconds: 1)); expect(t.takeException(), isNull);
 });
 testWidgets('rapid retained tab switching preserves child state', (t) async {
  final counter = GlobalKey<CounterState>(); var active = 0; late StateSetter update;
  await t.pumpWidget(host(StatefulBuilder(builder: (c, set) { update = set; return IndexedStack(index: active, children: [MotionTab(active: active == 0, child: Counter(key: counter)), MotionTab(active: active == 1, child: const Text('second'))]); })));
  await t.pumpAndSettle(); await t.tap(find.text('count 0')); await t.pump(); final original = counter.currentState;
  for (var i = 0; i < 8; i++) { update(() => active = 1 - active); await t.pump(const Duration(milliseconds: 20)); }
  await t.pumpAndSettle(); expect(counter.currentState, same(original)); expect(find.text('count 1'), findsOneWidget); expect(t.takeException(), isNull); await t.pumpWidget(const SizedBox.shrink());
 });
 testWidgets('reduced motion shows entrances in one frame', (t) async {
  await t.pumpWidget(host(const MotionEntrance(index: 7, child: Text('instant')), reduced: true)); await t.pump(); expect(t.widget<Opacity>(find.byType(Opacity)).opacity, 1); expect(t.hasRunningAnimations, false);
 });
}
