import 'dart:typed_data';

import 'package:smb_connect/src/smb_constants.dart';
import 'package:smb_connect/src/utils/encoding.dart';
import 'package:smb_connect/src/utils/extensions.dart';
import 'package:smb_connect/src/utils/utf16le/utf16_le.dart';

///
/// Base NTLMSSP packet.
///
abstract class NtlmPacket {
  ///
  /// The NTLMSSP header: "NTLMSSP#0"
  ///
  static final Uint8List NTLMSSP_HEADER =
      Uint8List.fromList([78, 84, 76, 77, 83, 83, 80, 0]);

  ///
  /// NTLM version
  ///
  static final Uint8List NTLMSSP_VERSION =
      Uint8List.fromList([6, 1, 0, 0, 0, 0, 0, 15]);

  static const int NTLMSSP_TYPE1 = 0x1;
  static const int NTLMSSP_TYPE2 = 0x2;
  static const int NTLMSSP_TYPE3 = 0x3;

  static final CharEncoding OEM_ENCODING = SmbConstants.DEFAULT_OEM_ENCODING;
  static final UNI_ENCODING = utf16le;

  int flags = 0;

  static bool getFlagStatic(int flags, int flag) => (flags & flag) != 0;
  static int setFlagStatic(int flags, int flag, bool value) =>
      value ? (flags | flag) : (flags & (0xffffffff ^ flag));

  bool getFlag(int flag) => (flags & flag) != 0;

  void setFlag(int flag, bool value) {
    flags = value ? (flags | flag) : (flags & (0xffffffff ^ flag));
  }

  static int readULong(Uint8List src, int index) {
    return (src[index] & 0xff) |
        ((src[index + 1] & 0xff) << 8) |
        ((src[index + 2] & 0xff) << 16) |
        ((src[index + 3] & 0xff) << 24);
  }

  static int readUShort(Uint8List src, int index) {
    return (src[index] & 0xff) | ((src[index + 1] & 0xff) << 8);
  }

  static Uint8List readSecurityBuffer(Uint8List src, int index) {
    int length = readUShort(src, index);
    int offset = readULong(src, index + 4);
    Uint8List buffer = Uint8List(length);
    byteArrayCopy(
        src: src, srcOffset: offset, dst: buffer, dstOffset: 0, length: length);
    return buffer;
  }

  static void writeULong(Uint8List dest, int offset, int ulong) {
    dest[offset] = ulong & 0xff;
    dest[offset + 1] = ulong >> 8 & 0xff;
    dest[offset + 2] = ulong >> 16 & 0xff;
    dest[offset + 3] = ulong >> 24 & 0xff;
  }

  static void writeUShort(Uint8List dest, int offset, int ushort) {
    dest[offset] = ushort & 0xff;
    dest[offset + 1] = ushort >> 8 & 0xff;
  }

  static int writeSecurityBuffer(Uint8List dest, int offset, Uint8List? src) {
    int length = (src != null) ? src.length : 0;
    if (length == 0) {
      return offset + 4;
    }
    writeUShort(dest, offset, length);
    writeUShort(dest, offset + 2, length);
    return offset + 4;
  }

  static int writeSecurityBufferContent(
      Uint8List dest, int pos, int off, Uint8List? src) {
    writeULong(dest, off, pos);
    if (src != null && src.isNotEmpty) {
      byteArrayCopy(
        src: src,
        srcOffset: 0,
        dst: dest,
        dstOffset: pos,
        length: src.length,
      );
      return src.length;
    }
    return 0;
  }

  static CharEncoding getOEMEncoding() => OEM_ENCODING;

  Uint8List toByteArray();
}
