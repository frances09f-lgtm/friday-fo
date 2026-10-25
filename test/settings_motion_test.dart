import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:friday/services/storage/settings_store.dart';
import 'package:friday/services/ai/local_model_service.dart';
import 'package:friday/ui/screens/settings_screen.dart';
import 'package:friday/ui/friday_motion.dart';
import 'package:friday/ui/orion_style.dart';

class SecureMock extends FlutterSecureStorage {
  SecureMock();
  final saved = <String,String>{};
  @override Future<void> write({required String key, required String? value, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async { saved[key] = value ?? ''; }
}
void main() {
  testWidgets('all Settings fields stay editable and the original save works', (t) async {
    SharedPreferences.setMockInitialValues({}); final prefs = await SharedPreferences.getInstance();
    final secure = SecureMock(); final store = SettingsStore(secure, prefs);
    store.geminiKey = 'initial-gemini'; store.groqKey = 'initial-groq'; store.openRouterKey = 'initial-router';
    final local = LocalModelService();
    const channel = MethodChannel('friday/device');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method); if (call.method == 'assistantState') return {'microphone': true, 'overlay': false}; return true;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await t.binding.setSurfaceSize(const Size(412, 892)); addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MultiProvider(providers: [ChangeNotifierProvider<SettingsStore>.value(value: store), ChangeNotifierProvider<LocalModelService>.value(value: local)],
      child: MaterialApp(theme: Orion.light(), home: const SettingsScreen())));
    await t.pumpAndSettle();
    for (final label in ['Assistant setup','Contact nicknames & saved matches','Connected devices','Speak replies out loud','AI & models']) { expect(find.text(label), findsOneWidget); }
    await t.ensureVisible(find.text('Speak replies out loud')); await t.tap(find.text('Speak replies out loud')); await t.pumpAndSettle();
    await t.ensureVisible(find.text('AI & models')); await t.tap(find.text('AI & models')); await t.pumpAndSettle();
    expect(find.text('Qwen local model'), findsOneWidget);
    await t.ensureVisible(find.text('On-device fallback')); await t.tap(find.text('On-device fallback')); await t.pumpAndSettle();
    await t.ensureVisible(find.text('Cloud fallback keys')); await t.tap(find.text('Cloud fallback keys')); await t.pumpAndSettle();
    Finder field(String label) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label);
    for (final entry in {'Gemini API key':'new-gemini','Groq API key':'new-groq','OpenRouter API key':'new-router','Groq model':'new-groq-model','OpenRouter model':'new-router-model'}.entries) {
      await t.ensureVisible(field(entry.key)); await t.enterText(field(entry.key), entry.value); await t.pump();
    }
    for (final label in ['Gemini API key','Groq API key','OpenRouter API key']) { expect(t.widget<TextField>(field(label)).obscureText, true); }
    t.testTextInput.hide(); await t.pump();
    await t.ensureVisible(find.text('Save changes')); await t.tap(find.text('Save changes')); await t.pumpAndSettle();
    expect(store.geminiKey, 'new-gemini'); expect(store.groqKey, 'new-groq'); expect(store.openRouterKey, 'new-router');
    expect(store.groqModel, 'new-groq-model'); expect(store.openRouterModel, 'new-router-model');
    expect(store.speakReplies, false); expect(store.localFallbackEnabled, false);
    expect(secure.saved.length, 3); expect(prefs.getBool('friday_speak_replies'), false); expect(prefs.getBool('friday_local_fallback'), false);
    expect(calls, contains('setGroqKey')); expect(find.text('Settings saved'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('tonal Settings cards support dark theme and reduced motion', (t) async {
    SharedPreferences.setMockInitialValues({}); final prefs = await SharedPreferences.getInstance();
    await t.pumpWidget(MultiProvider(providers: [ChangeNotifierProvider<SettingsStore>.value(value: SettingsStore(SecureMock(), prefs)), ChangeNotifierProvider<LocalModelService>.value(value: LocalModelService())],
      child: MaterialApp(theme: Orion.dark(), home: const MediaQuery(data: MediaQueryData(disableAnimations: true), child: SettingsScreen()))));
    await t.pump(); await t.pump();
    expect(find.byType(MotionCard), findsWidgets); expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
