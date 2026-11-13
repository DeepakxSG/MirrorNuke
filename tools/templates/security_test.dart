import 'package:flutter_test/flutter_test.dart';
import 'package:mirrornuke_app/security.dart';

void main() {
  test('Room, device name, URL, and password validators', () {
    expect(validRoom('home-room'), isTrue);
    expect(validRoom('ab'), isFalse);
    expect(validName('pc_1'), isTrue);
    expect(validName('../bad'), isFalse);
    expect(validUrl('ws://192.168.1.10:8080'), isTrue);
    expect(validUrl('http://192.168.1.10:8080'), isFalse);
    expect(validPassword('secret123'), isNull);
    expect(validPassword('short'), isNotNull);
  });

  test('DTLS fingerprint extraction and HMAC proof binding', () {
    const sdp = 'v=0\r\na=fingerprint:sha-256 AA:BB:CC:DD\r\n';
    expect(fingerprintOf(sdp), 'sha-256 AA:BB:CC:DD');
    final p1 = proof('pass1234', 'V', 'nonce1', 'room:pc', 'fpS', 'fpV');
    final p2 = proof('pass1234', 'V', 'nonce1', 'room:pc', 'fpS', 'fpV');
    final tampered = proof('pass1234', 'V', 'nonce1', 'room:pc', 'fpEvil', 'fpV');
    expect(constEq(p1, p2), isTrue);
    expect(constEq(p1, tampered), isFalse);
  });
}
