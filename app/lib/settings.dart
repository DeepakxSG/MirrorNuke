import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'security.dart';

class Settings {
  String server, token, room, me, other, password, quality;
  bool share, view, shareAudio, playAudio, hostLocalServer;

  Settings({
    required this.server,
    required this.token,
    required this.room,
    required this.me,
    required this.other,
    required this.password,
    required this.share,
    required this.view,
    required this.shareAudio,
    required this.playAudio,
    required this.quality,
    required this.hostLocalServer,
  });

  static const _sec = FlutterSecureStorage();

  static Future<Settings> load({required String defMe, required String defOther}) async {
    final p = await SharedPreferences.getInstance();
    var password = '', token = '';
    try {
      password = await _sec.read(key: 'password') ?? '';
      token = await _sec.read(key: 'token') ?? '';
    } catch (e) {
      AppLog.add('settings.load', e);
    }
    return Settings(
      server: p.getString('server') ?? 'ws://192.168.1.10:8080',
      token: token,
      room: p.getString('room') ?? 'home-room',
      me: p.getString('me') ?? defMe,
      other: p.getString('other') ?? defOther,
      password: password,
      share: p.getBool('share') ?? true,
      view: p.getBool('view') ?? true,
      shareAudio: p.getBool('shareAudio') ?? true,
      playAudio: p.getBool('playAudio') ?? true,
      quality: p.getString('quality') ?? 'movie',
      hostLocalServer: p.getBool('hostLocalServer') ?? Platform.isWindows,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('server', server);
    await p.setString('room', room);
    await p.setString('me', me);
    await p.setString('other', other);
    await p.setBool('share', share);
    await p.setBool('view', view);
    await p.setBool('shareAudio', shareAudio);
    await p.setBool('playAudio', playAudio);
    await p.setString('quality', quality);
    await p.setBool('hostLocalServer', hostLocalServer);
    try {
      await _sec.write(key: 'password', value: password);
      await _sec.write(key: 'token', value: token);
    } catch (e) {
      AppLog.add('settings.save', e);
    }
  }
}
