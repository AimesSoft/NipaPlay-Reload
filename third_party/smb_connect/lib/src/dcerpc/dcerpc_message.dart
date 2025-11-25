import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/dcerpc/ndr/ndr_buffer.dart';
import 'package:smb_connect/src/dcerpc/ndr/ndr_object.dart';

import 'dcerpc_constants.dart';

abstract class DcerpcMessage extends NdrObject implements DcerpcConstants {
  int ptype = -1;
  int flags = 0;
  int length = 0;
  int callId = 0;
  int allocHint = 0;
  int result = 0;

  bool isFlagSet(int flag) {
    return (flags & flag) == flag;
  }

  /// Remove flag
  void unsetFlag(int flag) {
    flags &= ~flag;
  }

  /// Set flag
  void setFlag(int flag) {
    flags |= flag;
  }

  DcerpcException? getResult() {
    if (result != 0) return DcerpcException(result);
    return null;
  }

  void encodeHeader(NdrBuffer buf) {
    buf.encNdrSmall(5); /* RPC version */
    buf.encNdrSmall(0); /* minor version */
    buf.encNdrSmall(ptype);
    buf.encNdrSmall(flags);
    buf.encNdrLong(0x00000010); /* Little-endian / ASCII / IEEE */
    buf.encNdrShort(length);
    buf.encNdrShort(0); /* length of authvalue */
    buf.encNdrLong(callId);
  }

  void decodeHeader(NdrBuffer buf) {
    /* RPC major / minor version */
    if (buf.decNdrSmall() != 5 || buf.decNdrSmall() != 0) {
      throw NdrException("DCERPC version not supported");
    }
    ptype = buf.decNdrSmall();
    flags = buf.decNdrSmall();
    if (buf.decNdrLong() != 0x00000010) {
      /* Little-endian / ASCII / IEEE */
      throw NdrException("Data representation not supported");
    }
    length = buf.decNdrShort();
    if (buf.decNdrShort() != 0) {
      throw NdrException("DCERPC authentication not supported");
    }
    callId = buf.decNdrLong();
  }

  @override
  void encode(NdrBuffer dst) {
    int start = dst.index;
    int allocHintIndex = 0;

    dst.advance(16); /* momentarily skip header */
    if (ptype == 0) {
      /* Request */
      allocHintIndex = dst.index;
      dst.encNdrLong(0); /* momentarily skip alloc hint */
      dst.encNdrShort(0); /* context id */
      dst.encNdrShort(getOpnum());
    }

    encodeIn(dst);
    length = dst.index - start;

    if (ptype == 0) {
      dst.index = allocHintIndex;
      allocHint = length - allocHintIndex;
      dst.encNdrLong(allocHint);
    }

    dst.index = start;
    encodeHeader(dst);
    dst.index = start + length;
  }

  @override
  void decode(NdrBuffer src) {
    decodeHeader(src);

    if (ptype != 12 && ptype != 2 && ptype != 3 && ptype != 13) {
      throw NdrException("Unexpected ptype: $ptype");
    }

    if (ptype == 2 || ptype == 3) {
      /* Response or Fault */
      allocHint = src.decNdrLong();
      src.decNdrShort(); /* context id */
      src.decNdrShort(); /* cancel count */
    }
    if (ptype == 3 || ptype == 13) {
      /* Fault */
      result = src.decNdrLong();
    } else {
      /* Bindack or Response */
      decodeOut(src);
    }
  }

  int getOpnum();

  void encodeIn(NdrBuffer buf);
  void decodeOut(NdrBuffer buf);
}
