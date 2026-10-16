import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/intent_router.dart';
import 'package:friday/services/ai/offline_engine.dart';
import 'package:friday/models/friday_response.dart';

void main() {
  test(
      'WhatsApp parser preserves spelling punctuation whitespace and embedded commands',
      () {
    const engine = OfflineEngine();
    for (final body in [
      "helo gaurv!!",
      "  HeLo\nDon't change this!  ",
      "hello and open camera",
      "gold above 4000 every 5 minutes?"
    ]) {
      final response = engine.handle('WhatsApp to gourav dhavale saying $body');
      expect(response.action.type, FridayActionType.sendWhatsApp);
      expect(response.action.target, 'gourav dhavale');
      expect(response.action.body, body);
      expect(response.extraActions, isEmpty);
    }
  });
  test('recipient rejection and cancellation never report completion', () {
    for (final outcome in [
      'cancelled',
      'recipient_changed',
      'confirmation_expired',
      'confirmation_unavailable',
      'locked',
      'agent_running'
    ]) {
      final reply = IntentRouter.recipientConfirmationReply(outcome);
      expect(reply, isNotNull);
      expect(reply, isNot('Done.'));
    }
    expect(IntentRouter.recipientConfirmationReply('opened'), isNull);
  });
}
