import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/oro/oro_bridge.dart';
void main() {
 test('fresh quote does not make old account fresh', () {
  const s=OroSnapshot(ts:1000000,quoteAt:1000000,accountAt:400000,accountKnown:true,bid:4000,ask:4001,balance:123);
  expect(OroBridge.answer('price',s,nowMs:1000000),contains('just now'));
  expect(OroBridge.answer('balance',s,nowMs:1000000),contains('10 minutes ago'));
  expect(OroBridge.answer('trades',s,nowMs:1000000),contains('10 minutes ago'));
 });
 test('unknown account does not claim no open trades', () {
  const s=OroSnapshot(ts:1000000,quoteAt:1000000,accountKnown:false,bid:4000,ask:4001);
  expect(OroBridge.answer('trades',s),contains('cannot tell'));
  expect(OroBridge.answer('tpsl',s),contains('cannot tell'));
 });
 test('legacy account timestamp is unknown rather than quote time', () {
  final s=OroSnapshot.parse('{"ts":1000000,"quoteAt":1000000,"balance":50,"open":[]}');
  expect(OroBridge.answer('balance',s,nowMs:1000000),contains('unknown time'));
 });
}
