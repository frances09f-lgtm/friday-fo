import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/assistant_overlay.dart';
import 'package:friday/ui/orion_style.dart';
void main() {
  for (final entry in {'light': Orion.light(), 'dark': Orion.dark()}.entries) {
    testWidgets('compact viewport dimensions and taps in ${entry.key}', (t) async {
      var taps = 0;
      await t.pumpWidget(MaterialApp(theme: entry.value, home: Center(
        child: SizedBox(width: 280, height: 140, child: CompactAssistantViewport(
          child: Center(child: GestureDetector(onTap: () => taps++,
            child: Container(key: const Key('target'), width: 100, height: 40,
              color: entry.value.colorScheme.primary))))))));
      final rect = t.getRect(find.byKey(const Key('target')));
      expect(rect.width, closeTo(100, 0.01));
      expect(rect.height, closeTo(40, 0.01));
      await t.tap(find.byKey(const Key('target')));
      expect(taps, 1);
      expect(t.takeException(), isNull);
    });
  }
}
