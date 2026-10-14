// PhoneLink addition: Dart side of the BLE broadcast channel (see
// android/.../PhoneLinkBroadcast.kt). Android only; a no-op elsewhere.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:loggy/loggy.dart';

class PhoneLinkBroadcast {
  static const _channel = MethodChannel('phonelink/broadcast');

  static bool get supported => Platform.isAndroid;

  /// Broadcast a list of 16-bit service UUIDs, replacing whatever is currently
  /// being broadcast. Returns null on success or an error description.
  static Future<String?> advertiseServiceUuids(List<int> uuid16) async {
    if (!supported) return 'Broadcasting is only supported on Android';
    try {
      return await _channel.invokeMethod<String?>(
        'advertiseServiceUuids',
        {'uuid16': uuid16},
      );
    } on PlatformException catch (e) {
      logError('PhoneLink broadcast failed: $e');
      return e.message ?? e.code;
    }
  }

  static Future<void> stop() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod('stop');
    } on PlatformException catch (e) {
      logError('PhoneLink broadcast stop failed: $e');
    }
  }
}
