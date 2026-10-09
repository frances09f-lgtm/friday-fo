import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/link/device_link.dart';
import 'dart:convert';
import 'dart:io';

class RealHttp extends HttpOverrides {}

void main() {
  test('only numeric private-network endpoints accepted', () {
    expect(DeviceLink.validEndpoint('http://192.168.1.3:4000'), true);
    expect(DeviceLink.validEndpoint('http://10.0.0.2:4000'), true);
    for (final s in [
      'http://8.8.8.8:4000',
      'http://example.com:4000',
      'http://user@192.168.1.3:4000',
      'http://192.168.1.3:4000/path'
    ]) {
      expect(DeviceLink.validEndpoint(s), false, reason: s);
    }
  });
  test('two local peers pair, encrypt and send commands both ways', () async {
    HttpOverrides.global = RealHttp();
    final a = DeviceLink(), b = DeviceLink();
    addTearDown(() async {
      await a.stop();
      await b.stop();
    });
    await a.start();
    await b.start();
    a.onCommand = (s) async => 'A executed: $s';
    b.onCommand = (s) async => 'B executed: $s';
    await b.join(a.addresses.first, a.pairingKey!, b.addresses.first);
    expect(a.paired, true);
    expect(b.paired, true);
    expect(await b.send('open camera'), 'A executed: open camera');
    expect(await a.send('volume up'), 'B executed: volume up');
    expect(a.pairingKey, isNull);
    expect(b.pairingKey, isNull);
  });
  test('unpaired/plaintext clients cannot execute commands', () async {
    HttpOverrides.global = RealHttp();
    final a = DeviceLink();
    await a.start();
    addTearDown(a.stop);
    var called = false;
    a.onCommand = (s) async {
      called = true;
      return 'bad';
    };
    final c = HttpClient();
    addTearDown(() => c.close(force: true));
    final req = await c.postUrl(Uri.parse('${a.addresses.first}/link'));
    req.write(jsonEncode({'kind': 'command', 'text': 'open camera'}));
    final res = await req.close();
    expect(res.statusCode, 403);
    expect(called, false);
  });
  test('wrong pairing key is rejected', () async {
    HttpOverrides.global = RealHttp();
    final a = DeviceLink(), b = DeviceLink();
    await a.start();
    await b.start();
    addTearDown(() async {
      await a.stop();
      await b.stop();
    });
    await expectLater(
        b.join(a.addresses.first, base64UrlEncode(List.filled(32, 0)),
            b.addresses.first),
        throwsA(anything));
    expect(a.paired, false);
    expect(b.paired, false);
  });
  test('missing own address reports selection before opening a connection',
      () async {
    final a = DeviceLink();
    await expectLater(
        a.join('http://192.168.1.2:1234', 'wrong', ''),
        throwsA(
            isA<LinkFailure>().having((e) => e.code, 'code', 'own_address')));
  });
  test('retry after lost reply recovers the same authenticated pair', () async {
    HttpOverrides.global = RealHttp();
    final a = DeviceLink(), b = DeviceLink();
    await a.start();
    await b.start();
    addTearDown(() async {
      await a.stop();
      await b.stop();
    });
    final key = a.pairingKey!;
    await b.join(a.addresses.first, key, b.addresses.first);
    b.peerUrl = null; // Sender lost the response, receiver accepted it.
    await b.join(a.addresses.first, key, b.addresses.first);
    expect(a.paired, true);
    expect(b.paired, true);
    a.onCommand = (s) async => 'recovered';
    expect(await b.send('open camera'), 'recovered');
  });
  test('wrong selected network address has a specific encrypted error',
      () async {
    HttpOverrides.global = RealHttp();
    final a = DeviceLink(), b = DeviceLink();
    await a.start();
    await b.start();
    addTearDown(() async {
      await a.stop();
      await b.stop();
    });
    const wrong = 'http://192.168.200.200:12345';
    b.addresses.add(wrong);
    await expectLater(
        b.join(a.addresses.first, a.pairingKey!, wrong),
        throwsA(isA<LinkFailure>()
            .having((e) => e.code, 'code', 'source_address')));
    expect(a.paired, false);
    expect(b.paired, false);
  });
  test('invalid endpoint and malformed key report distinct errors', () async {
    HttpOverrides.global = RealHttp();
    final a = DeviceLink();
    await a.start();
    addTearDown(a.stop);
    await expectLater(a.join('192.168.1.4', 'wrong', a.addresses.first),
        throwsA(isA<LinkFailure>().having((e) => e.code, 'code', 'address')));
    await expectLater(
        a.join('http://192.168.1.4:1234', '!notbase64!', a.addresses.first),
        throwsA(
            isA<LinkFailure>().having((e) => e.code, 'code', 'key_format')));
  });
  test('closed port reports network error rather than key error', () async {
    HttpOverrides.global = RealHttp();
    final a = DeviceLink(), b = DeviceLink();
    await a.start();
    await b.start();
    addTearDown(a.stop);
    final endpoint = b.addresses.first, key = b.pairingKey!;
    await b.stop();
    await expectLater(a.join(endpoint, key, a.addresses.first),
        throwsA(isA<LinkFailure>().having((e) => e.code, 'code', 'network')));
  });
}
