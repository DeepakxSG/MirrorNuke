import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'security.dart';

class AndroidControl {
  static const _ch = MethodChannel('mirrornuke/control');
  static const _audioEvents = EventChannel('mirrornuke/audio_stream');

  static Future<bool> isEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('isEnabled') ?? false;
    } catch (e) {
      AppLog.add('android.isEnabled', e);
      return false;
    }
  }

  static Future<void> openSettings() async {
    try {
      await _ch.invokeMethod('openSettings');
    } catch (e) {
      AppLog.add('android.openSettings', e);
    }
  }

  static Future<void> gesture(List<double> points, int durMs) async {
    try {
      await _ch.invokeMethod('gesture', {'points': points, 'dur': durMs});
    } catch (e) {
      AppLog.add('android.gesture', e);
    }
  }

  /// Makes Android redraw once so a still screen delivers a first video frame.
  static Future<void> kick() async {
    try {
      await _ch.invokeMethod('kick');
    } catch (e) {
      AppLog.add('android.kick', e);
    }
  }

  static Future<void> global(String action) async {
    try {
      await _ch.invokeMethod('global', {'a': action});
    } catch (e) {
      AppLog.add('android.global', e);
    }
  }

  static Future<void> text(String s) async {
    try {
      await _ch.invokeMethod('text', {'s': s});
    } catch (e) {
      AppLog.add('android.text', e);
    }
  }

  static Future<void> backspace() async {
    try {
      await _ch.invokeMethod('backspace');
    } catch (e) {
      AppLog.add('android.backspace', e);
    }
  }

  static Future<bool> startCaptureService() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch
              .invokeMethod<bool>('startCapture')
              .timeout(const Duration(seconds: 8)) ??
          false;
    } catch (e) {
      AppLog.add('android.startCaptureService', e);
      return false;
    }
  }

  static Future<bool> startAudioCapture() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('startAudioCapture') ?? false;
    } catch (e) {
      AppLog.add('android.startAudioCapture', e);
      return false;
    }
  }

  static Future<void> stopAudioCapture() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('stopAudioCapture');
    } catch (e) {
      AppLog.add('android.stopAudioCapture', e);
    }
  }

  static Stream<Uint8List> get encodedAudioStream {
    if (!Platform.isAndroid) return const Stream.empty();
    return _audioEvents
        .receiveBroadcastStream()
        .where((e) => e is Uint8List)
        .cast<Uint8List>();
  }

  static Future<void> playAudioPcm(Uint8List pcmBytes) async {
    if (!Platform.isAndroid || pcmBytes.isEmpty) return;
    try {
      await _ch.invokeMethod('playAudioPcm', {'pcm': pcmBytes});
    } catch (e) {
      AppLog.add('android.playAudioPcm', e);
    }
  }

  static Future<void> stopAudioPlayback() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('stopAudioPlayback');
    } catch (e) {
      AppLog.add('android.stopAudioPlayback', e);
    }
  }

  static Future<void> stopCaptureService() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('stopCapture');
    } catch (e) {
      AppLog.add('android.stopCaptureService', e);
    }
  }
}
