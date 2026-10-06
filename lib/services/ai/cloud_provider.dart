import '../../models/chat_message.dart';

class FridayApiException implements Exception {
  FridayApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A cloud "brain" Friday can think with. Implementations call one hosted API
/// with a free-tier key the user pastes in Settings.
abstract class CloudProvider {
  String get name;

  Future<String> complete({
    required String system,
    required List<ChatMessage> history,
    required String userText,
  });
}
