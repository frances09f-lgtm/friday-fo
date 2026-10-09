import 'package:flutter_test/flutter_test.dart';
import 'package:friday/state/friday_controller.dart';
void main(){
 test('verified volume speaks Done without diagnostic text',(){
  expect(FridayController.spokenActionReply('Media volume verified by two readbacks. Friday 1.0.110; before39/160; target96/160. Foreground volume window used.'),'Done');
 });
 test('unchanged or refused volume never speaks Done',(){
  for(final text in ['Media volume not verified. No success claimed. Readbacks39/160,39/160.','Android refused volume change. No success claimed.','Foreground volume control timed out. No success claimed.']){expect(FridayController.spokenActionReply(text),"Couldn't do it");}
  expect(FridayController.spokenActionReply('Media volume already at target. No change made.'),'No change needed');
 });
 test('request only and mixed outcomes never become Done',(){
  expect(FridayController.spokenActionReply('Requested Play, but audio did not start.'),'Check the screen');
  expect(FridayController.spokenActionReply('Media volume verified by two readbacks.\nCould not open app.'),"Couldn't do it");
  expect(FridayController.spokenActionReply('Spotify next requested, but state did not change. No completion claimed.'),'Check the screen');
 });
 test('verified Spotify and reminder stay short',(){
  expect(FridayController.spokenActionReply('Spotify next verified from playback or track state.'),'Done');
  expect(FridayController.spokenActionReply('Reminder registered for tomorrow with native scheduler.'),'Done');
 });
}
