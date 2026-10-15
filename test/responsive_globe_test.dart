import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/ui/responsive_globe.dart';

void main() {
  Widget scene(
          {GlobeMode mode = GlobeMode.idle,
          VoidCallback? tap,
          bool active = true,
          bool reduced = false,
          bool tickers = true}) =>
      MaterialApp(
          home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: TickerMode(
                  enabled: tickers,
                  child: Center(
                      child: ResponsiveGlobe(
                          mode: mode, onTap: tap, active: active)))));
  GlobePainter painter(WidgetTester t) => t
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((e) => e.painter)
      .whereType<GlobePainter>()
      .single;
  testWidgets('tap performs voice action, horizontal drag only rotates',
      (t) async {
    var calls = 0;
    await t.pumpWidget(scene(tap: () => calls++));
    final initial = painter(t).yaw;
    await t.tap(find.byType(ResponsiveGlobe));
    expect(calls, 1);
    await t.drag(find.byType(ResponsiveGlobe), const Offset(80, 12));
    await t.pump();
    expect(calls, 1);
    expect(painter(t).yaw, isNot(initial));
    expect(t.takeException(), isNull);
  });
  testWidgets('active listening, thinking and speaking move; idle does not',
      (t) async {
    for (final mode in [
      GlobeMode.listening,
      GlobeMode.thinking,
      GlobeMode.speaking
    ]) {
      await t.pumpWidget(scene(mode: mode));
      await t.pump();
      final before = painter(t).phase;
      await t.pump(const Duration(milliseconds: 220));
      expect(painter(t).mode, mode);
      expect(painter(t).phase, isNot(before));
    }
    await t.pumpWidget(scene());
    await t.pumpAndSettle();
    final idlePhase = painter(t).phase;
    await t.pump(const Duration(seconds: 2));
    expect(painter(t).phase, idlePhase);
    expect(t.hasRunningAnimations, isFalse);
  });
  testWidgets('reduced motion, inactive and hidden TickerMode stop animations',
      (t) async {
    for (final w in [
      scene(mode: GlobeMode.speaking, reduced: true),
      scene(mode: GlobeMode.listening, active: false),
      scene(mode: GlobeMode.thinking, tickers: false)
    ]) {
      await t.pumpWidget(w);
      await t.pumpAndSettle();
      final phase = painter(t).phase;
      await t.pump(const Duration(seconds: 2));
      expect(painter(t).phase, phase);
      expect(t.hasRunningAnimations, isFalse);
    }
  });
  testWidgets('background lifecycle stops and foreground resumes', (t) async {
    await t.pumpWidget(scene(mode: GlobeMode.listening));
    await t.pump();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    expect(t.hasRunningAnimations, isFalse);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(t.hasRunningAnimations, isTrue);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('disabled thinking globe never starts voice and exposes status',
      (t) async {
    final semantics = t.ensureSemantics();
    await t.pumpWidget(scene(mode: GlobeMode.thinking));
    await t.tap(find.byType(ResponsiveGlobe));
    await t.pump();
    expect(find.bySemanticsLabel('Friday is working. Drag to rotate.'),
        findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    semantics.dispose();
  });
}
