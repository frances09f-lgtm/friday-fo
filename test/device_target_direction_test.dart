import 'package:flutter_test/flutter_test.dart';
import 'package:friday/state/friday_controller.dart';
void main() {
 test('explicit laptop from Android is remote; phone from Windows is remote', () {
   for(final target in ['laptop','windows','computer']) {
     expect(FridayController.targetIsOtherDevice(target,isAndroid:true),true);
     expect(FridayController.targetIsOtherDevice(target,isAndroid:false),false);
   }
   for(final target in ['phone','mobile']) {
     expect(FridayController.targetIsOtherDevice(target,isAndroid:false),true);
     expect(FridayController.targetIsOtherDevice(target,isAndroid:true),false);
   }
 });
}
