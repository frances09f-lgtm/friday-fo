import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:friday/services/intent_router.dart';
import 'package:friday/services/device/device_hub.dart';
import 'package:friday/services/ai/offline_engine.dart';

void main() {
  test('owner Tiffe speech aliases bind package not unrelated food app', () {
    const apps = [
      InstalledApp(label: 'Tiffe', packageName: 'com.ambi.tiffe'),
      InstalledApp(label: 'Tiffin Delivery', packageName: 'other.food')
    ];
    for (final word in ['tiffe', 'tiffie', 'tiffin'])
      expect(DeviceHub.matchApp(word, apps)?.packageName, 'com.ambi.tiffe');
    expect(DeviceHub.matchApp('tiffin', [apps.last]), isNull);
  });
  test('unique small typo accepted, ambiguous and short names refused', () {
    const apps = [
      InstalledApp(label: 'WhatsApp', packageName: 'whatsapp'),
      InstalledApp(label: 'YouTube', packageName: 'youtube')
    ];
    expect(DeviceHub.matchApp('whatsap', apps)?.label, 'WhatsApp');
    expect(DeviceHub.matchApp('youtub', apps)?.label, 'YouTube');
    expect(
        DeviceHub.matchApp('whatsap', [
          ...apps,
          const InstalledApp(label: 'WhatsApp2', packageName: 'second')
        ]),
        isNull);
    expect(DeviceHub.matchApp('go', apps), isNull);
  });
  const apps = [
    InstalledApp(label: 'Muse', packageName: 'com.community.oru'),
    InstalledApp(label: 'Community Aura', packageName: 'com.aura'),
    InstalledApp(label: 'Oro', packageName: DeviceHub.sonaPackage)
  ];
  test('legacy aliases always select gold package, never Muse or Community',
      () {
    for (final alias in DeviceHub.sonaAliases) {
      expect(
          DeviceHub.matchApp(alias, apps)?.packageName, DeviceHub.sonaPackage);
      expect(DeviceHub.matchApp(alias, apps.take(2).toList()), isNull);
    }
  });
  test('partial labels require whole words, confidence and unique match', () {
    expect(DeviceHub.matchApp('oru', apps.take(2).toList()), isNull);
    expect(DeviceHub.matchApp('commun', apps), isNull);
    expect(DeviceHub.matchApp('community', apps), isNull);
    expect(DeviceHub.matchApp('community aura', apps)?.packageName, 'com.aura');
  });
  test('Oru Aura Sona spoken opens normalize before routing', () {
    for (final name in ['Oru', 'Aura', 'Sona', 'oro']) {
      expect(const OfflineEngine().handle('open $name').action.app, 'oro');
    }
  });
  test('native rejected launch never claims success; accepted is request only',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('friday/device');
    bool accepted = false;
    String? launched;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getInstalledApps')
        return [
          {'label': 'Muse', 'package': 'com.oru'},
          {'label': 'Sona', 'package': DeviceHub.sonaPackage}
        ];
      if (call.method == 'openApp') {
        launched = (call.arguments as Map)['package'];
        return accepted;
      }
      return null;
    });
    final hub = DeviceHub();
    expect(
        IntentRouter.appLaunchResult('Aura', await hub.openAppByName('Aura')),
        contains("couldn't"));
    expect(launched, DeviceHub.sonaPackage);
    accepted = true;
    final result =
        IntentRouter.appLaunchResult('Aura', await hub.openAppByName('Aura'));
    expect(result, contains('Launch requested for Sona'));
    expect(result, contains('cannot verify'));
    expect(result, isNot('Done.'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
