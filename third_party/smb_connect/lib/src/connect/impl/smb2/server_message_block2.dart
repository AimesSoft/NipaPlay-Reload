import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block_response.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_response.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_constants.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_signing_digest.dart';
import 'package:smb_connect/src/connect/common/smb_signing_digest.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/extensions.dart';
import 'package:smb_connect/src/utils/strings.dart';

abstract class ServerMessageBlock2 implements CommonServerMessageBlock {
  int command;
  int flags = 0;
  int length = 0, headerStart = 0, wordCount = 0, byteCount = 0;

  Uint8List signature = Uint8List(16);
  Smb2SigningDigest? digest;

  final Configuration config;

  int creditCharge = 0;
  int status = 0;
  int credit = 0;
  int nextCommand = 0;
  int readSize = 0;
  bool async = false;
  int treeId = 0;
  int mid = 0;
  int asyncId = 0, sessionId = 0;
  int errorContextCount = 0;
  Uint8List? errorData;

  bool retainPayload = false;
  Uint8List? rawPayload;

  ServerMessageBlock2? next;

  ServerMessageBlock2(
    this.config, {
    this.command = 0,
    this.credit = 0,
    this.retainPayload = false,
  });

  @override
  void reset() {
    flags = 0;
    digest = null;
    sessionId = 0;
    treeId = 0;
  }

  @override
  int getCommand() => command;

  int getNextCommandOffset() {
    return nextCommand;
  }

  void setReadSize(int readSize) {
    this.readSize = readSize;
  }

  @override
  void setCommand(int command) {
    this.command = command;
  }

  int getTreeId() {
    return treeId;
  }

  void setTreeId(int treeId) {
    this.treeId = treeId;
    next?.setTreeId(treeId);
  }

  int getCreditCharge() {
    return creditCharge;
  }

  @override
  void setRetainPayload() {
    retainPayload = true;
  }

  @override
  bool isRetainPayload() {
    return retainPayload;
  }

  @override
  Uint8List? getRawPayload() {
    return rawPayload;
  }

  @override
  void setRawPayload(Uint8List rawPayload) {
    this.rawPayload = rawPayload;
  }

  @override
  Smb2SigningDigest? getDigest() {
    return digest;
  }

  @override
  void setDigest(SMBSigningDigest? digest) {
    this.digest = digest as Smb2SigningDigest?;
    next?.setDigest(digest);
  }

  int getStatus() {
    return status;
  }

  int getSessionId() {
    return sessionId;
  }

  @override
  void setSessionId(int nextSessionId) {
    sessionId = nextSessionId;
    next?.setSessionId(nextSessionId);
  }

  @override
  void setExtendedSecurity(bool extendedSecurity) {
    // ignore
  }

  @override
  void setUid(int uid) {
    // ignore
  }

  void addFlags(int flag) {
    flags |= flag;
  }

  void clearFlags(int flag) {
    flags &= ~flag;
  }

  @override
  int getMid() {
    return mid;
  }

  @override
  void setMid(int nextMid) {
    mid = nextMid;
  }

  bool chain(ServerMessageBlock2 n) {
    if (next != null) {
      return next!.chain(n);
    }

    n.addFlags(Smb2Constants.SMB2_FLAGS_RELATED_OPERATIONS);
    next = n;
    return true;
  }

  ServerMessageBlock2? getNext() => next;

  void setNext(ServerMessageBlock2? next) {
    this.next = next;
  }

  @override
  ServerMessageBlock2Response? getResponse() {
    return null;
  }

  @override
  void setResponse(CommonServerMessageBlockResponse msg) {}

  Uint8List? getErrorData() {
    return errorData;
  }

  int getErrorContextCount() {
    return errorContextCount;
  }

  int getHeaderStart() {
    return headerStart;
  }

  int getLength() {
    return length;
  }

  @override
  int encode(Uint8List dst, int dstIndex) {
    int start = headerStart = dstIndex;
    dstIndex += writeHeaderWireFormat(dst, dstIndex);

    byteCount = writeBytesWireFormat(dst, dstIndex);
    dstIndex += byteCount;
    dstIndex += pad8(dstIndex);

    length = dstIndex - start;

    int len = length;

    if (next != null) {
      int nextStart = dstIndex;
      dstIndex += next!.encode(dst, dstIndex);
      int off = nextStart - start;
      SMBUtil.writeInt4(off, dst, start + 20);
      len += dstIndex - nextStart;
    }

    digest?.sign(dst, headerStart, length, this,
        getResponse() as CommonServerMessageBlock?);

    if (isRetainPayload()) {
      rawPayload = Uint8List(len);
      byteArrayCopy(
          src: dst,
          srcOffset: start,
          dst: rawPayload!,
          dstOffset: 0,
          length: len);
    }

    return len;
  }

  static int size8(int size, {int align = 0}) {
    int rem = size % 8 - align;
    if (rem == 0) {
      return size;
    }
    if (rem < 0) {
      rem = 8 + rem;
    }
    return size + 8 - rem;
  }

  int pad8(int dstIndex) {
    int fromHdr = dstIndex - headerStart;
    int rem = fromHdr % 8;
    if (rem == 0) {
      return 0;
    }
    return 8 - rem;
  }

  @override
  int decode(Uint8List buffer, int bufferIndex, {bool compound = false}) {
    int start = headerStart = bufferIndex;
    bufferIndex += readHeaderWireFormat(buffer, bufferIndex);
    if (isErrorResponseStatus()) {
      bufferIndex += readErrorResponse(buffer, bufferIndex);
    } else {
      bufferIndex += readBytesWireFormat(buffer, bufferIndex);
    }

    length = bufferIndex - start;
    int len = length;

    if (nextCommand != 0) {
      // padding becomes part of signature if this is _PART_ of a compound chain
      len += pad8(bufferIndex);
    } else if (compound && nextCommand == 0 && readSize > 0) {
      // TODO: only apply this for actual compound chains, or is this correct for single responses, too?
      // 3.2.5.1.9 Handling Compounded Responses
      // The final response in the compounded response chain will have NextCommand equal to 0,
      // and it MUST be processed as an individual message of a size equal to the number of byte?s
      // remaining in this receive.
      int rem = readSize - length;
      len += rem;
    }

    haveResponse(buffer, start, len);

    if (nextCommand != 0 && next != null) {
      if (nextCommand % 8 != 0) {
        throw SmbProtocolDecodingException("Chained command is not aligned");
      }
    }
    return len;
  }

  bool isErrorResponseStatus() {
    return getStatus() != 0;
  }

  void haveResponse(Uint8List buffer, int start, int len) {}

  int readErrorResponse(Uint8List buffer, int bufferIndex) {
    int start = bufferIndex;
    int structureSize = SMBUtil.readInt2(buffer, bufferIndex);
    if (structureSize != 9) {
      throw SmbProtocolDecodingException("Error structureSize should be 9");
    }
    errorContextCount = buffer[bufferIndex + 2];
    bufferIndex += 4;

    int bc = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;

    if (bc > 0) {
      errorData = Uint8List(bc);
      byteArrayCopy(
          src: buffer,
          srcOffset: bufferIndex,
          dst: errorData!,
          dstOffset: 0,
          length: bc);
      bufferIndex += bc;
    }
    return bufferIndex - start;
  }

  int writeHeaderWireFormat(Uint8List dst, int dstIndex) {
    byteArrayCopy(
        src: SMBUtil.SMB2_HEADER,
        srcOffset: 0,
        dst: dst,
        dstOffset: dstIndex,
        length: SMBUtil.SMB2_HEADER.length);

    SMBUtil.writeInt2(creditCharge, dst, dstIndex + 6);
    SMBUtil.writeInt2(command, dst, dstIndex + 12);
    SMBUtil.writeInt2(credit, dst, dstIndex + 14);
    SMBUtil.writeInt4(flags, dst, dstIndex + 16);
    SMBUtil.writeInt4(nextCommand, dst, dstIndex + 20);
    SMBUtil.writeInt8(mid, dst, dstIndex + 24);

    if (async) {
      SMBUtil.writeInt8(asyncId, dst, dstIndex + 32);
      SMBUtil.writeInt8(sessionId, dst, dstIndex + 40);
    } else {
      // 4 reserved
      SMBUtil.writeInt4(treeId, dst, dstIndex + 36);
      SMBUtil.writeInt8(sessionId, dst, dstIndex + 40);
      // + signature
    }

    return Smb2Constants.SMB2_HEADER_LENGTH;
  }

  int readHeaderWireFormat(Uint8List buffer, int bufferIndex) {
    // these are common between SYNC/ASYNC
    SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    SMBUtil.readInt2(buffer, bufferIndex);
    creditCharge = SMBUtil.readInt2(buffer, bufferIndex + 2);
    bufferIndex += 4;
    status = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    command = SMBUtil.readInt2(buffer, bufferIndex);
    credit = SMBUtil.readInt2(buffer, bufferIndex + 2);
    bufferIndex += 4;

    flags = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    nextCommand = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    mid = SMBUtil.readInt8(buffer, bufferIndex);
    bufferIndex += 8;

    if ((flags & Smb2Constants.SMB2_FLAGS_ASYNC_COMMAND) ==
        Smb2Constants.SMB2_FLAGS_ASYNC_COMMAND) {
      // async
      async = true;
      asyncId = SMBUtil.readInt8(buffer, bufferIndex);
      bufferIndex += 8;
      sessionId = SMBUtil.readInt8(buffer, bufferIndex);
      bufferIndex += 8;
      byteArrayCopy(
          src: buffer,
          srcOffset: bufferIndex,
          dst: signature,
          dstOffset: 0,
          length: 16);
      bufferIndex += 16;
    } else {
      // sync
      async = false;
      bufferIndex += 4; // reserved
      treeId = SMBUtil.readInt4(buffer, bufferIndex);
      bufferIndex += 4;
      sessionId = SMBUtil.readInt8(buffer, bufferIndex);
      bufferIndex += 8;
      byteArrayCopy(
          src: buffer,
          srcOffset: bufferIndex,
          dst: signature,
          dstOffset: 0,
          length: 16);
      bufferIndex += 16;
    }

    return Smb2Constants.SMB2_HEADER_LENGTH;
  }

  bool isResponse() {
    return (flags & Smb2Constants.SMB2_FLAGS_SERVER_TO_REDIR) ==
        Smb2Constants.SMB2_FLAGS_SERVER_TO_REDIR;
  }

  int writeBytesWireFormat(Uint8List dst, int dstIndex);

  int readBytesWireFormat(Uint8List buffer, int bufferIndex);

  @override
  String toString() {
    String c = Smb2Constants.commandToString(command);
    String str = status == 0
        ? "SUCCESS"
        : "${SmbException.getMessageByCode(status)}(${status.toRadixString(16)})";
    return "command=$c,status=$str,flags=0x${Hexdump.toHexString(flags, 4)},mid=$mid,wordCount=$wordCount,byteCount=$byteCount";
  }
}
