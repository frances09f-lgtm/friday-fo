import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/agent/compound_command.dart';

void main() {
  test('extract app separately without executing the remainder', () {
    final g = CompoundCommand.parse('open gallery and play first video')!;
    expect(g.app, 'gallery');
    expect(g.action, 'play first video');
    final x = CompoundCommand.parse('open WhatsApp and send money')!;
    expect(x.app, 'WhatsApp');
    expect(x.action, 'send money');
    expect(CompoundCommand.parse('open gallery'), null);
  });
}
