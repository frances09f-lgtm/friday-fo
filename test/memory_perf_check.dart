import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/storage/memory_store.dart';

void main() {
  test('memory path cost stays negligible for the on-device model', () async {
    final dir = Directory.systemTemp.createTempSync('friday_memory_perf');
    final store = MemoryStore(directory: dir);
    await store.ensureSeeded();
    for (var i = 0; i < 50; i++) {
      await store.remember('fact number $i about gold price and bikes');
    }
    final sw = Stopwatch()..start();
    final miss = await store.relevantSection('open whatsapp');
    final missMs = sw.elapsedMilliseconds;
    sw.reset();
    final hit = await store.relevantSection('what about my gold alerts?');
    final hitMs = sw.elapsedMilliseconds;
    // ignore: avoid_print
    print('PERF miss=${missMs}ms bytes=${miss.length} hit=${hitMs}ms bytes=${hit.length}');
    expect(miss, '');
    expect(hit.length, lessThan(340));
    dir.deleteSync(recursive: true);
  });
}
