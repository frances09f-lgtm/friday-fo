import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:friday/services/link/device_link.dart';
import 'package:friday/ui/screens/device_link_screen.dart';
class PreviewLink extends DeviceLink{
 @override bool get running=>true;
}
void main(){testWidgets('QR displayed for chosen own network; form remains reviewable',(t)async{
 final l=PreviewLink()..addresses=['http://192.168.1.4:45678']..pairingKey='AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB'..status='Ready to pair';
 await t.runAsync(()async{final f=File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');final loader=FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(await f.readAsBytes())));await loader.load();});
 await t.binding.setSurfaceSize(const Size(412,1450));final key=GlobalKey();
 await t.pumpWidget(ChangeNotifierProvider<DeviceLink>.value(value:l,child:MaterialApp(home:RepaintBoundary(key:key,child:const DeviceLinkScreen()))));await t.pumpAndSettle();expect(find.textContaining('Refresh QR'),findsOneWidget);expect(t.takeException(),isNull);
 await t.runAsync(()async{final im=await(key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();final d=await im.toByteData(format:ui.ImageByteFormat.png);await File('/tmp/friday-qr.png').writeAsBytes(d!.buffer.asUint8List());});
 });}
