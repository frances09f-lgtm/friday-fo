import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('confirmed order binds before queue, never opens Sona', () {
    final src = File('android/app/src/main/kotlin/com/friday/assistant/SonaBackgroundOrder.kt').readAsStringSync();
    expect(src, contains('Context.BIND_AUTO_CREATE'));
    expect(src, contains('getBoolean("background", false)'));
    expect(src, contains('onServiceConnected'));
    expect(src, contains('fridayTradeSubmit'));
    expect(src, contains('fridayTradeCancel'));
    expect(src, isNot(contains('startActivity(')));
    expect(src, isNot(contains('getLaunchIntentForPackage')));
    final bridge = File('android/app/src/main/kotlin/com/friday/assistant/DeviceBridge.kt').readAsStringSync();
    expect(bridge, contains('SonaBackgroundOrder.submit'));
    expect(bridge, isNot(contains('friday_trade')));
  });
}
