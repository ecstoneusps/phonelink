// PhoneLink addition: generates LoveSpouse broadcast commands.
//
// LoveSpouse toys contain a cheap 2.4 GHz radio, not a Bluetooth receiver.
// The phone sends a Bluetooth advertisement whose bytes have been chosen so
// that, after the phone's own Bluetooth "whitening" scrambles them on the air,
// the toy's radio sees a valid packet of its own:
//
//   sync 71 0F 55 | 5-byte address | payload | CRC-16
//
// Written from the rules recorded in the Toys project doc "LoveSpouse protocol
// findings" (2026-10-15). Reproduces all 12 commands captured from the official
// app byte for byte (see test/phonelink/lovespouse_encoder_test.dart).

class LoveSpouseEncoder {
  /// Default 5-byte address used by most LoveSpouse toys (ASCII "wbMSE").
  static const List<int> defaultAddress = [0x77, 0x62, 0x4D, 0x53, 0x45];

  /// Where our data starts inside the Bluetooth advertising packet when it is
  /// sent as Flags + a "Complete list of 16-bit Service UUIDs": 2 bytes PDU
  /// header + 6 bytes advertiser address + 3 bytes Flags + 2 bytes length/type.
  static const int serviceUuidPduOffset = 13;

  /// Encodes [payload] (usually one plain command byte) for [address].
  /// Returns the bytes to place in the advertisement: 8 address-dependent
  /// bytes, then the payload and CRC (3 bytes for a 1-byte payload).
  static List<int> encode(
    List<int> payload, {
    List<int> address = defaultAddress,
    int pduOffset = serviceUuidPduOffset,
  }) {
    final frame = <int>[
      for (final b in [0x71, 0x0F, 0x55, ...address.reversed]) _reverseBits8(b),
      ...payload.map((b) => b & 0xFF),
    ];
    final crc = _crc(address, payload);
    frame
      ..add(crc & 0xFF)
      ..add(crc >> 8);

    // The toy radio's own whitening covers everything after the sync bytes.
    final toyMask = _toyWhitening(frame.length - 3);
    for (var i = 3; i < frame.length; i++) {
      frame[i] ^= toyMask[i - 3];
    }

    // Pre-cancel the phone's Bluetooth whitening (advertising channel 37).
    final bleMask = _bleWhitening(pduOffset + frame.length);
    return [
      for (var i = 0; i < frame.length; i++) frame[i] ^ bleMask[pduOffset + i],
    ];
  }

  static int _reverseBits8(int x) {
    var r = 0;
    for (var i = 0; i < 8; i++) {
      r = (r << 1) | (x & 1);
      x >>= 1;
    }
    return r;
  }

  static int _reverseBits16(int x) {
    var r = 0;
    for (var i = 0; i < 16; i++) {
      r = (r << 1) | (x & 1);
      x >>= 1;
    }
    return r;
  }

  /// CRC-16/CCITT (poly 0x1021, init 0xFFFF) as the toy radio computes it:
  /// address bytes last-to-first, then payload bytes bit-reversed; the result
  /// is bit-reversed and inverted.
  static int _crc(List<int> address, List<int> payload) {
    int step(int c) {
      for (var i = 0; i < 8; i++) {
        c = (c & 0x8000) != 0 ? ((c << 1) ^ 0x1021) & 0xFFFF : (c << 1) & 0xFFFF;
      }
      return c;
    }

    var c = 0xFFFF;
    for (final b in address.reversed) {
      c = step(c ^ ((b & 0xFF) << 8));
    }
    for (final b in payload) {
      c = step(c ^ (_reverseBits8(b & 0xFF) << 8));
    }
    return (~_reverseBits16(c)) & 0xFFFF;
  }

  /// The toy radio's whitening sequence (7-bit register, all ones at start).
  static List<int> _toyWhitening(int count) {
    var r = List<int>.filled(7, 1);
    final out = <int>[];
    for (var n = 0; n < count; n++) {
      final a = r[2] ^ r[5];
      final b = r[1] ^ r[4];
      final c = r[6] ^ r[3];
      final d = c ^ r[0];
      final e = a ^ r[6];
      final bits = [e, d, b, a, c, r[4], r[5], r[6]];
      r = [e, d, b, a, r[3] ^ a, d ^ r[4], b ^ r[5]];
      var v = 0;
      for (final bit in bits) {
        v = (v << 1) | bit;
      }
      out.add(v);
    }
    return out;
  }

  /// Standard Bluetooth LE data whitening bytes for [channel].
  static List<int> _bleWhitening(int count, {int channel = 37}) {
    var lfsr = channel | 0x40;
    final out = <int>[];
    for (var n = 0; n < count; n++) {
      var v = 0;
      for (var bit = 0; bit < 8; bit++) {
        final b = lfsr & 1;
        v |= b << bit;
        lfsr >>= 1;
        if (b != 0) lfsr ^= 0x44;
      }
      out.add(v);
    }
    return out;
  }
}
