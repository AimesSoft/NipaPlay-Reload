import 'dart:typed_data';

import 'package:smb_connect/src/utils/extensions.dart';

class AvPair {
  final int type;
  final Uint8List raw;

  AvPair(this.type, this.raw);

  @override
  String toString() => "AvPair(type: $type, raw: ${raw.toHexString()})";

  /// EOL type
  static const int MsvAvEOL = 0x0;

  /// Flags type
  static const int MsvAvFlags = 0x6;

  /// Timestamp type
  static const int MsvAvTimestamp = 0x7;

  /// Single host type
  static const int MsvAvSingleHost = 0x08;

  /// Target name type
  static const int MsvAvTargetName = 0x09;

  /// Channel bindings type
  static const int MsvAvChannelBindings = 0x0A;
}
