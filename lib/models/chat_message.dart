import 'friday_response.dart';

enum MessageRole { user, friday }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.at,
    this.source,
    this.localOnly = false,
  });

  final String id;
  final MessageRole role;
  final bool localOnly;
  final String text;
  final DateTime at;

  /// Which brain produced this answer (cloud / local / offline). Null for
  /// user messages and older saved messages.
  final FridaySource? source;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'role': role.name,
        if (localOnly) 'localOnly': true,
        'text': text,
        'at': at.toIso8601String(),
        if (source != null) 'source': source!.name,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String? ?? '',
        role: MessageRole.values.firstWhere(
          (r) => r.name == json['role'],
          orElse: () => MessageRole.friday,
        ),
        text: json['text'] as String? ?? '',
        localOnly: json['localOnly'] == true,
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
        source: FridaySource.values
            .where((s) => s.name == json['source'])
            .firstOrNull,
      );
}
