// PhoneLink addition: LoveSpouse broadcast protocol.
//
// Captured 2026-10-14 from the iPhone LoveSpouse app (HCI snoop log) and
// verified by replaying in nRF Connect. The iPhone app hides the command in a
// "Complete list of 16-bit Service UUIDs" advertisement:
//
//   header (8 bytes, constant; likely includes the QR-code pairing ID)
//   command (3 bytes)
//   0B 0C 0D ... 19 (15 bytes of padding)
//
// See the "LoveSpouse protocol findings" doc in the Toys project.

class LoveSpouse {
  /// Number of intensity levels the toy supports (not counting stop).
  static const int levels = 8;

  static const List<int> _header = [0xF9, 0x08, 0x49, 0x23, 0xAE, 0xCB, 0xC1, 0xD1];

  static const List<int> stopCommand = [0x6E, 0x9C, 0x3D];

  /// Index 0 = level 1 (lowest) ... index 7 = level 8 (highest).
  static const List<List<int>> levelCommands = [
    [0x77, 0xDC, 0xB0],
    [0x76, 0x55, 0xA1],
    [0x79, 0xA2, 0x59],
    [0x78, 0x2B, 0x48],
    [0x7B, 0xB0, 0x7A],
    [0x7A, 0x39, 0x6B],
    [0x7D, 0x86, 0x1F],
    [0x7C, 0x0F, 0x0E],
  ];

  /// Captured codes believed to be presets. Not wired to any control yet.
  static const List<List<int>> presetCommands = [
    [0x5F, 0x96, 0x1D],
    [0x5E, 0x1F, 0x0C],
    [0x4E, 0x9E, 0x1C],
  ];

  /// Command bytes for level 0 (stop) through [levels].
  static List<int> commandForLevel(int level) {
    if (level <= 0) return stopCommand;
    return levelCommands[(level > levels ? levels : level) - 1];
  }

  /// Converts an engine output value (0..maxValue) to a level 0..[levels].
  /// Any non-zero value maps to at least level 1.
  static int levelForValue(double value, double maxValue) {
    if (value <= 0 || maxValue <= 0) return 0;
    final scaled = (value / maxValue * levels).ceil();
    if (scaled < 1) return 1;
    return scaled > levels ? levels : scaled;
  }

  /// Full 26-byte advertisement payload for a command.
  static List<int> payload(List<int> command) => [
        ..._header,
        ...command,
        for (var b = 0x0B; b <= 0x19; b++) b,
      ];

  /// The payload expressed as 16-bit service UUIDs (little-endian byte pairs),
  /// which is how Android's advertiser accepts it.
  static List<int> serviceUuids(List<int> command) {
    final bytes = payload(command);
    return [
      for (var i = 0; i < bytes.length; i += 2) bytes[i] | (bytes[i + 1] << 8),
    ];
  }
}
