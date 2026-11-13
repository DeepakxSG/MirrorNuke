import 'dart:io';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'security.dart';

class Startup {
  static bool get supported => Platform.isWindows;

  static void setup() {
    if (!supported) return;
    launchAtStartup.setup(
      appName: 'MirrorNuke',
      appPath: Platform.resolvedExecutable,
      args: ['--autostart'],
    );
  }

  static Future<bool> isEnabled() async {
    if (!supported) return false;
    try {
      return await launchAtStartup.isEnabled();
    } catch (e) {
      AppLog.add('startup.isEnabled', e);
      return false;
    }
  }

  static Future<void> set(bool on) async {
    if (!supported) return;
    try {
      on ? await launchAtStartup.enable() : await launchAtStartup.disable();
    } catch (e) {
      AppLog.add('startup.set', e);
    }
  }
}
