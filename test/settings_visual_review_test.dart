import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:friday/services/storage/settings_store.dart';
import 'package:friday/services/ai/local_model_service.dart';
import 'package:friday/ui/screens/settings_screen.dart';
import 'package:friday/ui/orion_style.dart';
void main() {
 testWidgets('review the current Settings in both themes with real fonts', (t) async {
  SharedPreferences.setMockInitialValues({}); final prefs = await SharedPreferences.getInstance();
  final channel = const MethodChannel('friday/device');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => {'microphone': true, 'overlay': false});
  addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
  await t.runAsync(() async {
   for (final name in ['Inter','SpaceGrotesk','JetBrainsMono']) {
    final font = FontLoader(name)..addFont(Future.value(ByteData.sublistView(await File('assets/fonts/$name.ttf').readAsBytes()))); await font.load();
   }
   final icons = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(await File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes()))); await icons.load();
  });
  final output = Directory('/tmp/friday-settings-evidence')..createSync(recursive:true);
  await t.binding.setSurfaceSize(const Size(412,892));
  for (final dark in [false,true]) {
   final key = GlobalKey();
   await t.pumpWidget(MultiProvider(providers: [ChangeNotifierProvider<SettingsStore>.value(value: SettingsStore(const FlutterSecureStorage(),prefs)),ChangeNotifierProvider<LocalModelService>.value(value: LocalModelService())],child: RepaintBoundary(key:key,child:MaterialApp(theme:dark?Orion.dark():Orion.light(),home:const SettingsScreen()))));
   Future<void> shot(String suffix) async {
    await t.pump(const Duration(milliseconds:800)); await t.pumpAndSettle(); expect(t.takeException(),isNull);
    await t.runAsync(() async { final im=await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio:2); final b=await im.toByteData(format:ui.ImageByteFormat.png); await File('${output.path}/${dark?'dark':'light'}-$suffix.png').writeAsBytes(b!.buffer.asUint8List()); im.dispose(); });
   }
   Future<void> reveal(String text) async { await t.scrollUntilVisible(find.text(text), 250, scrollable: find.byType(Scrollable).first); await t.pump(const Duration(milliseconds:800)); }
   await shot('top');
   await t.ensureVisible(find.text('AI & models')); await t.pumpAndSettle(); await t.tap(find.text('AI & models')); await t.pumpAndSettle();
   await reveal('Cloud fallback keys'); await t.tap(find.text('Cloud fallback keys')); await t.pumpAndSettle(); await shot('models');
   await reveal('Permissions & phone controls'); await t.tap(find.text('Permissions & phone controls')); await t.pumpAndSettle(); await shot('permissions');
   await reveal('Save changes'); await shot('save');
   await t.pumpWidget(const SizedBox.shrink());
  }
  await t.binding.setSurfaceSize(null);
 });
}
