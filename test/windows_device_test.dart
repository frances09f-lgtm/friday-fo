import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/device/windows_device.dart';
import 'package:friday/state/friday_controller.dart';

void main() {
  test('failed action result never gets a Done prefix', () {
    expect(FridayController.actionResultReply("I couldn't open Camera."),
        "I couldn't open Camera.");
    expect(FridayController.actionResultReply('Asked windows to close.'),
        'Asked windows to close.');
    expect(FridayController.actionResultReply(''), 'Done.');
  });
  test('close all requests closure without discarding unsaved work', () {
    final script = WindowsDevice.closeAllAppsScript;
    expect(script, contains('CloseMainWindow()'));
    expect(script, isNot(contains('.Kill(')));
    expect(script, isNot(contains('Stop-Process')));
    expect(script, isNot(contains('Start-Sleep')));
    expect(script, contains("'requested'"));
  });
  test('known apps resolve to their launch targets', () {
    expect(WindowsDevice.resolveAppTarget('whatsapp'), 'whatsapp:');
    expect(WindowsDevice.resolveAppTarget('Google Chrome'), 'chrome');
    expect(WindowsDevice.resolveAppTarget('calculator'), 'calc');
    expect(WindowsDevice.resolveAppTarget('spotify'), 'spotify:');
  });

  test('unknown apps pass through as-is', () {
    expect(WindowsDevice.resolveAppTarget('Figma'), 'figma');
  });

  test('volume step script moves exactly 5% through Core Audio', () {
    final up = WindowsDevice.volumeStepScript(up: true);
    expect(up, contains('FridayAudio'));
    expect(up, contains('+ (0.05)'));
    expect(up, contains('GetMasterVolumeLevelScalar'));
    final down = WindowsDevice.volumeStepScript(up: false);
    expect(down, contains('+ (-0.05)'));
  });

  test('brightness step script reads then writes WMI brightness by 5', () {
    final up = WindowsDevice.brightnessStepScript(up: true);
    expect(up, contains('WmiMonitorBrightness'));
    expect(up, contains('+ (5)'));
    final down = WindowsDevice.brightnessStepScript(up: false);
    expect(down, contains('+ (-5)'));
    expect(down, contains('WmiSetBrightness'));
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
