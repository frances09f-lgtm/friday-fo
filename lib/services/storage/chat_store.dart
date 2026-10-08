import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/chat_message.dart';

/// Persists the conversation so Friday remembers across restarts.
class ChatStore {
  ChatStore(this._prefs, {String storageKey = 'friday_chat_log'})
      : _storeKey = storageKey;

  final String _storeKey;
  static const _maxMessages = 200;

  final SharedPreferences _prefs;

  List<ChatMessage> load() {
    final raw = _prefs.getString(_storeKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map(ChatMessage.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<ChatMessage> messages) async {
    final trimmed = messages.length > _maxMessages
        ? messages.sublist(messages.length - _maxMessages)
        : messages;
    await _prefs.setString(
      _storeKey,
      jsonEncode([for (final m in trimmed) m.toJson()]),
    );
  }

  Future<void> clear() async {
    await _prefs.remove(_storeKey);
  }
}
