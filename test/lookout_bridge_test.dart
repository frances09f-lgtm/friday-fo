import 'dart:convert';
import 'dart:io';
import 'package:friday/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/lookout_bridge.dart';
import 'package:friday/services/ai/offline_engine.dart';
import 'package:friday/models/friday_response.dart';

void main() {
  test('read only exact Lookout commands do not imply mutations', () {
    for (final p in [
      'Lookout status',
      'show Lookout watches',
      'Lookout watch list'
    ]) {
      expect(const OfflineEngine().handle(p).action.type,
          FridayActionType.lookoutStatus);
    }
    expect(const OfflineEngine().handle('pause Lookout watches').action.type,
        isNot(FridayActionType.lookoutStatus));
  });
  test('missing and empty data are distinct', () {
    expect(LookoutBridge.answer(null), contains("couldn't read"));
    expect(LookoutBridge.answer('{"total":0,"watches":[]}'),
        contains('no watches'));
  });
  test('reports failed values unavailable and ages honestly', () {
    final raw = jsonEncode({
      'total': 1,
      'watches': [
        {
          'id': 1,
          'title': 'Phone',
          'status': 'failed',
          'lastCheckedAt': 60000,
          'currentValue': null,
          'lastSuccessfulValue': 999
        }
      ]
    });
    final text = LookoutBridge.answer(raw, nowMs: 180000);
    expect(text, contains('checked 2m ago'));
    expect(text, contains('current value unavailable'));
    expect(text, isNot(contains('999')));
    expect(text, contains('does not run a fresh'));
  });
  test(
      'private bridge replies persist local-only and never enter model history',
      () {
    final m = ChatMessage(
        id: 'bridge',
        role: MessageRole.friday,
        text: 'private watch',
        at: DateTime(2026),
        localOnly: true);
    expect(ChatMessage.fromJson(m.toJson()).localOnly, isTrue);
    final code = File('lib/services/ai/ai_brain.dart').readAsStringSync();
    expect(
        RegExp(r'history.where\(\(m\) => !m.localOnly\)')
            .allMatches(code)
            .length,
        2);
  });
 test('speech aliases stay app scoped',(){
  for(final q in ['look out status','look-out watches']){expect(const OfflineEngine().handle(q).action.type,FridayActionType.lookoutStatus);}
  for(final q in ['auro','orrow status','oro gold']){expect(const OfflineEngine().handle(q).action.type,FridayActionType.oroStatus);}
  expect(const OfflineEngine().handle('open auro').action.app,'oro');
  expect(const OfflineEngine().handle('open look out').action.app,'lookout');
 });

}
