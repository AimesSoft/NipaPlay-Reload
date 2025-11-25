import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/utils/encdec.dart';
import 'package:smb_connect/src/utils/extensions.dart';
import 'package:smb_connect/src/utils/strings.dart';

class NdrBuffer {
  int _referent = 0;
  Map<Object, _Entry>? _referents;

  Uint8List buf;
  int start;
  int index = 0;
  int length = 0;
  late NdrBuffer deferred;

  NdrBuffer(this.buf, this.start) {
    index = start;
    deferred = this;
  }

  NdrBuffer derive(int idx) {
    NdrBuffer nb = NdrBuffer(buf, start);
    nb.index = idx;
    nb.deferred = deferred;
    return nb;
  }

  void reset() {
    index = start;
    length = 0;
    deferred = this;
  }

  int getCapacity() {
    return buf.length - start;
  }

  int getTailSpace() {
    return buf.length - index;
  }

  Uint8List getBuffer() {
    return buf;
  }

  int align(int boundary, {int? value}) {
    int n = align0(boundary);
    if (value != null) {
      int i = n;
      while (i > 0) {
        buf[index - i] = value;
        i--;
      }
    }
    return n;
  }

  void writeOctetArray(Uint8List b, int i, int l) {
    byteArrayCopy(src: b, srcOffset: i, dst: buf, dstOffset: index, length: l);
    advance(l);
  }

  void readOctetArray(Uint8List b, int i, int l) {
    byteArrayCopy(src: buf, srcOffset: index, dst: b, dstOffset: i, length: l);
    advance(l);
  }

  int getLength() {
    return deferred.length;
  }

  void setLength(int length) {
    deferred.length = length;
  }

  void advance(int n) {
    index += n;
    if ((index - start) > deferred.length) {
      deferred.length = index - start;
    }
  }

  int align0(int boundary) {
    int m = boundary - 1;
    int i = index - start;
    int n = ((i + m) & ~m) - i;
    advance(n);
    return n;
  }

  void encNdrSmall(int s) {
    buf[index] = (s & 0xFF);
    advance(1);
  }

  int decNdrSmall() {
    int val = buf[index] & 0xFF;
    advance(1);
    return val;
  }

  void encNdrShort(int s) {
    align(2);
    Encdec.encUint16LE(s, buf, index);
    advance(2);
  }

  int decNdrShort() {
    align(2);
    int val = Encdec.decUint16LE(buf, index);
    advance(2);
    return val;
  }

  void encNdrLong(int l) {
    align(4);
    Encdec.encUint32LE(l, buf, index);
    advance(4);
  }

  int decNdrLong() {
    align(4);
    int val = Encdec.decUint32LE(buf, index);
    advance(4);
    return val;
  }

  void encNdrHyper(int h) {
    align(8);
    Encdec.encUint64LE(h, buf, index);
    advance(8);
  }

  int decNdrHyper() {
    align(8);
    int val = Encdec.decUint64LE(buf, index);
    advance(8);
    return val;
  }

  /* float */
  /* double */
  void encNdrString(String s) {
    align(4);
    int i = index;
    int len = s.length;
    Encdec.encUint32LE(len + 1, buf, i);
    i += 4;
    Encdec.encUint32LE(0, buf, i);
    i += 4;
    Encdec.encUint32LE(len + 1, buf, i);
    i += 4;
    byteArrayCopy(
        src: s.getUNIBytes(),
        srcOffset: 0,
        dst: buf,
        dstOffset: i,
        length: len * 2);
    i += len * 2;
    buf[i++] = 0;
    buf[i++] = 0;
    advance(i - index);
  }

  String? decNdrString() {
    align(4);
    int i = index;
    String? val;
    int len = Encdec.decUint32LE(buf, i);
    i += 12;
    if (len != 0) {
      len--;
      int size = len * 2;
      if (size < 0 || size > 0xFFFF) {
        throw NdrException(NdrException.INVALID_CONFORMANCE);
      }
      val = fromUNIBytes(buf, i, size);
      i += size + 2;
    }
    advance(i - index);
    return val;
  }

  int _getDceReferent(Object obj) {
    _Entry? e;

    if (_referents == null) {
      _referents = {};
      _referent = 1;
    }

    e = _referents![obj];
    if (e == null) {
      e = _Entry(_referent++, obj);
      _referents![obj] = e;
    }

    return e.referent;
  }

  void encNdrReferent(Object? obj, int type) {
    if (obj == null) {
      encNdrLong(0);
      return;
    }
    switch (type) {
      case 1: /* unique */
      case 3: /* ref */
        encNdrLong(identityHashCode(obj));
        return;
      case 2: /* ptr */
        encNdrLong(_getDceReferent(obj));
        return;
    }
  }

  @override
  String toString() {
    return "start=$start,index=$index,length=${getLength()}";
  }
}

class _Entry {
  final Object obj;
  final int referent;

  _Entry(this.referent, this.obj);
}
