import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:friday/models/chat_message.dart';
import 'package:friday/services/storage/chat_store.dart';

void main() {
  test('screen summary stays in current UI but not saved chat', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ChatStore(await SharedPreferences.getInstance());
    await store.save([
      ChatMessage(
          id: 'normal',
          role: MessageRole.user,
          text: 'read my screen',
          at: DateTime(2026)),
      ChatMessage(
          id: 'screen',
          role: MessageRole.friday,
          text: 'private screen summary',
          at: DateTime(2026),
          localOnly: true,
          transient: true)
    ]);
    expect(store.load().map((m) => m.id), ['normal']);
  });
}
