import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:friday/services/storage/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('default trade size is 0.01 lot, saved and validated', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = SettingsStore(const FlutterSecureStorage(), prefs);
    expect(store.defaultTradeLots, 0.01);
    expect(await store.setDefaultTradeLots(0.1), isTrue);
    expect(store.defaultTradeLots, 0.1);
    expect(prefs.getDouble('friday_default_trade_lots'), 0.1);
    expect(await store.setDefaultTradeLots(0.005), isFalse);
    expect(await store.setDefaultTradeLots(0), isFalse);
    expect(await store.setDefaultTradeLots(1000), isFalse);
    expect(store.defaultTradeLots, 0.1);
  });
}
