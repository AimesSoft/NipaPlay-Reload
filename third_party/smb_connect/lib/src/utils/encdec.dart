import 'dart:convert';
import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/smb_constants.dart';

class Encdec {
  static const int SEC_BETWEEEN_1904_AND_1970 = 2082844800;
  static const int TIME_1970_SEC_32BE = 1;
  static const int TIME_1970_SEC_32LE = 2;
  static const int TIME_1904_SEC_32BE = 3;
  static const int TIME_1904_SEC_32LE = 4;
  static const int TIME_1601_NANOS_64LE = 5;
  static const int TIME_1601_NANOS_64BE = 6;
  static const int TIME_1970_MILLIS_64BE = 7;
  static const int TIME_1970_MILLIS_64LE = 8;

  ///
  /// Encode integers
  ///
  static int encUint16BE(int s, Uint8List dst, int di) {
    dst[di++] = ((s >> 8) & 0xFF);
    dst[di] = (s & 0xFF);
    return 2;
  }

  static int encUint32BE(int i, Uint8List dst, int di) {
    dst[di++] = ((i >> 24) & 0xFF);
    dst[di++] = ((i >> 16) & 0xFF);
    dst[di++] = ((i >> 8) & 0xFF);
    dst[di] = (i & 0xFF);
    return 4;
  }

  static int encUint16LE(int s, Uint8List dst, int di) {
    dst[di++] = (s & 0xFF);
    dst[di] = ((s >> 8) & 0xFF);
    return 2;
  }

  static int encUint32LE(int i, Uint8List dst, int di) {
    dst[di++] = (i & 0xFF);
    dst[di++] = ((i >> 8) & 0xFF);
    dst[di++] = ((i >> 16) & 0xFF);
    dst[di] = ((i >> 24) & 0xFF);
    return 4;
  }

  ///
  /// Decode integers
  ///
  static int decUint16BE(Uint8List src, int si) {
    return (((src[si] & 0xFF) << 8) | (src[si + 1] & 0xFF));
  }

  static int decUint32BE(Uint8List src, int si) {
    return ((src[si] & 0xFF) << 24) |
        ((src[si + 1] & 0xFF) << 16) |
        ((src[si + 2] & 0xFF) << 8) |
        (src[si + 3] & 0xFF);
  }

  static int decUint16LE(Uint8List src, int si) {
    return ((src[si] & 0xFF) | ((src[si + 1] & 0xFF) << 8));
  }

  static int decUint32LE(Uint8List src, int si) {
    return (src[si] & 0xFF) |
        ((src[si + 1] & 0xFF) << 8) |
        ((src[si + 2] & 0xFF) << 16) |
        ((src[si + 3] & 0xFF) << 24);
  }

  ///
  /// Encode and decode 64 bit integers
  ///
  static int encUint64BE(int l, Uint8List dst, int di) {
    encUint32BE((l & 0xFFFFFFFF), dst, di + 4);
    encUint32BE(((l >> 32) & 0xFFFFFFFF), dst, di);
    return 8;
  }

  static int encUint64LE(int l, Uint8List dst, int di) {
    encUint32LE((l & 0xFFFFFFFF), dst, di);
    encUint32LE(((l >> 32) & 0xFFFFFFFF), dst, di + 4);
    return 8;
  }

  static int decUint64BE(Uint8List src, int si) {
    int l;
    l = decUint32BE(src, si) & 0xFFFFFFFF;
    l <<= 32;
    l |= decUint32BE(src, si + 4) & 0xFFFFFFFF;
    return l;
  }

  static int decUint64LE(Uint8List src, int si) {
    int l;
    l = decUint32LE(src, si + 4) & 0xFFFFFFFF;
    l <<= 32;
    l |= decUint32LE(src, si) & 0xFFFFFFFF;
    return l;
  }

  ///
  /// Encode floats
  ///
  static int encFloatLE(double f, Uint8List dst, int di) {
    var buff = ByteData(4);
    buff.setFloat32(0, f);
    return encUint32LE(buff.getInt32(0), dst, di);
  }

  static int encFloatBE(double f, Uint8List dst, int di) {
    var buff = ByteData(4);
    buff.setFloat32(0, f);
    return encUint32BE(buff.getUint32(0), dst, di);
  }

  ///
  /// Decode floating point numbers
  ///
  static double decFloatLE(Uint8List src, int si) {
    var buff = ByteData.view(src.buffer, si, 4);
    return buff.getFloat32(0, Endian.little);
  }

  static double decFloatBE(Uint8List src, int si) {
    var buff = ByteData.view(src.buffer, si, 4);
    return buff.getFloat32(0, Endian.big);
  }

  ///
  /// Encode and decode doubles
  ///
  static int encDoubleLE(double d, Uint8List dst, int di) {
    var buff = ByteData(8);
    buff.setFloat64(0, d);
    return encUint64LE(buff.getInt64(0), dst, di);
  }

  static int encDoubleBE(double d, Uint8List dst, int di) {
    var buff = ByteData(8);
    buff.setFloat64(0, d);
    return encUint64BE(buff.getInt64(0), dst, di);
  }

  static double decDoubleLE(Uint8List src, int si) {
    var buff = ByteData.view(src.buffer, si, 8);
    return buff.getFloat64(0, Endian.little);
  }

  static double decDoubleBE(Uint8List src, int si) {
    var buff = ByteData.view(src.buffer, si, 8);
    return buff.getFloat64(0, Endian.big);
  }

  ///
  /// Encode times
  ///
  static int encTime(DateTime date, Uint8List dst, int di, int enc) {
    int t;

    switch (enc) {
      case TIME_1970_SEC_32BE:
        return encUint32BE((date.millisecondsSinceEpoch ~/ 1000), dst, di);
      case TIME_1970_SEC_32LE:
        return encUint32LE((date.millisecondsSinceEpoch ~/ 1000), dst, di);
      case TIME_1904_SEC_32BE:
        return encUint32BE(
            ((date.millisecondsSinceEpoch ~/ 1000 +
                    SEC_BETWEEEN_1904_AND_1970) &
                0xFFFFFFFF),
            dst,
            di);
      case TIME_1904_SEC_32LE:
        return encUint32LE(
            ((date.millisecondsSinceEpoch ~/ 1000 +
                    SEC_BETWEEEN_1904_AND_1970) &
                0xFFFFFFFF),
            dst,
            di);
      case TIME_1601_NANOS_64BE:
        t = (date.millisecondsSinceEpoch +
                SmbConstants.MILLISECONDS_BETWEEN_1970_AND_1601) *
            10000;
        return encUint64BE(t, dst, di);
      case TIME_1601_NANOS_64LE:
        t = (date.millisecondsSinceEpoch +
                SmbConstants.MILLISECONDS_BETWEEN_1970_AND_1601) *
            10000;
        return encUint64LE(t, dst, di);
      case TIME_1970_MILLIS_64BE:
        return encUint64BE(date.millisecondsSinceEpoch, dst, di);
      case TIME_1970_MILLIS_64LE:
        return encUint64LE(date.millisecondsSinceEpoch, dst, di);
      default:
        throw SmbIllegalArgumentException("Unsupported time encoding");
    }
  }

  ///
  /// Decode times
  ///
  static DateTime decTime(Uint8List src, int si, int enc) {
    int t;

    switch (enc) {
      case TIME_1970_SEC_32BE:
        return DateTime.fromMillisecondsSinceEpoch(decUint32BE(src, si) * 1000);
      case TIME_1970_SEC_32LE:
        return DateTime.fromMillisecondsSinceEpoch(decUint32LE(src, si) * 1000);
      case TIME_1904_SEC_32BE:
        return DateTime.fromMillisecondsSinceEpoch(
            ((decUint32BE(src, si) & 0xFFFFFFFF) - SEC_BETWEEEN_1904_AND_1970) *
                1000);
      case TIME_1904_SEC_32LE:
        return DateTime.fromMillisecondsSinceEpoch(
            ((decUint32LE(src, si) & 0xFFFFFFFF) - SEC_BETWEEEN_1904_AND_1970) *
                1000);
      case TIME_1601_NANOS_64BE:
        t = decUint64BE(src, si);
        return DateTime.fromMillisecondsSinceEpoch(
            t ~/ 10000 - SmbConstants.MILLISECONDS_BETWEEN_1970_AND_1601);
      case TIME_1601_NANOS_64LE:
        t = decUint64LE(src, si);
        return DateTime.fromMillisecondsSinceEpoch(
            t ~/ 10000 - SmbConstants.MILLISECONDS_BETWEEN_1970_AND_1601);
      case TIME_1970_MILLIS_64BE:
        return DateTime.fromMillisecondsSinceEpoch(decUint64BE(src, si));
      case TIME_1970_MILLIS_64LE:
        return DateTime.fromMillisecondsSinceEpoch(decUint64LE(src, si));
      default:
        throw SmbIllegalArgumentException("Unsupported time encoding");
    }
  }

  static int encUtf8(String str, Uint8List dst, int di, int dlim) {
    int start = di, ch;
    int strlen = str.length;

    for (int i = 0; di < dlim && i < strlen; i++) {
      ch = str.codeUnitAt(i);
      if ((ch >= 0x0001) && (ch <= 0x007F)) {
        dst[di++] = ch;
      } else if (ch > 0x07FF) {
        if ((dlim - di) < 3) {
          break;
        }
        dst[di++] = (0xE0 | ((ch >> 12) & 0x0F));
        dst[di++] = (0x80 | ((ch >> 6) & 0x3F));
        dst[di++] = (0x80 | ((ch >> 0) & 0x3F));
      } else {
        if ((dlim - di) < 2) {
          break;
        }
        dst[di++] = (0xC0 | ((ch >> 6) & 0x1F));
        dst[di++] = (0x80 | ((ch >> 0) & 0x3F));
      }
    }

    return di - start;
  }

  static String decUtf8(Uint8List src, int si, int slim) {
    Uint16List uni = Uint16List(slim - si);

    int ui, ch;

    for (ui = 0; si < slim && (ch = src[si++] & 0xFF) != 0; ui++) {
      if (ch < 0x80) {
        uni[ui] = ch;
      } else if ((ch & 0xE0) == 0xC0) {
        if ((slim - si) < 2) {
          break;
        }
        uni[ui] = ((ch & 0x1F) << 6);
        ch = src[si++] & 0xFF;
        uni[ui] |= ch & 0x3F;
        if ((ch & 0xC0) != 0x80 || uni[ui] < 0x80) {
          throw SmbIOException("Invalid UTF-8 sequence");
        }
      } else if ((ch & 0xF0) == 0xE0) {
        if ((slim - si) < 3) {
          break;
        }
        uni[ui] = ((ch & 0x0F) << 12);
        ch = src[si++] & 0xFF;
        if ((ch & 0xC0) != 0x80) {
          throw SmbIOException("Invalid UTF-8 sequence");
        }
        uni[ui] |= (ch & 0x3F) << 6;
        ch = src[si++] & 0xFF;
        uni[ui] |= ch & 0x3F;
        if ((ch & 0xC0) != 0x80 || uni[ui] < 0x800) {
          throw SmbIOException("Invalid UTF-8 sequence");
        }
      } else {
        throw SmbIOException("Unsupported UTF-8 sequence");
      }
    }

    return utf8.decode(uni);
  }

  static String decUcs2LE(Uint8List src, int si, int slim, Uint16List buf) {
    int bi;

    for (bi = 0; (si + 1) < slim; bi++, si += 2) {
      buf[bi] = decUint16LE(src, si);
      if (buf[bi] == 0) {
        break;
      }
    }
    return utf8.decode(buf);
  }
}
