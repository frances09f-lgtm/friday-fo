import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/device/windows_device.dart';

void main() {
  test('known apps resolve to their launch targets', () {
    expect(WindowsDevice.resolveAppTarget('whatsapp'), 'whatsapp:');
    expect(WindowsDevice.resolveAppTarget('Google Chrome'), 'chrome');
    expect(WindowsDevice.resolveAppTarget('calculator'), 'calc');
    expect(WindowsDevice.resolveAppTarget('spotify'), 'spotify:');
  });

  test('unknown apps pass through as-is', () {
    expect(WindowsDevice.resolveAppTarget('Figma'), 'figma');
  });

  test('volume scripts send the right keys and steps', () {
    expect(WindowsDevice.volumeScript(up: true), contains('[char]175'));
    expect(WindowsDevice.volumeScript(up: false), contains('[char]174'));
    expect(WindowsDevice.volumeScript(up: true), contains('1..5'));
  });

  test('set-volume script bottoms out then climbs percent/2 steps', () {
    final s = WindowsDevice.setVolumeScript(30);
    expect(s, contains('1..50')); // 50 downs to reach zero
    expect(s, contains('1..15')); // 15 ups = 30%
    expect(WindowsDevice.setVolumeScript(150), contains('1..50'));
  });

  test('brightness script targets the WMI brightness method', () {
    final s = WindowsDevice.brightnessScript(40);
    expect(s, contains('WmiMonitorBrightnessMethods'));
    expect(s, contains('WmiSetBrightness(1, 40)'));
  });
}
