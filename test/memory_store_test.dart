import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/storage/memory_store.dart';

void main() {
  late Directory dir;
  late MemoryStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('friday_memory_test');
    store = MemoryStore(directory: dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('seeds the three markdown files once without overwriting edits', () async {
    await store.ensureSeeded();
    final base = Directory('${dir.path}/friday_memory');
    expect(File('${base.path}/SOUL.md').existsSync(), isTrue);
    expect(File('${base.path}/MEMORY.md').existsSync(), isTrue);
    expect(File('${base.path}/USER.md').existsSync(), isTrue);
    await File('${base.path}/USER.md').writeAsString('# About the user\n- Name is Abhijeet\n');
    await store.ensureSeeded();
    expect(File('${base.path}/USER.md').readAsStringSync(), contains('Abhijeet'));
  });

  test('remember appends dated bullets and recall finds them', () async {
    expect(await store.remember('my bike is a Duke 390'), isTrue);
    expect(await store.remember('wifi password is not saved here'), isTrue);
    final found = await store.search('bike');
    expect(found.single, contains('Duke 390'));
    final recent = await store.recent();
    expect(recent.length, 2);
  });

  test('prompt injection is retrieval-only and tiny', () async {
    await store.remember('favorite color is cyan');
    // No keyword overlap: nothing is added to the prompt at all.
    expect(await store.relevantSection('open whatsapp'), '');
    // Keyword hit: the matching fact, capped small for the on-device model.
    final section = await store.relevantSection('what is my favorite color?');
    expect(section, contains('cyan'));
    expect(section.length, lessThan(340));
  });

  test('long facts are truncated to the line budget', () async {
    await store.remember('long fact ${'x' * 400}');
    final section = await store.relevantSection('long fact');
    expect(section.length, lessThan(340));
  });

  test('forget removes only matching bullets', () async {
    await store.remember('my bike is a Duke 390');
    await store.remember('favorite color is cyan');
    expect(await store.forget('bike duke'), 1);
    final recent = await store.recent();
    expect(recent.single, contains('cyan'));
    expect(await store.forget('nonexistent thing'), 0);
  });

  test('search ranks the best matching fact first', () async {
    await store.remember('gold price alerts are set at 4100');
    await store.remember('gold and gold and gold watch runs daily');
    final found = await store.search('gold');
    expect(found, isNotEmpty);
    expect(found.first.toLowerCase(), contains('gold'));
  });
}
