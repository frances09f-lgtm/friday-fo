import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/device/device_hub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('friday/device');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  String? launched;
  setUp(() {
    launched = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getInstalledApps') {
        return [
          {
            'label': 'Gold Paper Trading',
            'package': 'com.ambi.gold_paper_trading',
          },
        ];
      }
      if (call.method == 'openApp') {
        launched = (call.arguments as Map)['package'] as String;
        return true;
      }
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  for (final name in ['Sona', 'oro']) {
    test('$name launches the same Android application', () async {
      final app = await DeviceHub().openAppByName(name);
      expect(app?.packageName, 'com.ambi.gold_paper_trading');
      expect(launched, 'com.ambi.gold_paper_trading');
    });
  }
}
