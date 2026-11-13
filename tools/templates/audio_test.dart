import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrornuke_app/win_audio.dart';

Uint8List _buildAdpcmPacket(int seq, int predL, int idxL, int predR, int idxR, List<int> nibbles) {
  final out = ByteData(10 + nibbles.length);
  out.setUint16(0, seq, Endian.little);
  out.setInt16(2, predL, Endian.little);
  out.setUint8(4, idxL);
  out.setInt16(6, predR, Endian.little);
  out.setUint8(8, idxR);
  for (var i = 0; i < nibbles.length; i++) {
    out.setUint8(10 + i, nibbles[i]);
  }
  return out.buffer.asUint8List();
}

void main() {
  test('ImaAdpcmDecoder decodes 10-byte sequenced header and stereo samples accurately', () {
    // idx=0 => step=7, nibble=0 => diff = 7>>3 = 0 => pred remains 1000 / -1000
    final pkt = _buildAdpcmPacket(42, 1000, 0, -1000, 0, [0x00, 0x00]);
    final decoded = ImaAdpcmDecoder.decodePacket(pkt);
    expect(decoded, isNotNull);
    expect(decoded!.seq, 42);
    expect(decoded.pcm.length, 12); // 3 stereo frames * 4 bytes
    final samples = ByteData.sublistView(decoded.pcm);
    expect(samples.getInt16(0, Endian.little), 1000);
    expect(samples.getInt16(2, Endian.little), -1000);
    expect(samples.getInt16(4, Endian.little), 1000);
    expect(samples.getInt16(6, Endian.little), -1000);
  });

  test('AudioJitterBuffer reorders out-of-order frames and drops late frames', () {
    final jb = AudioJitterBuffer(targetFrames: 2, maxFrames: 4);
    final f0 = Uint8List.fromList([0, 0, 0, 0]);
    final f1 = Uint8List.fromList([1, 1, 1, 1]);
    final f2 = Uint8List.fromList([2, 2, 2, 2]);
    final late = Uint8List.fromList([9, 9, 9, 9]);

    // Frame 0 arrives first -> buffered until targetFrames (2) reached
    expect(jb.push(0, f0), isEmpty);
    // Frame 2 arrives before Frame 1 -> targetFrames reached, releases Frame 0 while holding Frame 2
    final out1 = jb.push(2, f2);
    expect(out1.length, 1);
    expect(out1[0][0], 0);

    // Frame 1 arrives -> releases Frame 1 and Frame 2 in exact order!
    final out2 = jb.push(1, f1);
    expect(out2.length, 2);
    expect(out2[0][0], 1);
    expect(out2[1][0], 2);

    // Stale frame 1 arriving again is dropped
    expect(jb.push(1, late), isEmpty);
  });

  test('AudioJitterBuffer drops excess frames on burst to bound latency', () {
    final jb = AudioJitterBuffer(targetFrames: 2, maxFrames: 3);
    // Simulate missing seq 0 while seq 1, 2, 3, 4 arrive in a burst
    expect(jb.push(1, Uint8List.fromList([1, 0, 0, 0])), isEmpty);
    // Once targetFrames (2) queued beyond missing 0, it skips gap and drains in order
    final out = jb.push(2, Uint8List.fromList([2, 0, 0, 0]));
    expect(out.length, 2);
    expect(out[0][0], 1);
    expect(out[1][0], 2);
  });
}
