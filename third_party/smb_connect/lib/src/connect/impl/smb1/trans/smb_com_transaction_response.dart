import 'dart:typed_data';

import 'package:smb_connect/src/connect/impl/smb1/server_message_block.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/enumeration.dart';
import 'package:smb_connect/src/utils/extensions.dart';

import '../../../../smb/file_entry.dart';

abstract class SmbComTransactionResponse extends ServerMessageBlock
    implements Enumeration<SmbComTransactionResponse> {
  // relative to headerStart
  static const int SETUP_OFFSET = 61;

  static const int DISCONNECT_TID = 0x01;
  static const int ONE_WAY_TRANSACTION = 0x02;

  int _pad = 0;
  int _pad1 = 0;
  bool _parametersDone = false, _dataDone = false;

  int totalParameterCount = 0;
  int totalDataCount = 0;
  int parameterCount = 0;
  int parameterOffset = 0;
  int parameterDisplacement = 0;
  int dataOffset = 0;
  int dataDisplacement = 0;
  int setupCount = 0;
  int bufParameterStart = 0;
  int bufDataStart = 0;

  int dataCount = 0;
  int subCommand;
  bool hasMore = true;
  bool isPrimary = true;
  Uint8List? txnBuf;

  /// for doNetEnum and doFindFirstNext */
  int status = 0;
  int numEntries = 0;
  List<FileEntry>? results;

  SmbComTransactionResponse(super.config, {super.command, this.subCommand = 0});

  void setBuffer(Uint8List buffer) {
    txnBuf = buffer;
  }

  Uint8List? releaseBuffer() {
    Uint8List? buf = txnBuf;
    txnBuf = null;
    return buf;
  }

  @override
  void setReceived() {
    if (hasMore) {
      return;
    }
    super.setReceived();
  }

  @override
  void reset() {
    super.reset();
    bufDataStart = 0;
    isPrimary = hasMore = true;
    _parametersDone = _dataDone = false;
  }

  @override
  bool hasMoreElements() {
    return errorCode == 0 && hasMore;
  }

  @override
  SmbComTransactionResponse nextElement() {
    if (isPrimary) {
      isPrimary = false;
    }
    return this;
  }

  @override
  int writeParameterWordsWireFormat(Uint8List dst, int dstIndex) {
    return 0;
  }

  @override
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    return 0;
  }

  @override
  int decode(Uint8List buffer, int bufferIndex) {
    int len = super.decode(buffer, bufferIndex);
    if (byteCount == 0) {
      // otherwise hasMore may not be correctly set
      readBytesWireFormat(buffer, len + bufferIndex);
    }
    nextElement();
    return len;
  }

  @override
  int readParameterWordsWireFormat(Uint8List buffer, int bufferIndex) {
    int start = bufferIndex;

    totalParameterCount = SMBUtil.readInt2(buffer, bufferIndex);
    if (bufDataStart == 0) {
      bufDataStart = totalParameterCount;
    }
    bufferIndex += 2;
    totalDataCount = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 4; // Reserved
    parameterCount = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;
    parameterOffset = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;
    parameterDisplacement = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;
    dataCount = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;
    dataOffset = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;
    dataDisplacement = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;
    setupCount = buffer[bufferIndex] & 0xFF;
    bufferIndex += 2;

    return bufferIndex - start;
  }

  @override
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    _pad = _pad1 = 0;
    if (parameterCount > 0) {
      bufferIndex += _pad = parameterOffset - (bufferIndex - headerStart);
      byteArrayCopy(
          src: buffer,
          srcOffset: bufferIndex,
          dst: txnBuf!,
          dstOffset: bufParameterStart + parameterDisplacement,
          length: parameterCount);
      bufferIndex += parameterCount;
    }
    if (dataCount > 0) {
      bufferIndex += _pad1 = dataOffset - (bufferIndex - headerStart);
      byteArrayCopy(
          src: buffer,
          srcOffset: bufferIndex,
          dst: txnBuf!,
          dstOffset: bufDataStart + dataDisplacement,
          length: dataCount);
      bufferIndex += dataCount;
    }

    ///
    /// Check to see if the entire transaction has been
    /// read. If so call the read methods.

    if (!_parametersDone &&
        (parameterDisplacement + parameterCount) == totalParameterCount) {
      _parametersDone = true;
    }

    if (!_dataDone && (dataDisplacement + dataCount) == totalDataCount) {
      _dataDone = true;
    }

    if (_parametersDone && _dataDone) {
      readParametersWireFormat(txnBuf!, bufParameterStart, totalParameterCount);
      readDataWireFormat(txnBuf!, bufDataStart, totalDataCount);
      hasMore = false;
    }

    return _pad + parameterCount + _pad1 + dataCount;
  }

  int writeSetupWireFormat(Uint8List dst, int dstIndex);

  int writeParametersWireFormat(Uint8List dst, int dstIndex);

  int writeDataWireFormat(Uint8List dst, int dstIndex);

  int readSetupWireFormat(Uint8List buffer, int bufferIndex, int len);

  int readParametersWireFormat(Uint8List buffer, int bufferIndex, int len);

  int readDataWireFormat(Uint8List buffer, int bufferIndex, int len);

  @override
  String toString() {
    return "${super.toString()},totalParameterCount=$totalParameterCount,totalDataCount=$totalDataCount,parameterCount=$parameterCount,parameterOffset=$parameterOffset,parameterDisplacement=$parameterDisplacement,dataCount=$dataCount,dataOffset=$dataOffset,dataDisplacement=$dataDisplacement,setupCount=$setupCount,pad=$_pad,pad1=$_pad1";
  }
}
