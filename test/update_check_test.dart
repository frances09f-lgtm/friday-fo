import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:friday/services/update_check.dart';
import 'package:friday/ui/stitch_style.dart';

void main() {
 setUpAll(() async {
  for(final pair in [['Inter','Inter.ttf'],['SpaceGrotesk','SpaceGrotesk.ttf']]) {
   await (FontLoader(pair[0])..addFont(rootBundle.load('assets/fonts/${pair[1]}'))).load();
  }
 });
 test('only final numeric release tags qualify', () {
  expect(releaseBuild({'tag_name':'v56','draft':false,'prerelease':false}),56);
  for(final tag in ['v55-beta','main','v0','v']) {
   expect(releaseBuild({'tag_name':tag,'draft':false,'prerelease':false}),isNull);
  }
  expect(releaseBuild({'tag_name':'v56','draft':true,'prerelease':false}),isNull);
  expect(releaseBuild({'tag_name':'v56','draft':false,'prerelease':true}),isNull);
 });
 for(final width in [320.0,390.0]) {
  testWidgets('popup Update opens Firebase $width', (t) async {
   t.view.physicalSize=Size(width,800);t.view.devicePixelRatio=1;
   SharedPreferences.setMockInitialValues({});final prefs=await SharedPreferences.getInstance();
   late BuildContext context;final key=GlobalKey();
   await t.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:Stitch.theme(),home:Builder(builder:(c){context=c;return const Scaffold(body:Center(child:Text('Friday')));}))));
   bool opened=false;FridayUpdateCheck.opener=() async{opened=true;};
   final f=FridayUpdateCheck.run(context,installed:()async=>55,latest:()async=>56,preferences:prefs);
   await t.pumpAndSettle();expect(find.text('New version available'),findsOneWidget);expect(t.takeException(),isNull);
   await t.runAsync(() async{
    final image=await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
    await File('/downloads/friday-popup-${width.toInt()}.png').writeAsBytes(bytes!.buffer.asUint8List());image.dispose();
   });
   await t.tap(find.text('Update'));await t.pumpAndSettle();await f;expect(opened,true);
   expect(fridayUpdatePage,contains('bdf178861eee975f0a46f4'));
  });
 }
 testWidgets('Later prevents another fetch and current/offline stay quiet',(t)async{
  SharedPreferences.setMockInitialValues({});final p=await SharedPreferences.getInstance();late BuildContext c;
  await t.pumpWidget(MaterialApp(home:Builder(builder:(ctx){c=ctx;return const Scaffold();})));
  final f=FridayUpdateCheck.run(c,installed:()async=>55,latest:()async=>56,preferences:p);await t.pumpAndSettle();await t.tap(find.text('Later'));await t.pumpAndSettle();await f;
  expect(p.getInt(FridayUpdateCheck.laterKey),greaterThan(DateTime.now().millisecondsSinceEpoch));
  var calls=0;await FridayUpdateCheck.run(c,installed:()async=>55,latest:()async{calls++;return 57;},preferences:p);expect(calls,0);
  for(final n in [55,54,null]) {
   await p.clear();await FridayUpdateCheck.run(c,installed:()async=>55,latest:()async=>n,preferences:p);await t.pumpAndSettle();expect(find.text('New version available'),findsNothing);
  }
 });
}
