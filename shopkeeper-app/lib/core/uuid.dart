// ==============================================================================
// SmartShelf V2 - Cryptographically Secure UUID v4 Generator
// ==============================================================================

import 'dart:math';

class UuidUtils {
  static final Random _secureRandom = Random.secure();

  /// Generates a canonical RFC 4122 v4 UUID string.
  static String generateV4() {
    final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));

    // Set version to 0100 (version 4)
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    // Set variant to 10xx (RFC 4122 variant)
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }
}
