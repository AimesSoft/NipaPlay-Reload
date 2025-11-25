import 'dart:typed_data';

import 'package:smb_connect/src/ntlmssp/av/av_pair.dart';
import 'package:smb_connect/src/utils/extensions.dart';

class AvChannelBindings extends AvPair {
  AvChannelBindings(Uint8List channelBindingHash)
      : super(AvPair.MsvAvChannelBindings, channelBindingHash);

  @override
  String toString() {
    return "AvChannelBindings(type: $type, raw: ${raw.toHexString()})";
  }
}
