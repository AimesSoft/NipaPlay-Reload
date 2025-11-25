import 'dart:typed_data';

import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/ntlmssp/av/av_pair.dart';
import 'package:smb_connect/src/utils/extensions.dart';

class AvSingleHost extends AvPair {
  AvSingleHost(Uint8List raw) : super(AvPair.MsvAvSingleHost, raw);

  factory AvSingleHost.cfg(Configuration cfg) {
    return AvSingleHost.encode(Uint8List(8), cfg.machineId);
  }

  @override
  String toString() => "AvSingleHost(type: $type, raw: ${raw.toHexString()})";

  factory AvSingleHost.encode(Uint8List customData, Uint8List machineId) {
    int size = 8 + 8 + 32;
    Uint8List enc = Uint8List(size);
    SMBUtil.writeInt4(size, enc, 0);
    SMBUtil.writeInt4(0, enc, 4);
    byteArrayCopy(
        src: customData, srcOffset: 0, dst: enc, dstOffset: 8, length: 8);
    byteArrayCopy(
        src: machineId, srcOffset: 0, dst: enc, dstOffset: 16, length: 32);
    return AvSingleHost(enc);
  }
}
