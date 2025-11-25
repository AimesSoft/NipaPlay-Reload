import 'dart:typed_data';

import 'package:smb_connect/src/ntlmssp/av/av_pair.dart';
import 'package:smb_connect/src/utils/extensions.dart';
import 'package:smb_connect/src/utils/strings.dart';

class AvTargetName extends AvPair {
  AvTargetName(Uint8List raw) : super(AvPair.MsvAvTargetName, raw);

  String getTargetName() => fromUNIBytes(raw, 0, raw.length);

  @override
  String toString() {
    return "AvTargetName(type: $type, targetName: ${getTargetName()}, raw: ${raw.toHexString()})";
  }

  factory AvTargetName.encode(String targetName) {
    return AvTargetName(targetName.getUNIBytes());
  }
}
