import 'dart:typed_data';

import 'package:smb_connect/src/smb_constants.dart';
import 'package:smb_connect/src/utils/extensions.dart';

class SMBUtil {
  static void writeInt2(int val, Uint8List dst, int dstIndex) {
    dst[dstIndex] = (val);
    dst[++dstIndex] = (val >> 8);
  }

  static void writeInt4(int val, Uint8List dst, int dstIndex) {
    dst[dstIndex] = (val);
    dst[++dstIndex] = (val >>= 8);
    dst[++dstIndex] = (val >>= 8);
    dst[++dstIndex] = (val >> 8);
  }

  static int readInt2(Uint8List src, int srcIndex) {
    return (src[srcIndex] & 0xFF) + ((src[srcIndex + 1] & 0xFF) << 8);
  }

  static int readInt4(Uint8List src, int srcIndex) {
    return (src[srcIndex] & 0xFF) +
        ((src[srcIndex + 1] & 0xFF) << 8) +
        ((src[srcIndex + 2] & 0xFF) << 16) +
        ((src[srcIndex + 3] & 0xFF) << 24);
  }

  static int readInt8(Uint8List src, int srcIndex) {
    return (readInt4(src, srcIndex) & 0xFFFFFFFF) +
        ((readInt4(src, srcIndex + 4)) << 32);
  }

  static void writeInt8(int val, Uint8List dst, int dstIndex) {
    dst[dstIndex] = (val);
    dst[++dstIndex] = (val >>= 8);
    dst[++dstIndex] = (val >>= 8);
    dst[++dstIndex] = (val >>= 8);
    dst[++dstIndex] = (val >>= 8);
    dst[++dstIndex] = (val >>= 8);
    dst[++dstIndex] = (val >>= 8);
    dst[++dstIndex] = (val >> 8);
  }

  static int readTime(Uint8List src, int srcIndex) {
    int low = readInt4(src, srcIndex);
    int hi = readInt4(src, srcIndex + 4);
    int t = (hi << 32) | (low & 0xFFFFFFFF);
    t = t ~/ 10000 - SmbConstants.MILLISECONDS_BETWEEN_1970_AND_1601;
    return t;
  }

  static void writeTime(int t, Uint8List dst, int dstIndex) {
    if (t != 0) {
      t = (t + SmbConstants.MILLISECONDS_BETWEEN_1970_AND_1601) * 10000;
    }
    writeInt8(t, dst, dstIndex);
  }

  static int readUTime(Uint8List buffer, int bufferIndex) {
    return (readInt4(buffer, bufferIndex) & 0xFFFFFFFF) * 1000;
  }

  static void writeUTime(int t, Uint8List dst, int dstIndex) {
    writeInt4(t ~/ 1000, dst, dstIndex);
  }

  static final Uint8List SMB_HEADER = [
    0xFF,
    'S'.codeUnitAt(0),
    'M'.codeUnitAt(0),
    'B'.codeUnitAt(0),
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00
  ].toUint8List();

  static final Uint8List SMB2_HEADER = [
    0xFE, 'S'.codeUnitAt(0), 'M'.codeUnitAt(0), 'B'.codeUnitAt(0), // ProtocolId
    64, 0x00, // StructureSize (LE)
    0x00, 0x00, // CreditCharge (reserved 2.0.2)
    0x00, 0x00, // ChannelSequence
    0x00, 0x00, // Reserved
    0x00, 0x00, 0x00, 0x00, // Status
    0x00, 0x00, // Command
    0x00, 0x00, // CreditRequest/CreditResponse
    0x00, 0x00, 0x00, 0x00, // Flags
    0x00, 0x00, 0x00, 0x00, // NextCommand
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // MessageId
    0x00, 0x00, 0x00, 0x00, // Reserved / AsyncId
    0x00, 0x00, 0x00, 0x00, // TreeId / AsyncId
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // SessionId
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // Signature
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // Signature
    // (cont)
  ].toUint8List();
}
