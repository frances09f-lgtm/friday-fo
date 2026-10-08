import 'dart:async';
import 'dart:io';

/// Range download. The file itself is the resume checkpoint, including after
/// process death. A server ignoring Range restarts safely rather than appending.
class ModelDownload {
  static Future<void> fetch(
      {required Uri url,
      required File part,
      required int expectedBytes,
      required bool Function() cancelled,
      required void Function(int) progress,
      required void Function(HttpClient?) clientChanged,
      Duration timeout = const Duration(minutes: 2)}) async {
    var offset = await part.exists() ? await part.length() : 0;
    if (offset > expectedBytes) {
      await part.delete();
      offset = 0;
    }
    progress(offset);
    if (offset == expectedBytes) return;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 45);
    clientChanged(client);
    try {
      final request = await client.getUrl(url);
      if (offset > 0) request.headers.set('Range', 'bytes=$offset-');
      final response = await request.close().timeout(timeout);
      if (response.statusCode == 200) {
        offset = 0;
        progress(0);
      } else if (response.statusCode == 206) {
        if (!(response.headers.value('content-range') ?? '')
            .startsWith('bytes $offset-'))
          throw StateError(
              'Server returned the wrong resume range. Partial file kept; retry.');
      } else {
        throw HttpException(
            'Download HTTP ${response.statusCode}. Partial file kept; retry.');
      }
      final sink =
          part.openWrite(mode: offset > 0 ? FileMode.append : FileMode.write);
      try {
        await for (final chunk in response.timeout(timeout)) {
          if (cancelled()) throw StateError('Cancelled');
          offset += chunk.length;
          if (offset > expectedBytes)
            throw StateError(
                'Download exceeded expected size; retry to restart.');
          sink.add(chunk);
          progress(offset);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (await part.length() != expectedBytes)
        throw StateError(
            'Incomplete download. Partial file kept; retry to resume.');
    } finally {
      client.close(force: true);
      clientChanged(null);
    }
  }
}
