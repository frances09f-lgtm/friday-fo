import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Friday's long-term memory as three plain-Markdown files, adapted from
/// OpenJarvis's SOUL.md / MEMORY.md / USER.md design
/// (github.com/open-jarvis/OpenJarvis, Apache-2.0):
///
/// - SOUL.md   - who Friday is (seeded once, user-editable)
/// - MEMORY.md - things the user asked Friday to remember, newest last
/// - USER.md   - lasting facts about the user
///
/// No vector database and no embeddings: files are short, injected into the
/// system prompt under a strict character budget, and searched with a small
/// keyword ranking (OpenJarvis's SQLite FTS5 idea, kept dependency-free so
/// the APK gains no native plugin).
class MemoryStore {
  MemoryStore({Directory? directory}) : _dir = directory;

  Directory? _dir;
  bool _unavailable = false;

  static const soulName = 'SOUL.md';
  static const memoryName = 'MEMORY.md';
  static const userName = 'USER.md';

  static const _maxBullets = 200;
  static const _maxFileBytes = 8192;

  static const _defaultSoul =
      '# Friday\nYou are Friday, a concise, friendly on-device phone assistant. '
      'Answer briefly, do what is asked, and admit what you cannot do.\n';

  Future<Directory?> _directory() async {
    if (_dir != null) return _dir;
    if (_unavailable) return null;
    try {
      _dir = await getApplicationDocumentsDirectory();
      return _dir;
    } catch (_) {
      _unavailable = true;
      return null;
    }
  }

  Future<File?> _file(String name) async {
    final dir = await _directory();
    if (dir == null) return null;
    return File('${dir.path}/friday_memory/$name');
  }

  /// Create the three files on first run; never overwrite user edits.
  Future<void> ensureSeeded() async {
    final soul = await _file(soulName);
    if (soul == null) return;
    try {
      await soul.parent.create(recursive: true);
      if (!await soul.exists()) await soul.writeAsString(_defaultSoul);
      for (final name in [memoryName, userName]) {
        final f = await _file(name);
        if (f != null && !await f.exists()) {
          await f.writeAsString(name == memoryName
              ? '# Remembered facts\n'
              : '# About the user\n');
        }
      }
    } catch (_) {}
  }

  Future<String> _read(String name) async {
    final f = await _file(name);
    if (f == null) return '';
    try {
      return await f.exists() ? await f.readAsString() : '';
    } catch (_) {
      return '';
    }
  }

  /// The on-device model has a small context and every prompt token costs
  /// time, so memory is retrieval-only: nothing is injected unless a saved
  /// bullet matches the current request's keywords, and matches are capped
  /// to [totalBudget] characters. Returns '' when nothing is relevant, so
  /// prompts stay byte-identical to before for almost every message.
  Future<String> relevantSection(
    String userText, {
    int limit = 2,
    int lineBudget = 120,
    int totalBudget = 280,
  }) async {
    final hits = await search(userText, limit: limit);
    if (hits.isEmpty) return '';
    final kept = <String>[];
    var used = 0;
    for (final hit in hits) {
      var line = hit.replaceFirst(RegExp(r'^- '), '');
      if (line.length > lineBudget) line = line.substring(0, lineBudget);
      if (used + line.length > totalBudget) break;
      kept.add(line);
      used += line.length;
    }
    if (kept.isEmpty) return '';
    return '\n\nSaved notes (use silently): ${kept.join(' | ')}';
  }

  /// Append a dated fact to MEMORY.md, trimming the oldest bullets first.
  Future<bool> remember(String fact) async {
    final clean = fact.trim();
    if (clean.isEmpty) return false;
    await ensureSeeded();
    final f = await _file(memoryName);
    if (f == null) return false;
    try {
      final existing = await _read(memoryName);
      final lines = existing.split('\n');
      final header =
          lines.where((l) => !l.trimLeft().startsWith('- ')).join('\n').trim();
      var bullets = lines
          .where((l) => l.trimLeft().startsWith('- '))
          .map((l) => l.trim())
          .toList();
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      bullets.add('- [$stamp] $clean');
      while (bullets.length > _maxBullets) {
        bullets.removeAt(0);
      }
      var body = '$header\n${bullets.join('\n')}\n';
      while (body.length > _maxFileBytes && bullets.isNotEmpty) {
        bullets.removeAt(0);
        body = '$header\n${bullets.join('\n')}\n';
      }
      await f.writeAsString(body);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Remove saved bullets whose text contains every token of [query].
  /// Returns how many bullets were removed.
  Future<int> forget(String query) async {
    final tokens = _tokens(query);
    if (tokens.isEmpty) return 0;
    var removed = 0;
    for (final name in [memoryName, userName]) {
      final f = await _file(name);
      if (f == null) continue;
      try {
        final lines = (await _read(name)).split('\n');
        final kept = <String>[];
        for (final line in lines) {
          final lower = line.toLowerCase();
          final hit = line.trimLeft().startsWith('- ') &&
              tokens.every(lower.contains);
          if (hit) {
            removed++;
          } else {
            kept.add(line);
          }
        }
        if (kept.length != lines.length) {
          await f.writeAsString(kept.join('\n'));
        }
      } catch (_) {}
    }
    return removed;
  }

  static List<String> _tokens(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.length > 1)
      .toList();

  /// Keyword search over saved bullets. Scores by term frequency with a
  /// light length penalty (BM25-style), so the best-matching fact wins.
  Future<List<String>> search(String query, {int limit = 5}) async {
    final tokens = _tokens(query);
    if (tokens.isEmpty) return [];
    final scored = <({double score, String line})>[];
    for (final name in [memoryName, userName]) {
      for (final line in (await _read(name)).split('\n')) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('- ')) continue;
        final lower = trimmed.toLowerCase();
        var score = 0.0;
        for (final t in tokens) {
          final hits = RegExp(RegExp.escape(t)).allMatches(lower).length;
          if (hits > 0) score += 1.0 + hits / (1 + lower.length / 40);
        }
        if (score > 0) scored.add((score: score, line: trimmed));
      }
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).map((s) => s.line).toList();
  }

  /// The newest saved facts, for "what do you remember".
  Future<List<String>> recent({int limit = 10}) async {
    final bullets = (await _read(memoryName))
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.startsWith('- '))
        .toList();
    final user = (await _read(userName))
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.startsWith('- '))
        .toList();
    return [...user, ...bullets].reversed.take(limit).toList();
  }
}
