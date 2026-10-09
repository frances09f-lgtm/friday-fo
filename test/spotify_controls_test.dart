import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/intent_router.dart';
import 'package:friday/ui/screens/spotify_controls_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'Spotify outcomes separate request, unchanged, access and observed change',
      () {
    expect(IntentRouter.spotifyReply('spotify_verified_next'),
        contains('next verified'));
    expect(IntentRouter.spotifyReply('spotify_unverified_previous'),
        contains('No completion claimed'));
    expect(IntentRouter.spotifyReply('spotify_metadata_unavailable'),
        contains('not verified'));
    expect(IntentRouter.spotifyReply('no_spotify_session'),
        contains('Open Spotify'));
    expect(IntentRouter.spotifyReply('access_required'),
        contains('enable Friday yourself'));
    expect(IntentRouter.spotifyReply('spotify_already_playing'),
        contains('No new change'));
  });
  test(
      'native access ignores notification content and cannot dispatch to another app',
      () {
    final native = File(
            'android/app/src/main/kotlin/com/friday/assistant/SpotifySessionControl.kt')
        .readAsStringSync();
    expect(native, contains('it.packageName==SPOTIFY'));
    expect(native, contains('SpotifyObservation.trackChanged(beforeTrack,track(controller.metadata))'));
    expect(native, contains('unsupported_spotify_action'));
    expect(native, contains('ambiguous_spotify_session'));
    expect(native, isNot(contains('sbn.notification')));
    expect(native, isNot(contains('dispatchMediaKeyEvent')));
    expect(File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        contains('android.permission.BIND_NOTIFICATION_LISTENER_SERVICE'));
  });
  testWidgets(
      'setup requires manual access, renders caveat and session prerequisites',
      (t) async {
    await t.runAsync(() async {
      await (FontLoader('Roboto')
            ..addFont(Future.value(ByteData.sublistView(
                await File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')
                    .readAsBytes()))))
          .load();
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(ByteData.sublistView(await File(
                    '/home/sandbox/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
                .readAsBytes()))))
          .load();
    });
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('friday/device'),
            (call) async {
      calls.add(call.method);
      return call.method == 'spotifyState'
          ? {'enabled': false, 'spotifySessions': 0}
          : true;
    });
    await t.binding.setSurfaceSize(const Size(412, 915));
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark(useMaterial3: true),
            home: const SpotifyControlsScreen())));
    await t.pumpAndSettle();
    expect(find.text('Notification access: off'), findsOneWidget);
    expect(calls, ['spotifyState']);
    await t.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/friday-spotify-setup.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    });
    await t.tap(find.text('Review Android notification access'));
    await t.pumpAndSettle();
    expect(calls.last, 'spotifySettings');
  });
}
