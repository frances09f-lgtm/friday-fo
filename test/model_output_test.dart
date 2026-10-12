import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/ai/model_output.dart';

void main() {
  test('escaped whitespace alone is not a model response', () {
    expect(hasModelContent(r'\n\n\n'), false);
    expect(hasModelContent(' \n\t '), false);
    expect(hasModelContent(r'\nHello\n'), true);
    expect(hasModelContent(r'{"text":"\n"}'), true);
  });
}
