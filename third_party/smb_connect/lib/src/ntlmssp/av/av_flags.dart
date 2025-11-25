import 'dart:typed_data';

import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/ntlmssp/av/av_pair.dart';
import 'package:smb_connect/src/utils/extensions.dart';

class AvFlags extends AvPair {
  AvFlags(Uint8List raw) : super(AvPair.MsvAvFlags, raw);

  int getFlags() => SMBUtil.readInt4(raw, 0);

  @override
  String toString() {
    return "AvFlags(type: $type, flags: ${getFlags()}, raw: ${raw.toHexString()})";
  }

  factory AvFlags.encode(int flags) {
    Uint8List raw = Uint8List(4);
    SMBUtil.writeInt4(flags, raw, 0);
    return AvFlags(raw);
  }
}
