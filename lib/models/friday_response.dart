enum FridayActionType { none, openApp, readMessages, setReminder }

enum FridaySource { cloud, local, offline }

class FridayAction {
  const FridayAction({
    this.type = FridayActionType.none,
    this.app = '',
    this.query = '',
    this.afterMinutes = 0,
    this.title = '',
    this.body = '',
  });

  final FridayActionType type;
  final String app;
  final String query;
  final int afterMinutes;
  final String title;
  final String body;

  static FridayActionType _typeFrom(String? raw) {
    switch (raw) {
      case 'open_app':
        return FridayActionType.openApp;
      case 'read_messages':
        return FridayActionType.readMessages;
      case 'set_reminder':
        return FridayActionType.setReminder;
      default:
        return FridayActionType.none;
    }
  }

  factory FridayAction.fromJson(Map<String, dynamic> json) => FridayAction(
        type: _typeFrom(json['type'] as String?),
        app: json['app'] as String? ?? '',
        query: json['query'] as String? ?? '',
        afterMinutes: (json['after_minutes'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type.name,
        'app': app,
        'query': query,
        'after_minutes': afterMinutes,
        'title': title,
        'body': body,
      };
}

class FridayResponse {
  const FridayResponse({
    required this.reply,
    this.action = const FridayAction(),
    this.source = FridaySource.offline,
  });

  final String reply;
  final FridayAction action;
  final FridaySource source;
}
