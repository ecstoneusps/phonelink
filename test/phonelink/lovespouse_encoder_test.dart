import 'package:flutter_test/flutter_test.dart';
import 'package:intiface_central/phonelink/lovespouse.dart';
import 'package:intiface_central/phonelink/lovespouse_encoder.dart';

void main() {
  // Commands captured from the official iPhone app on 2026-10-14
  // (plain command -> 3 bytes after the 8-byte header).
  const captured = <int, List<int>>{
    0x00: [0x6E, 0x9C, 0x3D],
    0x12: [0x7C, 0x0F, 0x0E],
    0x13: [0x7D, 0x86, 0x1F],
    0x14: [0x7A, 0x39, 0x6B],
    0x15: [0x7B, 0xB0, 0x7A],
    0x16: [0x78, 0x2B, 0x48],
    0x17: [0x79, 0xA2, 0x59],
    0x18: [0x76, 0x55, 0xA1],
    0x19: [0x77, 0xDC, 0xB0],
    0x20: [0x4E, 0x9E, 0x1C],
    0x30: [0x5E, 0x1F, 0x0C],
    0x31: [0x5F, 0x96, 0x1D],
  };
  const header = [0xF9, 0x08, 0x49, 0x23, 0xAE, 0xCB, 0xC1, 0xD1];

  test('encoder reproduces every captured command', () {
    captured.forEach((plain, bytes) {
      expect(
        LoveSpouseEncoder.encode([plain]),
        [...header, ...bytes],
        reason: 'plain command 0x${plain.toRadixString(16)}',
      );
    });
  });

  test('generated payload matches the fixed level table', () {
    for (var level = 0; level <= LoveSpouse.levels; level++) {
      final plain = level == 0 ? LoveSpouse.plainStop : LoveSpouse.plainLevel1 + level - 1;
      expect(
        LoveSpouse.serviceUuidsForPlain([plain]),
        LoveSpouse.serviceUuids(LoveSpouse.commandForLevel(level)),
        reason: 'level $level',
      );
    }
  });

  test('longer payloads keep a 26-byte advertisement', () {
    expect(LoveSpouse.payloadForPlain([0xAA, 0x01, 0x32, 0x00, 0x00]).length, 26);
    expect(LoveSpouse.serviceUuidsForPlain([0xAA, 0x01, 0x32, 0x00, 0x00]).length, 13);
  });
}
