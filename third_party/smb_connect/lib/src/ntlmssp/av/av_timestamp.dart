import 'dart:typed_data';

import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/ntlmssp/av/av_pair.dart';
import 'package:smb_connect/src/utils/extensions.dart';

class AvTimestamp extends AvPair {
  AvTimestamp(Uint8List raw) : super(AvPair.MsvAvTimestamp, raw);

  factory AvTimestamp.encode(int ts) {
    Uint8List data = Uint8List(8);
    SMBUtil.writeInt8(ts, data, 0);
    return AvTimestamp(data);
  }

  int getTimestamp() => SMBUtil.readInt8(raw, 0);

  @override
  String toString() {
    return "AvTimestamp(type: $type, timestamp: ${getTimestamp()}, raw: ${raw.toHexString()})";
  }
}
