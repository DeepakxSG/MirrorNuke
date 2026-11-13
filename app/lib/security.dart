import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

final _nameRe = RegExp(r'^[A-Za-z0-9_-]{1,32}$');
final _roomRe = RegExp(r'^[A-Za-z0-9_-]{4,32}$');
final _fpRe = RegExp(r'a=fingerprint:(\S+ \S+)');

bool validName(String s) => _nameRe.hasMatch(s);
bool validRoom(String s) => _roomRe.hasMatch(s);

bool validUrl(String s) {
  final u = Uri.tryParse(s);
  return u != null && (u.scheme == 'ws' || u.scheme == 'wss') && u.host.isNotEmpty && s.length <= 200;
}

String? validPassword(String p) => p.length >= 8 && p.length <= 128 ? null : 'Password must be 8 to 128 characters';

String randomNonce([int bytes = 24]) {
  final r = Random.secure();
  return base64Url.encode(List<int>.generate(bytes, (_) => r.nextInt(256)));
}

String fingerprintOf(String? sdp) => _fpRe.firstMatch(sdp ?? '')?.group(1) ?? '';

String proof(String password, String role, String nonce, String roomKey, String senderFp, String viewerFp) {
  final key = utf8.encode(password);
  final msg = utf8.encode('$role|$nonce|$roomKey|$senderFp|$viewerFp');
  return Hmac(sha256, key).convert(msg).toString();
}

bool constEq(String a, String b) {
  if (a.length != b.length) return false;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return d == 0;
}

double? unit(dynamic v) {
  if (v is! num) return null;
  final d = v.toDouble();
  if (!d.isFinite) return null;
  return d.clamp(0.0, 1.0);
}

String cleanText(String s) {
  final c = s.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '');
  return c.length > 200 ? c.substring(0, 200) : c;
}
