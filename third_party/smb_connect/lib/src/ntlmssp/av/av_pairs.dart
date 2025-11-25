import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/ntlmssp/av/av_channel_bindings.dart';
import 'package:smb_connect/src/ntlmssp/av/av_flags.dart';
import 'package:smb_connect/src/ntlmssp/av/av_pair.dart';
import 'package:smb_connect/src/ntlmssp/av/av_single_host.dart';
import 'package:smb_connect/src/ntlmssp/av/av_target_name.dart';
import 'package:smb_connect/src/ntlmssp/av/av_timestamp.dart';
import 'package:smb_connect/src/utils/extensions.dart';

final class AvPairs {
  static List<AvPair> decode(Uint8List data) {
    List<AvPair> pairs = [];
    int pos = 0;
    bool foundEnd = false;
    while (pos + 4 <= data.length) {
      int avId = SMBUtil.readInt2(data, pos);
      int avLen = SMBUtil.readInt2(data, pos + 2);
      pos += 4;

      if (avId == AvPair.MsvAvEOL) {
        if (avLen != 0) {
          throw SmbConnectException("Invalid avLen for AvEOL");
        }
        foundEnd = true;
        break;
      }

      Uint8List raw = Uint8List(avLen);
      byteArrayCopy(
          src: data, srcOffset: pos, dst: raw, dstOffset: 0, length: avLen);
      pairs.add(_parseAvPair(avId, raw));

      pos += avLen;
    }
    if (!foundEnd) {
      throw SmbConnectException("Missing AvEOL");
    }
    return pairs;
  }

  static bool contains(List<AvPair>? pairs, int type) {
    if (pairs == null) {
      return false;
    }
    for (AvPair p in pairs) {
      if (p.type == type) {
        return true;
      }
    }
    return false;
  }

  /// first occurance of the given type
  static AvPair? get(List<AvPair> pairs, int type) {
    return pairs.findFirst((element) => element.type == type);
  }

  /// Remove all occurances of the given type
  static void remove(List<AvPair> pairs, int type) {
    pairs.removeWhere((element) => element.type == type);
  }

  /// Replace all occurances of the given type
  static void replace(List<AvPair> pairs, AvPair rep) {
    remove(pairs, rep.type);
    pairs.add(rep);
  }

  /// encoded avpairs
  static Uint8List encode(List<AvPair> pairs) {
    int size = 0;
    for (AvPair p in pairs) {
      size += 4 + p.raw.length;
    }
    size += 4;

    Uint8List enc = Uint8List(size);
    int pos = 0;
    for (AvPair p in pairs) {
      Uint8List raw = p.raw;
      SMBUtil.writeInt2(p.type, enc, pos);
      SMBUtil.writeInt2(raw.length, enc, pos + 2);
      byteArrayCopy(
          src: raw,
          srcOffset: 0,
          dst: enc,
          dstOffset: pos + 4,
          length: raw.length);
      // print("encode AvPairs  ${enc.toHexString()}"); //${p.type}
      pos += 4 + raw.length;
    }

    // MsvAvEOL
    SMBUtil.writeInt2(AvPair.MsvAvEOL, enc, pos);
    SMBUtil.writeInt2(0, enc, pos + 2);
    // pos += 4;
    // print("encode AvPairs  ${enc.toHexString()}"); //${p.type}
    return enc;
  }

  static AvPair _parseAvPair(int avId, Uint8List raw) {
    switch (avId) {
      case AvPair.MsvAvFlags:
        return AvFlags(raw);
      case AvPair.MsvAvTimestamp:
        return AvTimestamp(raw);
      case AvPair.MsvAvTargetName:
        return AvTargetName(raw);
      case AvPair.MsvAvSingleHost:
        return AvSingleHost(raw);
      case AvPair.MsvAvChannelBindings:
        return AvChannelBindings(raw);
      default:
        return AvPair(avId, raw);
    }
  }
}
