import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/assistant_overlay.dart';
import 'package:friday/ui/orion_style.dart';

Widget _host(ThemeData theme) => MaterialApp(
      theme: theme,
      home: const Scaffold(
        body: Center(
          child: FridayGlowFrame(
            active: true,
            child: SizedBox(
              width: 200,
              height: 60,
              child: Center(child: FridayWave(active: true, enabled: true)),
            ),
          ),
        ),
      ),
    );

void main() {
  for (final entry in {'light': Orion.light(), 'dark': Orion.dark()}.entries) {
    testWidgets('floating bar frame and wave render in ${entry.key}',
        (tester) async {
      await tester.pumpWidget(_host(entry.value));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(FridayGlowFrame), findsOneWidget);
      expect(find.byType(FridayWave), findsOneWidget);
      expect(tester.takeException(), isNull);
      final box = tester.widget<AnimatedContainer>(find.descendant(
          of: find.byType(FridayGlowFrame),
          matching: find.byType(AnimatedContainer)));
      final deco = box.decoration as BoxDecoration;
      expect(deco.color, entry.value.colorScheme.surfaceContainerLow);
      expect(deco.borderRadius, BorderRadius.circular(32));
    });
  }

  test('overlay sources use the Orion look', () {
    final dart = File('lib/assistant_overlay.dart').readAsStringSync();
    final kt = File(
            'android/app/src/main/kotlin/com/friday/assistant/AssistantOverlayService.kt')
        .readAsStringSync();
    expect(dart, contains('Orion.light()'));
    expect(dart, contains('Orion.dark()'));
    expect(dart, isNot(contains('0xff0d1222')));
    expect(dart, isNot(contains('0xff00f2fe')));
    expect(kt, contains('GradientDrawable.RECTANGLE'));
    expect(kt, contains('setCornerRadius(24*density)'));
    expect(kt, contains('UI_MODE_NIGHT_MASK'));
    expect(kt, isNot(contains('GradientDrawable.OVAL')));
  });
}
