import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:friday/services/link/device_link.dart';
import 'package:friday/services/ai/ai_brain.dart';
import 'package:friday/services/ai/local_model_service.dart';
import 'package:friday/services/device/device_hub.dart';
import 'package:friday/services/device/reminder_service.dart';
import 'package:friday/services/intent_router.dart';
import 'package:friday/services/speech/speech_service.dart';
import 'package:friday/services/storage/chat_store.dart';
import 'package:friday/services/storage/settings_store.dart';
import 'package:friday/state/friday_controller.dart';
import 'package:friday/models/friday_response.dart';
class CaptureLink extends DeviceLink {
  String? received;
  @override
  Future<String> send(String text) async { received = text; return 'Received on phone'; }
}
class CaptureRouter extends IntentRouter {
 CaptureRouter():super(deviceHub:DeviceHub(),reminders:ReminderService());
 List<FridayAction>? actions;
 @override
 Future<String> executeAll(List<FridayAction> value) async { actions=value; return ''; }
}
void main() {
 TestWidgetsFlutterBinding.ensureInitialized();
 for(final input in ['open camera on phone','open camera on my phone','open camera on the phone','open camera to mobile','open camera ON PHONE!']) {
  test('routes stripped command: $input',() async {
   SharedPreferences.setMockInitialValues({});
   final prefs=await SharedPreferences.getInstance();
   final settings=SettingsStore(const FlutterSecureStorage(),prefs)..speakReplies=false;
   final link=CaptureLink();
   final c=FridayController(brain:AIBrain(settings:settings,local:LocalModelService()),
    router:IntentRouter(deviceHub:DeviceHub(),reminders:ReminderService()),
    chatStore:ChatStore(prefs),speech:SpeechService(),settings:settings,link:link);
   await c.send(input);
   expect(link.received,'open camera');
   expect(c.busy,false);
   expect(c.messages.last.text,'Received on phone');
  });
 }
 test('received close-apps executes receiver router and empty result is not Done',() async {
   SharedPreferences.setMockInitialValues({});
   final prefs=await SharedPreferences.getInstance();
   final settings=SettingsStore(const FlutterSecureStorage(),prefs)..speakReplies=false;
   final router=CaptureRouter();
   final c=FridayController(brain:AIBrain(settings:settings,local:LocalModelService()),
    router:router,chatStore:ChatStore(prefs),speech:SpeechService(),settings:settings);
   final reply=await c.receiveRemote('close all apps');
   expect(router.actions!.single.type,FridayActionType.closeAllApps);
   expect(reply,contains('not verified'));
   expect(reply,isNot(contains('Done')));
 });

}
