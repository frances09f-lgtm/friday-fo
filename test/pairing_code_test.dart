import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/link/device_link.dart';
import 'package:friday/services/link/pairing_code.dart';
class RealHttp extends HttpOverrides{}
void main(){
 final now=DateTime(2026,10,7,23);final key=base64UrlEncode(List.filled(32,1));
 test('roundtrip exact address and key',(){final raw=PairingCode.create('http://192.168.1.4:5000',key,now:now).encode();final code=PairingCode.decode(raw,now:now);expect(code.address,'http://192.168.1.4:5000');expect(code.key,key);});
 test('expired QR never accepted',(){final raw=PairingCode.create('http://192.168.1.4:5000',key,now:now).encode();expect(()=>PairingCode.decode(raw,now:now.add(const Duration(minutes:10))),throwsFormatException);});
 test('reject foreign URLs and non-key payloads',(){for(final address in ['https://example.com','http://8.8.8.8:4000','http://127.0.0.1:4000','http://192.168.1.3:4000/link']){expect(()=>PairingCode.decode(PairingCode.create(address,key,now:now).encode(),now:now),throwsFormatException);}expect(()=>PairingCode.decode(PairingCode.create('http://192.168.1.4:5000','bad',now:now).encode(),now:now),throwsFormatException);expect(()=>PairingCode.decode('{"type":"other"}',now:now),throwsFormatException);});
 test('decoded values fill exact pairing parameters without network execution',(){final code=PairingCode.decode(PairingCode.create('http://192.168.1.4:5000',key,now:now).encode(),now:now);expect(code.address,'http://192.168.1.4:5000');expect(code.key,key);});
}
