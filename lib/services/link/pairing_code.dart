import 'dart:convert';
import 'device_link.dart';

/// Session-only local code. Scanning fills the form, never executes a command.
class PairingCode {
  final String address, key;
  final int expires;
  const PairingCode(this.address, this.key, this.expires);
  String encode() => jsonEncode({
        'type': 'friday-local-pair',
        'version': 1,
        'address': address,
        'key': key,
        'expires': expires
      });
  static PairingCode create(String address, String key, {DateTime? now}) =>
      PairingCode(
          address,
          key,
          (now ?? DateTime.now())
              .add(const Duration(minutes: 10))
              .millisecondsSinceEpoch);
  static PairingCode decode(String raw, {DateTime? now}) {
    if (raw.length > 2000)
      throw const FormatException('Not a Friday pairing QR');
    final j = jsonDecode(raw);
    if (j is! Map || j['type'] != 'friday-local-pair' || j['version'] != 1)
      throw const FormatException('Not a Friday pairing QR');
    final a = j['address'], k = j['key'], e = j['expires'];
    if (a is! String ||
        k is! String ||
        e is! int ||
        !DeviceLink.validEndpoint(a) ||
        Uri.parse(a).host == '127.0.0.1')
      throw const FormatException('Invalid local pairing address');
    try {
      if (base64Url.decode(k).length != 32) throw const FormatException();
    } catch (_) {
      throw const FormatException('Invalid pairing key');
    }
    final t = (now ?? DateTime.now()).millisecondsSinceEpoch;
    if (e <= t || e > t + 11 * 60 * 1000)
      throw const FormatException(
          'Pairing QR expired or clocks differ. Refresh it on the other device.');
    return PairingCode(a, k, e);
  }
}
