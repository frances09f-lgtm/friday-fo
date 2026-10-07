import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// Session-only, encrypted local link. Nothing is relayed through a server.
/// Pairing ends when either app exits. Calls/messages and shell code cannot
/// be executed remotely: the receiver uses a fixed command allowlist.
class LinkFailure implements Exception {
  final String code;
  final String message;
  const LinkFailure(this.code, this.message);
  @override
  String toString() => message;
}

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
    if (p.length != 4 || p.any((n) => n == null || n < 0 || n > 255))
      return false;
    return p[0] == 10 ||
        (p[0] == 192 && p[1] == 168) ||
        (p[0] == 172 && p[1]! >= 16 && p[1]! <= 31) ||
        p[0] == 127;
  }

  Future<void> join(String url, String key, String ownUrl) async {
    if (!addresses.contains(ownUrl)) {
      throw const LinkFailure('own_address',
          'Select My address on the shared network on this device.');
    }
    if (!validEndpoint(url)) {
      throw const LinkFailure('address',
          'Enter the other device address exactly as shown: http://IP:port, with no trailing slash.');
    }
    late List<int> bytes;
    try {
      bytes = base64Url.decode(key.trim());
    } catch (_) {
      throw const LinkFailure('key_format',
          'Copy the full current pairing key from the other device.');
    }
    if (bytes.length != 32) {
      throw const LinkFailure('key_format',
          'Copy the full current pairing key from the other device.');
    }
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
      throw const LinkFailure('clock',
          'The device clocks differ by more than 2 minutes. Set date and time automatically on both devices, then retry.');
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
      final body = await utf8.decoder
          .bind(res)
          .join()
          .timeout(const Duration(seconds: 5));
      Map<String, dynamic> reply;
      try {
        reply = await _open(jsonDecode(body) as Map<String, dynamic>);
      } on LinkFailure {
        rethrow;
      } catch (_) {
        throw const LinkFailure('authentication',
            'The other device rejected this key or returned an invalid reply. Enable a fresh link on both devices and copy its current key.');
      }
      if (reply['error'] == 'clock') {
        throw const LinkFailure('clock',
            'The device clocks differ by more than 2 minutes. Set date and time automatically on both devices, then retry.');
      }
      if (reply['error'] == 'source_address') {
        throw const LinkFailure('source_address',
            'My address does not match the network used for this connection. Select the shared Wi-Fi/hotspot address, not a VPN or virtual adapter.');
      }
      if (reply['error'] == 'already_paired') {
        throw const LinkFailure('already_paired',
            'The other Friday is already paired to another address. Disconnect and enable the link on both devices, then pair from one device only.');
      }
      if (res.statusCode != 200 || reply.containsKey('error')) {
        throw const LinkFailure('rejected',
            'The other Friday rejected pairing. Disconnect and enable the link on both devices, then retry.');
      }
      return reply;
    } on TimeoutException {
      throw const LinkFailure('timeout',
          'The other Friday did not reply in time. Keep both apps open, check the current IP and port, shared network and Windows Firewall permission.');
    } on SocketException {
      throw const LinkFailure('network',
          'Cannot reach the other Friday. Check its current IP and port, shared Wi-Fi/hotspot and Windows Firewall permission.');
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
          (peerUrl == null || peerUrl == j['endpoint']) &&
          validEndpoint(j['endpoint']?.toString() ?? '')) {
        final endpoint = j['endpoint'] as String;
        if (Uri.parse(endpoint).host !=
            req.connectionInfo?.remoteAddress.address)
          throw const LinkFailure('source_address', 'Wrong device address');
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
        throw const LinkFailure('already_paired', 'Not paired');
      }
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(await _seal(result)));
    } on LinkFailure catch (e) {
      req.response.statusCode = 403;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(await _seal({'error': e.code})));
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
