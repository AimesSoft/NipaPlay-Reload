import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/utils/extensions.dart';

final bool MASK_SECRET_VALUE = true;
final String SECRET_PATTERN = "^(smb.*:).*(@.*)\$";
final String SECRET_MASK_REPLACE = "\$1******\$2";

extension String0Extension on String {
  List<String> toChars() {
    return split("");
  }

  String addToken(String div, String token, {bool ignoreDivIfSame = false}) {
    if (token.isEmpty) {
      return this;
    } else if (isEmpty) {
      return token;
    } else if (ignoreDivIfSame && (endsWith(div) || token.startsWith(div))) {
      return this + token;
    } else {
      return this + div + token;
    }
  }

  String? afterTokenOrNull(String token, {String? def}) {
    var n = indexOf(token);
    return (n >= 0) ? substring(n + token.length) : def;
  }

  String beforeToken(String token, {String def = ""}) {
    var n = indexOf(token);
    return (n >= 0) ? substring(0, n) : def;
  }

  String beforeTokenLast(String token, {String def = ""}) {
    var n = lastIndexOf(token);
    return (n >= 0) ? substring(0, n) : def;
  }

  String afterToken(String token, {String def = ""}) {
    var n = indexOf(token);
    return (n >= 0) ? substring(n + token.length) : def;
  }

  String afterTokenOrSelf(String token) {
    var n = indexOf(token);
    return (n >= 0) ? substring(n + token.length) : this;
  }

  String afterTokenLast(String token, {String def = ""}) {
    var n = lastIndexOf(token);
    return (n >= 0) ? substring(n + token.length) : def;
  }

  String fileExt({bool lowercase = true}) {
    final s = afterTokenLast('.');
    return lowercase ? s.toLowerCase() : s;
  }

  String filename({String? pathSeparator}) {
    final separator = pathSeparator ?? Platform.pathSeparator;
    return afterTokenLast(separator);
  }

  String uriFilename() {
    final s = afterTokenLast('/');
    var n1 = s.lastIndexOf('?');
    final n2 = s.lastIndexOf('#');
    if (n1 > 0 && n2 > 0) {
      n1 = min(n1, n2);
    } else if (n2 > 0) {
      n1 = n2;
    }
    return n1 > 0 ? s.substring(0, n1) : s;
  }

  String fileBasename() {
    return beforeTokenLast('.');
  }

  String changeFileExt(String newExt) {
    int n = lastIndexOf('.');
    if (n >= 0) {
      return newExt.isEmpty ? substring(0, n) : substring(0, n + 1) + newExt;
    } else {
      return this;
    }
  }

  Uint8List hexToUint8List() {
    var hex = this;
    if (hex.length % 2 != 0) {
      throw 'Odd number of hex digits';
    }
    var l = hex.length ~/ 2;
    var result = Uint8List(l);
    for (var i = 0; i < l; ++i) {
      var x = int.parse(hex.substring(2 * i, 2 * (i + 1)), radix: 16);
      if (x.isNaN) {
        throw 'Expected hex string';
      }
      result[i] = x;
    }
    return result;
  }
}

extension StringExtension on String? {
  bool isNullOrEmpty() => this == null || this!.isEmpty;

  Uint8List getUNIBytes() {
    var codeUnits = this?.codeUnits;
    if (codeUnits == null) {
      return Uint8List(0);
    } else {
      var byteData = ByteData(codeUnits.length * 2);
      for (var i = 0; i < codeUnits.length; i += 1) {
        byteData.setUint16(i * 2, codeUnits[i], Endian.little);
      }
      return byteData.buffer.asUint8List();
    }
  }

  Uint8List getOEMBytes(Configuration config) {
    if (this == null) {
      return Uint8List(0);
    } else {
      return config.oemEncoding.encode(this!).toUint8List();
    }
  }

  Uint8List getOEMBytesBy(CodePage cp) {
    if (this == null) {
      return Uint8List(0);
    } else {
      return cp.encode(this!).toUint8List();
    }
  }

  Uint8List getASCIIBytes() {
    if (this == null) {
      return Uint8List(0);
    } else {
      return ascii.encode(this!).toUint8List();
    }
  }

  String? maskSecretValue() {
    if (MASK_SECRET_VALUE) {
      return this?.replaceFirst(SECRET_PATTERN, SECRET_MASK_REPLACE);
    }
    return this;
  }
}

String fromUNIBytes(Uint8List buff, int srcOffset, int len) {
// var f = File("utf-16le.txt");
// var bytes = f.readAsBytesSync();

// Note that this assumes that the system's native endianness is the same as
// the file's.
// var utf16CodeUnits =
  Uint8List bytes = Uint8List(len);
  byteArrayCopy(
      src: buff, srcOffset: srcOffset, dst: bytes, dstOffset: 0, length: len);

  return String.fromCharCodes(bytes.buffer.asUint16List());
  // final decodeBuff = Uint8List(len);
  // byteArrayCopy(
  //     src: buff,
  //     srcOffset: srcOffset,
  //     dst: decodeBuff,
  //     dstOffset: 0,
  //     length: len);
  // return utf16.decode(decodeBuff);
}

String fromASCIIBytes(Uint8List buff, int srcOffset, int len) {
  final decodeBuff = Uint8List(len);
  byteArrayCopy(
      src: buff,
      srcOffset: srcOffset,
      dst: decodeBuff,
      dstOffset: 0,
      length: len);
  return ascii.decode(decodeBuff);
}

/// decoded string
String fromOEMBytes(
    Uint8List src, int srcIndex, int len, Configuration config) {
  return fromOEMBytesFor(src, srcIndex, len, config.oemEncoding);
}

String fromOEMBytesFor(Uint8List src, int srcIndex, int len, CodePage cp) {
  try {
    Uint8List bytes = Uint8List(len);
    byteArrayCopy(
        src: src, srcOffset: srcIndex, dst: bytes, dstOffset: 0, length: len);
    return cp.decode(bytes);
  } catch (e) {
    throw SmbRuntimeException("Unsupported OEM encoding ${cp.name}");
  }
}

/// position of terminating null bytes
int findUNITermination(Uint8List buffer, int bufferIndex, int maxLen) {
  int len = 0;
  while (buffer[bufferIndex + len] != 0x00 ||
      buffer[bufferIndex + len + 1] != 0x00) {
    len += 2;
    if (len > maxLen) {
      throw SmbRuntimeException("zero termination not found");
    }
  }
  return len;
}

/// position of terminating null byte
int findTermination(Uint8List buffer, int bufferIndex, int maxLen) {
  int len = 0;
  while (buffer[bufferIndex + len] != 0x00) {
    len++;
    if (len > maxLen) {
      throw SmbRuntimeException("zero termination not found");
    }
  }
  return len;
}

class Hexdump {
  static String toHexString(int n, int padLeft) {
    return n.toRadixString(16).padLeft(padLeft, '0');
  }

  static String toHexStringBuff(Uint8List? buff,
      {int offset = 0, int? length}) {
    return (buff?.toHexString2(offset, length ?? buff.length) ??
        "00"); //.padLeft(padLeft, '0');
  }

  static Uint8List decodeToBuff(String hex) {
    if (hex.length % 2 != 0) {
      throw 'Odd number of hex digits';
    }
    var l = hex.length ~/ 2;
    var result = Uint8List(l);
    for (var i = 0; i < l; ++i) {
      var x = int.parse(hex.substring(2 * i, 2 * (i + 1)), radix: 16);
      if (x.isNaN) {
        throw 'Expected hex string';
      }
      result[i] = x;
    }
    return result;
  }
}
