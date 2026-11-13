import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

final class _WaveFormatEx extends Struct {
  @Uint16()
  external int wFormatTag;
  @Uint16()
  external int nChannels;
  @Uint32()
  external int nSamplesPerSec;
  @Uint32()
  external int nAvgBytesPerSec;
  @Uint16()
  external int nBlockAlign;
  @Uint16()
  external int wBitsPerSample;
  @Uint16()
  external int cbSize;
}

final class _WaveHdr extends Struct {
  external Pointer<Uint8> lpData;
  @Uint32()
  external int dwBufferLength;
  @Uint32()
  external int dwBytesRecorded;
  @IntPtr()
  external int dwUser;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int dwLoops;
  external Pointer<_WaveHdr> lpNext;
  @IntPtr()
  external int reserved;
}

typedef _WaveOutOpenNative = Uint32 Function(
  Pointer<IntPtr> phwo,
  Uint32 uDeviceID,
  Pointer<_WaveFormatEx> pwfx,
  IntPtr dwCallback,
  IntPtr dwInstance,
  Uint32 fdwOpen,
);
typedef _WaveOutOpenDart = int Function(
  Pointer<IntPtr> phwo,
  int uDeviceID,
  Pointer<_WaveFormatEx> pwfx,
  int dwCallback,
  int dwInstance,
  int fdwOpen,
);

typedef _WaveOutHdrNative = Uint32 Function(IntPtr hwo, Pointer<_WaveHdr> pwh, Uint32 cbwh);
typedef _WaveOutHdrDart = int Function(int hwo, Pointer<_WaveHdr> pwh, int cbwh);

typedef _WaveOutSimpleNative = Uint32 Function(IntPtr hwo);
typedef _WaveOutSimpleDart = int Function(int hwo);

typedef _WaveOutSetVolNative = Uint32 Function(IntPtr hwo, Uint32 dwVolume);
typedef _WaveOutSetVolDart = int Function(int hwo, int dwVolume);

/// Decodes incoming 4:1 IMA-ADPCM frames from Android and plays them directly
/// through Windows PC speakers via winmm.dll waveOut.
class WinSpeakerPlayer {
  static const int _ringSize = 24;
  static const int _maxSlotBytes = 16384;
  static const int _whdrDone = 0x00000001;
  static const int _whdrPrepared = 0x00000002;

  DynamicLibrary? _winmm;
  late _WaveOutOpenDart _waveOutOpen;
  late _WaveOutHdrDart _waveOutPrepareHeader;
  late _WaveOutHdrDart _waveOutWrite;
  late _WaveOutHdrDart _waveOutUnprepareHeader;
  late _WaveOutSimpleDart _waveOutReset;
  late _WaveOutSimpleDart _waveOutClose;
  late _WaveOutSetVolDart _waveOutSetVolume;

  int _hWaveOut = 0;
  bool _opened = false;
  bool muted = false;
  double volume = 1.0;

  final List<Pointer<_WaveHdr>> _hdrs = [];
  final List<Pointer<Uint8>> _bufs = [];
  int _slot = 0;

  bool open() {
    if (!Platform.isWindows) return false;
    if (_opened) return true;
    try {
      _winmm = DynamicLibrary.open('winmm.dll');
      _waveOutOpen = _winmm!.lookupFunction<_WaveOutOpenNative, _WaveOutOpenDart>('waveOutOpen');
      _waveOutPrepareHeader =
          _winmm!.lookupFunction<_WaveOutHdrNative, _WaveOutHdrDart>('waveOutPrepareHeader');
      _waveOutWrite = _winmm!.lookupFunction<_WaveOutHdrNative, _WaveOutHdrDart>('waveOutWrite');
      _waveOutUnprepareHeader =
          _winmm!.lookupFunction<_WaveOutHdrNative, _WaveOutHdrDart>('waveOutUnprepareHeader');
      _waveOutReset =
          _winmm!.lookupFunction<_WaveOutSimpleNative, _WaveOutSimpleDart>('waveOutReset');
      _waveOutClose =
          _winmm!.lookupFunction<_WaveOutSimpleNative, _WaveOutSimpleDart>('waveOutClose');
      _waveOutSetVolume =
          _winmm!.lookupFunction<_WaveOutSetVolNative, _WaveOutSetVolDart>('waveOutSetVolume');

      final fmt = calloc<_WaveFormatEx>();
      fmt.ref.wFormatTag = 1; // WAVE_FORMAT_PCM
      fmt.ref.nChannels = 2;
      fmt.ref.nSamplesPerSec = 48000;
      fmt.ref.wBitsPerSample = 16;
      fmt.ref.nBlockAlign = 4;
      fmt.ref.nAvgBytesPerSec = 48000 * 4;
      fmt.ref.cbSize = 0;

      final phwo = calloc<IntPtr>();
      const waveMapper = 0xFFFFFFFF;
      final res = _waveOutOpen(phwo, waveMapper, fmt, 0, 0, 0);
      _hWaveOut = phwo.value;
      calloc.free(fmt);
      calloc.free(phwo);

      if (res != 0 || _hWaveOut == 0) return false;

      for (var i = 0; i < _ringSize; i++) {
        final hdr = calloc<_WaveHdr>();
        final buf = calloc<Uint8>(_maxSlotBytes);
        hdr.ref.lpData = buf;
        hdr.ref.dwFlags = _whdrDone;
        _hdrs.add(hdr);
        _bufs.add(buf);
      }

      _opened = true;
      setVolume(volume);
      return true;
    } catch (_) {
      return false;
    }
  }

  void setVolume(double v) {
    volume = v.clamp(0.0, 1.0);
    if (!_opened || _hWaveOut == 0) return;
    final chan = (muted ? 0 : (volume * 0xFFFF).round()).clamp(0, 0xFFFF);
    _waveOutSetVolume(_hWaveOut, chan | (chan << 16));
  }

  void setMuted(bool m) {
    muted = m;
    setVolume(volume);
  }

  void playPcm(Uint8List pcmBytes) {
    if (!Platform.isWindows || muted || pcmBytes.isEmpty) return;
    if (!_opened && !open()) return;
    final len = pcmBytes.length.clamp(0, _maxSlotBytes);
    final hdr = _hdrs[_slot];
    final buf = _bufs[_slot];
    _slot = (_slot + 1) % _ringSize;

    if ((hdr.ref.dwFlags & _whdrPrepared) != 0) {
      _waveOutUnprepareHeader(_hWaveOut, hdr, sizeOf<_WaveHdr>());
    }
    buf.asTypedList(len).setAll(0, pcmBytes.sublist(0, len));
    hdr.ref.lpData = buf;
    hdr.ref.dwBufferLength = len;
    hdr.ref.dwFlags = 0;
    hdr.ref.dwLoops = 0;

    if (_waveOutPrepareHeader(_hWaveOut, hdr, sizeOf<_WaveHdr>()) == 0) {
      _waveOutWrite(_hWaveOut, hdr, sizeOf<_WaveHdr>());
    }
  }

  void close() {
    if (!_opened) return;
    _opened = false;
    try {
      if (_hWaveOut != 0) {
        _waveOutReset(_hWaveOut);
        for (var i = 0; i < _hdrs.length; i++) {
          if ((_hdrs[i].ref.dwFlags & _whdrPrepared) != 0) {
            _waveOutUnprepareHeader(_hWaveOut, _hdrs[i], sizeOf<_WaveHdr>());
          }
          calloc.free(_bufs[i]);
          calloc.free(_hdrs[i]);
        }
        _waveOutClose(_hWaveOut);
      }
    } catch (_) {}
    _hdrs.clear();
    _bufs.clear();
    _hWaveOut = 0;
  }
}

class ImaAdpcmDecoder {
  static const List<int> _indexTable = [
    -1, -1, -1, -1, 2, 4, 6, 8,
    -1, -1, -1, -1, 2, 4, 6, 8,
  ];
  static const List<int> _stepTable = [
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17,
    19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
    50, 55, 60, 66, 73, 80, 88, 97, 107, 118,
    130, 143, 157, 173, 190, 209, 230, 253, 279, 307,
    337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
    876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
    2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358,
    5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
    15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767,
  ];

  static Uint8List decodeStereoFrame(Uint8List packet) {
    if (packet.length < 9) return Uint8List(0);
    final bd = ByteData.sublistView(packet);
    var predL = bd.getInt16(0, Endian.little);
    var idxL = packet[2].clamp(0, 88);
    var predR = bd.getInt16(4, Endian.little);
    var idxR = packet[6].clamp(0, 88);

    final payloadLen = packet.length - 8;
    final totalFrames = 1 + payloadLen;
    final out = ByteData(totalFrames * 4);
    out.setInt16(0, predL, Endian.little);
    out.setInt16(2, predR, Endian.little);

    for (var i = 0; i < payloadLen; i++) {
      final packed = packet[8 + i];
      final codeL = packed & 0x0F;
      final codeR = (packed >> 4) & 0x0F;

      final stepL = _stepTable[idxL];
      var diffL = stepL >> 3;
      if ((codeL & 4) != 0) diffL += stepL;
      if ((codeL & 2) != 0) diffL += stepL >> 1;
      if ((codeL & 1) != 0) diffL += stepL >> 2;
      predL += ((codeL & 8) != 0) ? -diffL : diffL;
      predL = predL.clamp(-32768, 32767);
      idxL = (idxL + _indexTable[codeL]).clamp(0, 88);

      final stepR = _stepTable[idxR];
      var diffR = stepR >> 3;
      if ((codeR & 4) != 0) diffR += stepR;
      if ((codeR & 2) != 0) diffR += stepR >> 1;
      if ((codeR & 1) != 0) diffR += stepR >> 2;
      predR += ((codeR & 8) != 0) ? -diffR : diffR;
      predR = predR.clamp(-32768, 32767);
      idxR = (idxR + _indexTable[codeR]).clamp(0, 88);

      final off = (i + 1) * 4;
      out.setInt16(off, predL, Endian.little);
      out.setInt16(off + 2, predR, Endian.little);
    }
    return out.buffer.asUint8List();
  }
}
