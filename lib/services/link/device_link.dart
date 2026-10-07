import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// Session-only, encrypted local link. Nothing is relayed through a server.
/// Pairing ends when either app exits. Calls/messages and shell code cannot
/// be executed remotely: the receiver uses a fixed command allowlist.
class DeviceLink extends ChangeNotifier {
  HttpServer? _server;
  SecretKey? _key;
  String? pairingKey;
  String? peerUrl;
  List<String> addresses = [];
  String status = 'Not connected';
  final _cipher = AesGcm.with256bits();
  final _seen = <String>{};
  Future<String> Function(String)? onCommand;
  bool get running => _server != null;
  bool get paired => peerUrl != null;

  Future<void> start() async {
    if (running) return;
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    _key = SecretKey(bytes);
    pairingKey = base64UrlEncode(bytes);
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    addresses = [
      for (final n in await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: true))
        for (final a in n.addresses) 'http://${a.address}:${_server!.port}'
    ];
    status = 'Ready to pair';
    notifyListeners();
    _server!.listen(_receive);
  }

  static bool validEndpoint(String s) {
    final u = Uri.tryParse(s);
    if (u == null ||
        u.scheme != 'http' ||
        !u.hasPort ||
        u.userInfo.isNotEmpty ||
        (u.path.isNotEmpty || u.hasQuery || u.hasFragment)) return false;
    final p = u.host.split('.').map(int.tryParse).toList();
    if (p.length != 4 || p.any((n) => n == null || n! < 0 || n > 255))
      return false;
    return p[0] == 10 ||
        (p[0] == 192 && p[1] == 168) ||
        (p[0] == 172 && p[1]! >= 16 && p[1]! <= 31) ||
        p[0] == 127;
  }

  Future<void> join(String url, String key, String ownUrl) async {
    if (!validEndpoint(url) || !addresses.contains(ownUrl))
      throw const FormatException('Use the local address shown on each device');
    final bytes = base64Url.decode(key.trim());
    if (bytes.length != 32)
      throw const FormatException('Pairing key is not valid');
    final previous = _key;
    _key = SecretKey(bytes);
    try {
      final reply = await _post(url, {'kind': 'pair', 'endpoint': ownUrl});
      if (reply['ok'] != true)
        throw const FormatException('Pairing was not accepted');
      peerUrl = url;
      pairingKey = null;
      status = 'Connected';
      notifyListeners();
    } catch (_) {
      _key = previous;
      rethrow;
    }
  }

  Future<String> send(String command) async {
    final peer = peerUrl;
    if (peer == null) return 'Pair the other device from the header first.';
    try {
      final reply = await _post(peer, {'kind': 'command', 'text': command});
      return reply['result']?.toString() ??
          'The other device returned no result.';
    } catch (_) {
      return 'The other Friday could not be reached. Keep both apps open on the same Wi-Fi or hotspot.';
    }
  }

  Future<Map<String, dynamic>> _seal(Map<String, dynamic> value) async {
    final box = await _cipher.encrypt(
        utf8.encode(jsonEncode(
            {...value, 'at': DateTime.now().millisecondsSinceEpoch})),
        secretKey: _key!);
    return {
      'nonce': base64Encode(box.nonce),
      'data': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes)
    };
  }

  Future<Map<String, dynamic>> _open(Map<String, dynamic> raw,
      {bool replay = false}) async {
    final nonce = raw['nonce'] as String;
    if (replay && _seen.contains(nonce))
      throw const FormatException('Duplicate request');
    final bytes = await _cipher.decrypt(
        SecretBox(base64Decode(raw['data'] as String),
            nonce: base64Decode(nonce),
            mac: Mac(base64Decode(raw['mac'] as String))),
        secretKey: _key!);
    final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if ((DateTime.now().millisecondsSinceEpoch - (j['at'] as int)).abs() >
        120000)
      throw const FormatException('Device clocks differ or request expired');
    if (replay) {
      _seen.add(nonce);
      if (_seen.length > 1000) _seen.remove(_seen.first);
    }
    return j;
  }

  Future<Map<String, dynamic>> _post(
      String url, Map<String, dynamic> value) async {
    final client = HttpClient();
    client.findProxy = (_) => 'DIRECT';
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client
          .postUrl(Uri.parse('$url/link'))
          .timeout(const Duration(seconds: 5));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(await _seal(value)));
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200)
        throw const FormatException('Pairing or connection rejected');
      final body = await utf8.decoder
          .bind(res)
          .join()
          .timeout(const Duration(seconds: 5));
      return _open(jsonDecode(body) as Map<String, dynamic>);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _receive(HttpRequest req) async {
    try {
      if (req.method != 'POST' || req.uri.path != '/link')
        throw const FormatException('Unknown request');
      var size = 0;
      final bytes = <int>[];
      await for (final part in req.timeout(const Duration(seconds: 5))) {
        size += part.length;
        if (size > 16000) throw const FormatException('Request too large');
        bytes.addAll(part);
      }
      final j = await _open(
          jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
          replay: true);
      Map<String, dynamic> result;
      if (j['kind'] == 'pair' &&
          peerUrl == null &&
          validEndpoint(j['endpoint']?.toString() ?? '')) {
        final endpoint = j['endpoint'] as String;
        if (Uri.parse(endpoint).host !=
            req.connectionInfo?.remoteAddress.address)
          throw const FormatException('Wrong device address');
        peerUrl = endpoint;
        pairingKey = null;
        status = 'Connected';
        notifyListeners();
        result = {'ok': true};
      } else if (j['kind'] == 'command' &&
          paired &&
          Uri.parse(peerUrl!).host ==
              req.connectionInfo?.remoteAddress.address) {
        final text = j['text']?.toString() ?? '';
        if (text.isEmpty || text.length > 500)
          throw const FormatException('Invalid command');
        result = {
          'result': await onCommand?.call(text) ?? 'Friday is not ready yet.'
        };
      } else {
        throw const FormatException('Not paired');
      }
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(await _seal(result)));
    } catch (_) {
      req.response.statusCode = 403;
    }
    await req.response.close();
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _key = null;
    pairingKey = null;
    peerUrl = null;
    addresses = [];
    _seen.clear();
    status = 'Not connected';
    notifyListeners();
  }
}
