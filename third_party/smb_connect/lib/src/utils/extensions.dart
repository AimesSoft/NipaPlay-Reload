import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/asn1.dart';

bool isDigit(String? s) {
  if (s == null) {
    return false;
  }
  return int.tryParse(s) != null;
}

bool isWhitespace(String? s) {
  if (s == null) {
    return false;
  }
  int rune = s.codeUnitAt(0);
  return (rune >= 0x0009 && rune <= 0x000D) ||
      rune == 0x0020 ||
      rune == 0x0085 ||
      rune == 0x00A0 ||
      rune == 0x1680 ||
      rune == 0x180E ||
      (rune >= 0x2000 && rune <= 0x200A) ||
      rune == 0x2028 ||
      rune == 0x2029 ||
      rune == 0x202F ||
      rune == 0x205F ||
      rune == 0x3000 ||
      rune == 0xFEFF;
}

extension StringExtension on String {
  bool equalsIgnoreCase(String? s) {
    return toLowerCase() == s?.toLowerCase();
  }
}

bool isAttr(int attributes, int attrFlag) =>
    (attributes & attrFlag) == attrFlag;

extension IntExtension on int {
  bool isFlag(int attrFlag) => isAttr(this, attrFlag);
}

extension ListExtension<T> on List<T> {
  T? findFirst(bool Function(T item) test, {T? def}) {
    for (var item in this) {
      if (test(item)) {
        return item;
      }
    }
    return def;
  }

  T? getOrNull(int index) {
    return (index >= 0 && index < length) ? this[index] : null;
  }

  int sumOf(int Function(T item) getValue) {
    var sum = 0;
    for (var item in this) {
      sum += getValue(item);
    }
    return sum;
  }

  List<R> mapNotNull<R>(R? Function(T item) mapper) {
    List<R> res = [];
    for (var item in this) {
      var newItem = mapper(item);
      if (newItem != null) {
        res.add(newItem);
      }
    }
    return res;
  }
}

extension DataBufferExtension on List<int> {
  String toHexString() {
    return map((e) => e.toRadixString(16).padLeft(2, '0')).join("");
  }

  String toHexString2(int offset, int length) {
    var s = "";
    for (var i = 0; i < length; i++) {
      s += this[offset + i].toRadixString(16).padLeft(2, '0');
    }
    return s;
  }

  Uint8List toUint8List() {
    return Uint8List.fromList(this);
  }

  void fill([int start = 0, int? count, int value = 0]) {
    int len = count ?? length;
    for (var i = 0; i < len; i++) {
      this[start + i] = value;
    }
  }
}

extension Uint8ListExtension on Uint8List {
  void fill({int start = 0, int? end, int value = 0}) {
    int end0 = end ?? length;
    for (var i = start; i < end0; i++) {
      this[i] = value;
    }
  }
}

extension RandomExtension on Random {
  Uint8List nextBytes(int count) {
    Uint8List res = Uint8List(count);
    for (var i = 0; i < count; i++) {
      res[i] = nextInt(0xFF);
    }
    return res;
  }
}

T? enumValueOf<T extends Enum>(String s, List<T> values) =>
    values.findFirst((element) => element.name == s);

void buffFill(Uint8List buff, int count, {int value = 0}) {
  for (var i = 0; i < count; i++) {
    buff.add(value);
  }
}

void buffFillTo(Uint8List buff, int count, {int value = 0}) {
  for (var i = 0; i < count - buff.length; i++) {
    buff.add(value);
  }
}

// void buffArrayCopyIf({
//   required DataBuffer? src,
//   required int offset,
//   required DataBuffer dst,
//   required int length,
// }) {
//   if (src != null) {
//     buffArrayCopy(src: src, offset: offset, dst: dst, length: length);
//   } else {
//     buffFill(dst, length);
//   }
// }

// void buffArrayCopy(
//     {required DataBuffer src,
//     required int offset,
//     required DataBuffer dst,
//     int? length}) {
//   int len = length ?? src.length;
//   for (int i = 0; i < len; i++) {
//     dst.add(src[offset + i]);
//   }
// }

void byteArrayCopy(
    {required Uint8List src,
    required int srcOffset,
    required Uint8List dst,
    required int dstOffset,
    int? length}) {
  int len = length ?? src.length;
  for (int i = 0; i < len; i++) {
    dst[dstOffset + i] = src[srcOffset + i];
  }
}

void intArrayCopy(
    {required List<int> src,
    required int srcOffset,
    required Uint8List dst,
    required int dstOffset,
    int? length}) {
  int len = length ?? src.length;
  for (int i = 0; i < len; i++) {
    dst[dstOffset + i] = src[srcOffset + i];
  }
}

void arrayCopy(
    Uint8List src, int srcOffset, Uint8List dst, int dstOffset, int length) {
  // int len = length ?? src.length;
  for (int i = 0; i < length; i++) {
    dst[dstOffset + i] = src[srcOffset + i];
  }
}

// DataBuffer newBuffArrayCopy(
//     {required DataBuffer src, required int offset, required int length}) {
//   DataBuffer res = []; //DataBuffer();
//   buffArrayCopy(src: src, dst: res, offset: offset, length: length);
//   return res;
// }

extension ASN1ParserExtension on ASN1Parser {
  ASN1Object? nextObjectIf() {
    if (hasNext()) {
      return nextObject();
    } else {
      return null;
    }
  }
}

int bitCount(int n) {
  return n.toRadixString(2).replaceAll('0', '').length;
}

extension DigestExtension on Digest {
  void updateBuff(Uint8List inp) {
    update(inp, 0, inp.length);
  }

  Uint8List digest() {
    Uint8List res = Uint8List(digestSize);
    doFinal(res, 0);
    return res;
  }

  int digestTo(Uint8List out, int offset, int len) {
    return doFinal(out, offset);
  }
}

bool isEqualMessageDigest(Uint8List? digesta, Uint8List? digestb) {
  if (digesta == digestb) return true;
  if (digesta == null || digestb == null) {
    return false;
  }

  int lenA = digesta.length;
  int lenB = digestb.length;

  if (lenB == 0) {
    return lenA == 0;
  }

  int result = 0;
  result |= lenA - lenB;

  // time-constant comparison
  for (int i = 0; i < lenA; i++) {
    // If i >= lenB, indexB is 0; otherwise, i.
    int indexB = i; //((i - lenB) >>> 31) * i;
    result |= digesta[i] ^ digestb[indexB];
  }
  return result == 0;
}
