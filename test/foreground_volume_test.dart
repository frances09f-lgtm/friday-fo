import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
void main(){
 test('overlay volume uses visible Activity while main app keeps measured path',(){
  final bridge=File('android/app/src/main/kotlin/com/friday/assistant/DeviceBridge.kt').readAsStringSync();
  expect(bridge,contains('if(activity!=null)verifiedVolumeSet'));
  expect(bridge,contains('else VolumeControlActivity.request(context'));
  expect(bridge,contains('early==target&&after==target&&after!=before&&sameRoute'));
  final activity=File('android/app/src/main/kotlin/com/friday/assistant/VolumeControlActivity.kt').readAsStringSync();
  expect(activity,contains('if(!focus||started)return'));
  expect(activity,contains('DeviceBridge.measuredVolume(this,p.percent,p.up'));
  expect(activity,contains('isKeyguardLocked'));
  expect(activity,contains('Foreground volume window used.'));
  expect(activity,isNot(contains('AudioTrack')));
  expect(activity,isNot(contains('WRITE_SETTINGS')));
  final overlay=File('android/app/src/main/kotlin/com/friday/assistant/AssistantOverlayService.kt').readAsStringSync();
  expect(overlay,contains('FLAG_NOT_FOCUSABLE.inv()'));
  expect(overlay,contains('View.INVISIBLE'));
 });
}
