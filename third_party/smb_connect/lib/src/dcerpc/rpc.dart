import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/dcerpc/ndr/ndr_buffer.dart';
import 'package:smb_connect/src/dcerpc/ndr/ndr_object.dart';
import 'package:smb_connect/src/utils/encdec.dart';
import 'package:smb_connect/src/utils/extensions.dart';

class RpcUuidT extends NdrObject {
  int timeLow = 0;
  int timeMid = 0;
  int timeHiAndVersion = 0;
  int clockSeqHiAndReserved = 0;
  int clockSeqLow = 0;
  Uint8List? node;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrLong(timeLow);
    dst.encNdrShort(timeMid);
    dst.encNdrShort(timeHiAndVersion);
    dst.encNdrSmall(clockSeqHiAndReserved);
    dst.encNdrSmall(clockSeqLow);
    int nodes = 6;
    int nodei = dst.index;
    dst.advance(1 * nodes);

    dst = dst.derive(nodei);
    for (int i = 0; i < nodes; i++) {
      dst.encNdrSmall(node![i]);
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    timeLow = src.decNdrLong();
    timeMid = src.decNdrShort();
    timeHiAndVersion = src.decNdrShort();
    clockSeqHiAndReserved = src.decNdrSmall();
    clockSeqLow = src.decNdrSmall();
    int nodes = 6;
    int nodei = src.index;
    src.advance(1 * nodes);

    if (node == null) {
      if (nodes < 0 || nodes > 0xFFFF) {
        throw NdrException(NdrException.INVALID_CONFORMANCE);
      }
      node = Uint8List(nodes);
    }
    src = src.derive(nodei);
    for (int i = 0; i < nodes; i++) {
      node![i] = src.decNdrSmall();
    }
  }
}

class RpcPolicyHandle extends NdrObject {
  int type = 0;
  RpcUuidT? uuid;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrLong(type);
    if (uuid == null) {
      throw NdrException(NdrException.NO_NULL_REF);
    }
    dst.encNdrLong(uuid!.timeLow);
    dst.encNdrShort(uuid!.timeMid);
    dst.encNdrShort(uuid!.timeHiAndVersion);
    dst.encNdrSmall(uuid!.clockSeqHiAndReserved);
    dst.encNdrSmall(uuid!.clockSeqLow);
    int uuidNodes = 6;
    int uuidNodei = dst.index;
    dst.advance(1 * uuidNodes);

    dst = dst.derive(uuidNodei);
    for (int i = 0; i < uuidNodes; i++) {
      dst.encNdrSmall(uuid!.node![i]);
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    type = src.decNdrLong();
    src.align(4);
    uuid ??= RpcUuidT();
    uuid!.timeLow = src.decNdrLong();
    uuid!.timeMid = src.decNdrShort();
    uuid!.timeHiAndVersion = src.decNdrShort();
    uuid!.clockSeqHiAndReserved = src.decNdrSmall();
    uuid!.clockSeqLow = src.decNdrSmall();
    int uuidNodes = 6;
    int uuidNodei = src.index;
    src.advance(1 * uuidNodes);

    if (uuid!.node == null) {
      if (uuidNodes < 0 || uuidNodes > 0xFFFF) {
        throw NdrException(NdrException.INVALID_CONFORMANCE);
      }
      uuid!.node = Uint8List(uuidNodes);
    }
    src = src.derive(uuidNodei);
    for (int i = 0; i < uuidNodes; i++) {
      uuid!.node![i] = src.decNdrSmall();
    }
  }
}

class RpcUnicodeString extends NdrObject {
  int length = 0;
  int maximumLength = 0;
  Uint8List? buffer;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    dst.encNdrShort(length);
    dst.encNdrShort(maximumLength);
    dst.encNdrReferent(buffer, 1);

    if (buffer != null) {
      dst = dst.deferred;
      int bufferl = length ~/ 2;
      int buffers = maximumLength ~/ 2;
      dst.encNdrLong(buffers);
      dst.encNdrLong(0);
      dst.encNdrLong(bufferl);
      int bufferi = dst.index;
      dst.advance(2 * bufferl);

      dst = dst.derive(bufferi);
      for (int i = 0; i < bufferl; i++) {
        dst.encNdrShort(buffer![i]);
      }
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    length = src.decNdrShort();
    maximumLength = src.decNdrShort();
    int bufferp = src.decNdrLong();

    if (bufferp != 0) {
      src = src.deferred;
      int buffers = src.decNdrLong();
      src.decNdrLong();
      int bufferl = src.decNdrLong();
      int bufferi = src.index;
      src.advance(2 * bufferl);

      if (buffer == null) {
        if (buffers < 0 || buffers > 0xFFFF) {
          throw NdrException(NdrException.INVALID_CONFORMANCE);
        }
        buffer = Uint8List(buffers);
      }
      src = src.derive(bufferi);
      for (int i = 0; i < bufferl; i++) {
        buffer![i] = src.decNdrShort();
      }
    }
  }
}

class RpcSidT extends NdrObject {
  static Uint8List toByteArray(RpcSidT sid) {
    Uint8List dst = Uint8List(1 + 1 + 6 + sid.subAuthorityCount * 4);
    int di = 0;
    dst[di++] = sid.revision;
    dst[di++] = sid.subAuthorityCount;
    byteArrayCopy(
        src: sid.identifierAuthority!,
        srcOffset: 0,
        dst: dst,
        dstOffset: di,
        length: 6);
    di += 6;
    for (int ii = 0; ii < sid.subAuthorityCount; ii++) {
      Encdec.encUint32LE(sid.subAuthority![ii], dst, di);
      di += 4;
    }
    return dst;
  }

  int revision = 0;
  int subAuthorityCount = 0;
  Uint8List? identifierAuthority;
  Uint8List? subAuthority;

  @override
  void encode(NdrBuffer dst) {
    dst.align(4);
    int subAuthoritys = subAuthorityCount;
    dst.encNdrLong(subAuthoritys);
    dst.encNdrSmall(revision);
    dst.encNdrSmall(subAuthorityCount);
    int identifierAuthoritys = 6;
    int identifierAuthorityi = dst.index;
    dst.advance(1 * identifierAuthoritys);
    int subAuthorityi = dst.index;
    dst.advance(4 * subAuthoritys);

    dst = dst.derive(identifierAuthorityi);
    for (int i = 0; i < identifierAuthoritys; i++) {
      dst.encNdrSmall(identifierAuthority![i]);
    }
    dst = dst.derive(subAuthorityi);
    for (int i = 0; i < subAuthoritys; i++) {
      dst.encNdrLong(subAuthority![i]);
    }
  }

  @override
  void decode(NdrBuffer src) {
    src.align(4);
    int subAuthoritys = src.decNdrLong();
    revision = src.decNdrSmall();
    subAuthorityCount = src.decNdrSmall();
    int identifierAuthoritys = 6;
    int identifierAuthorityi = src.index;
    src.advance(1 * identifierAuthoritys);
    int subAuthorityi = src.index;
    src.advance(4 * subAuthoritys);

    if (identifierAuthority == null) {
      if (identifierAuthoritys < 0 || identifierAuthoritys > 0xFFFF) {
        throw NdrException(NdrException.INVALID_CONFORMANCE);
      }
      identifierAuthority = Uint8List(identifierAuthoritys);
    }
    src = src.derive(identifierAuthorityi);
    for (int i = 0; i < identifierAuthoritys; i++) {
      identifierAuthority![i] = src.decNdrSmall();
    }
    if (subAuthority == null) {
      if (subAuthoritys < 0 || subAuthoritys > 0xFFFF) {
        throw NdrException(NdrException.INVALID_CONFORMANCE);
      }
      subAuthority = Uint8List(subAuthoritys);
    }
    src = src.derive(subAuthorityi);
    for (int i = 0; i < subAuthoritys; i++) {
      subAuthority![i] = src.decNdrLong();
    }
  }
}
