import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/agent/agent_contract.dart';
import 'package:friday/services/agent/gallery_command.dart';
import 'package:friday/services/agent/element_order.dart';

void main() {
  test('exact screenshot commands route deterministically', () {
    final g = AgentGoal.parse('open WhatsApp and search for Mayuri')!;
    expect(g.package, 'com.whatsapp');
    expect(g.query, 'Mayuri');
    expect(g.workflow, 'search');
    expect(AgentGoal.parse('open  WhatsApp and\n search for Mayuri')!.query,
        'Mayuri');
    expect(GalleryCommand.parse('play first video from my gallery'), 1);
    expect(GalleryCommand.parse('play fifty video from my gallery'), null);
  });
  test('ported sort uses observed top then left', () {
    expect(
        ElementOrder.compare({
          'bounds': [40, 100, 50, 200]
        }, {
          'bounds': [10, 100, 30, 200]
        }),
        greaterThan(0));
    expect(
        ElementOrder.compare({
          'bounds': [40, 90, 50, 200]
        }, {
          'bounds': [10, 100, 30, 200]
        }),
        lessThan(0));
  });
}
