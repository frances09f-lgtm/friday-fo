import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/ai/model_download.dart';

void main() {
  HttpOverrides.global = null;
  for (final ignore in [false, true]) {
    testWidgets('restart resumes saved partial bytes; ignore Range=$ignore',
        (t) async {
      await t.runAsync(() async {
        HttpOverrides.global = null;
        final d = await Directory.systemTemp.createTemp('model-resume');
        final f = File('${d.path}/model.part');
        await f.writeAsBytes([1, 2]);
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        String? range;
        server.listen((r) {
          range = r.headers.value('range');
          r.response.statusCode = ignore ? 200 : 206;
          if (!ignore) r.response.headers.set('content-range', 'bytes 2-3/4');
          r.response.add(ignore ? [1, 2, 3, 4] : [3, 4]);
          r.response.close();
        });
        try {
          await ModelDownload.fetch(
              url: Uri.parse('http://127.0.0.1:${server.port}/model'),
              part: f,
              expectedBytes: 4,
              cancelled: () => false,
              progress: (_) {},
              clientChanged: (_) {});
          expect(range, 'bytes=2-');
          expect(await f.readAsBytes(), [1, 2, 3, 4]);
        } finally {
          await server.close(force: true);
          await d.delete(recursive: true);
        }
      });
    });
  }
  testWidgets('wrong range keeps saved file for retry', (t) async {
    await t.runAsync(() async {
      HttpOverrides.global = null;
      final d = await Directory.systemTemp.createTemp('model-range');
      final f = File('${d.path}/model.part');
      await f.writeAsBytes([1, 2]);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) {
        r.response.statusCode = 206;
        r.response.headers.set('content-range', 'bytes 0-3/4');
        r.response.add([1, 2, 3, 4]);
        r.response.close();
      });
      try {
        await expectLater(
            ModelDownload.fetch(
                url: Uri.parse('http://127.0.0.1:${server.port}/model'),
                part: f,
                expectedBytes: 4,
                cancelled: () => false,
                progress: (_) {},
                clientChanged: (_) {}),
            throwsStateError);
        expect(await f.readAsBytes(), [1, 2]);
      } finally {
        await server.close(force: true);
        await d.delete(recursive: true);
      }
    });
  });
}
