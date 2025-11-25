import 'dart:math';
import 'dart:typed_data';

import 'package:smb_connect/src/connect/impl/smb1/server_message_block.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/extensions.dart';
import 'package:smb_connect/src/utils/strings.dart';

import '../../../../utils/enumeration.dart';

abstract class SmbComTransaction extends ServerMessageBlock
    implements Enumeration<SmbComTransaction> {
  // relative to headerStart
  static const int PRIMARY_SETUP_OFFSET = 61;
  static const int SECONDARY_PARAMETER_OFFSET = 51;

  static const int DISCONNECT_TID = 0x01;
  static const int ONE_WAY_TRANSACTION = 0x02;

  static const int PADDING_SIZE = 4;

  final int _tflags = 0x00;
  int _pad1 = 0;
  int _pad2 = 0;
  bool _hasMore = true;
  bool _isPrimary = true;
  final int _bufParameterOffset = 0;
  int _bufDataOffset = 0;

  static const int TRANSACTION_BUF_SIZE = 0xFFFF;

  static const int TRANS2_FIND_FIRST2 = 0x01;
  static const int TRANS2_FIND_NEXT2 = 0x02;
  static const int TRANS2_QUERY_FS_INFORMATION = 0x03;
  static const int TRANS2_QUERY_PATH_INFORMATION = 0x05;
  static const int TRANS2_GET_DFS_REFERRAL = 0x10;
  static const int TRANS2_QUERY_FILE_INFORMATION = 0x07;
  static const int TRANS2_SET_FILE_INFORMATION = 0x08;

  static const int NET_SHARE_ENUM = 0x00;
  static const int NET_SERVER_ENUM2 = 0x68;
  static const int NET_SERVER_ENUM3 = 0xD7;

  static const int TRANS_PEEK_NAMED_PIPE = 0x23;
  static const int TRANS_WAIT_NAMED_PIPE = 0x53;
  static const int TRANS_CALL_NAMED_PIPE = 0x54;
  static const int TRANS_TRANSACT_NAMED_PIPE = 0x26;

  int primarySetupOffset = 0;
  int secondaryParameterOffset = 0;
  int parameterCount = 0;
  int parameterOffset = 0;
  int parameterDisplacement = 0;
  int dataCount = 0;
  int dataOffset = 0;
  int dataDisplacement = 0;

  int totalParameterCount = 0;
  int totalDataCount = 0;
  int maxParameterCount = 0;
  int maxDataCount = 0;
  int maxSetupCount = 0;
  int timeout = 0;
  int setupCount = 1;
  int subCommand = 0;
  String name = "";
  int maxBufferSize =
      0; // set in SmbTransport.sendTransaction() before nextElement called

  Uint8List? txnBuf;

  SmbComTransaction(super.config, int command, {this.subCommand = 0})
      : super(command: command) {
    // this.subCommand = subCommand;
    maxDataCount = config.transactionBufferSize - 512;
    maxParameterCount = 1024;
    primarySetupOffset = PRIMARY_SETUP_OFFSET;
    secondaryParameterOffset = SECONDARY_PARAMETER_OFFSET;
  }

  void setMaxBufferSize(int maxBufferSize) {
    this.maxBufferSize = maxBufferSize;
  }

  void setMaxDataCount(int maxDataCount) {
    this.maxDataCount = maxDataCount;
  }

  void setBuffer(Uint8List buffer) {
    txnBuf = buffer;
  }

  Uint8List? releaseBuffer() {
    Uint8List? buf = txnBuf;
    txnBuf = null;
    return buf;
  }

  int getSubCommand() {
    return subCommand;
  }

  void setSubCommand(int subCommand) {
    this.subCommand = subCommand;
  }

  @override
  void reset() {
    super.reset();
    _isPrimary = _hasMore = true;
  }

  void reset2(int key, String? lastName) {
    reset();
  }

  @override
  bool hasMoreElements() {
    return _hasMore;
  }

  @override
  SmbComTransaction nextElement() {
    if (_isPrimary) {
      _isPrimary = false;

      // primarySetupOffset
      // SMB_COM_TRANSACTION: 61 = 32 SMB header + 1 (word count) + 28 (fixed words)
      // SMB_COM_NT_TRANSACTION: 69 = 32 SMB header + 1 (word count) + 38 (fixed words)
      parameterOffset = primarySetupOffset;

      // 2* setupCount
      parameterOffset += setupCount * 2;
      parameterOffset += 2; // ByteCount

      if (getCommand() == SmbComConstants.SMB_COM_TRANSACTION &&
          isResponse() == false) {
        parameterOffset += stringWireLength(name, parameterOffset);
      }

      _pad1 = pad(parameterOffset);
      parameterOffset += _pad1;

      totalParameterCount =
          writeParametersWireFormat(txnBuf!, _bufParameterOffset);
      _bufDataOffset = totalParameterCount; // data comes right after data

      int available = maxBufferSize - parameterOffset;
      parameterCount = min(totalParameterCount, available);
      available -= parameterCount;

      dataOffset = parameterOffset + parameterCount;
      _pad2 = pad(dataOffset);
      dataOffset += _pad2;

      totalDataCount = writeDataWireFormat(txnBuf!, _bufDataOffset);

      dataCount = min(totalDataCount, available);
    } else {
      if (getCommand() != SmbComConstants.SMB_COM_NT_TRANSACT) {
        setCommand(SmbComConstants.SMB_COM_TRANSACTION_SECONDARY);
      } else {
        setCommand(SmbComConstants.SMB_COM_NT_TRANSACT_SECONDARY);
      }
      // totalParameterCount and totalDataCount are set ok from primary

      parameterOffset = SECONDARY_PARAMETER_OFFSET;
      if ((totalParameterCount - parameterDisplacement) > 0) {
        _pad1 = pad(parameterOffset);
        parameterOffset += _pad1;
      }

      // caclulate parameterDisplacement before calculating parameterCount
      parameterDisplacement += parameterCount;

      int available = maxBufferSize - parameterOffset - _pad1;
      parameterCount =
          min(totalParameterCount - parameterDisplacement, available);
      available -= parameterCount;

      dataOffset = parameterOffset + parameterCount;
      _pad2 = pad(dataOffset);
      dataOffset += _pad2;

      dataDisplacement += dataCount;

      available -= _pad2;
      dataCount = min(totalDataCount - dataDisplacement, available);
    }
    if ((parameterDisplacement + parameterCount) >= totalParameterCount &&
        (dataDisplacement + dataCount) >= totalDataCount) {
      _hasMore = false;
    }
    return this;
  }

  int pad(int offset) {
    int p = offset % getPadding();
    if (p == 0) {
      return 0;
    }
    return getPadding() - p;
  }

  int getPadding() {
    return PADDING_SIZE;
  }

  @override
  int writeParameterWordsWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;

    SMBUtil.writeInt2(totalParameterCount, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt2(totalDataCount, dst, dstIndex);
    dstIndex += 2;
    if (getCommand() != SmbComConstants.SMB_COM_TRANSACTION_SECONDARY) {
      SMBUtil.writeInt2(maxParameterCount, dst, dstIndex);
      dstIndex += 2;
      SMBUtil.writeInt2(maxDataCount, dst, dstIndex);
      dstIndex += 2;
      dst[dstIndex++] = maxSetupCount;
      dst[dstIndex++] = 0x00; // Reserved1
      SMBUtil.writeInt2(_tflags, dst, dstIndex);
      dstIndex += 2;
      SMBUtil.writeInt4(timeout, dst, dstIndex);
      dstIndex += 4;
      dst[dstIndex++] = 0x00; // Reserved2
      dst[dstIndex++] = 0x00;
    }
    SMBUtil.writeInt2(parameterCount, dst, dstIndex);
    dstIndex += 2;
    // writeInt2(( parameterCount == 0 ? 0 : parameterOffset ), dst, dstIndex );
    SMBUtil.writeInt2(parameterOffset, dst, dstIndex);
    dstIndex += 2;
    if (getCommand() == SmbComConstants.SMB_COM_TRANSACTION_SECONDARY) {
      SMBUtil.writeInt2(parameterDisplacement, dst, dstIndex);
      dstIndex += 2;
    }
    SMBUtil.writeInt2(dataCount, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt2((dataCount == 0 ? 0 : dataOffset), dst, dstIndex);
    dstIndex += 2;
    if (getCommand() == SmbComConstants.SMB_COM_TRANSACTION_SECONDARY) {
      SMBUtil.writeInt2(dataDisplacement, dst, dstIndex);
      dstIndex += 2;
    } else {
      dst[dstIndex++] = setupCount;
      dst[dstIndex++] = 0x00; // Reserved3
      dstIndex += writeSetupWireFormat(dst, dstIndex);
    }

    return dstIndex - start;
  }

  @override
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;

    if (getCommand() == SmbComConstants.SMB_COM_TRANSACTION &&
        isResponse() == false) {
      dstIndex += writeString(name, dst, dstIndex);
    }

    int end = dstIndex + _pad1;

    if (parameterCount > 0) {
      byteArrayCopy(
          src: txnBuf!,
          srcOffset: _bufParameterOffset,
          dst: dst,
          dstOffset: headerStart + parameterOffset,
          length: parameterCount);
      end = max(end, headerStart + parameterOffset + parameterCount + _pad2);
    }

    if (dataCount > 0) {
      byteArrayCopy(
          src: txnBuf!,
          srcOffset: _bufDataOffset,
          dst: dst,
          dstOffset: headerStart + dataOffset,
          length: dataCount);
      _bufDataOffset += dataCount;
      end = max(end, headerStart + dataOffset + dataCount);
    }

    return end - start;
  }

  @override
  int readParameterWordsWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }

  @override
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }

  int writeSetupWireFormat(Uint8List dst, int dstIndex);

  int writeParametersWireFormat(Uint8List dst, int dstIndex);

  int writeDataWireFormat(Uint8List dst, int dstIndex);

  int readSetupWireFormat(Uint8List buffer, int bufferIndex, int len);

  int readParametersWireFormat(Uint8List buffer, int bufferIndex, int len);

  int readDataWireFormat(Uint8List buffer, int bufferIndex, int len);

  @override
  String toString() {
    return "${super.toString()},totalParameterCount=$totalParameterCount,totalDataCount=$totalDataCount,maxParameterCount=$maxParameterCount,maxDataCount=$maxDataCount,maxSetupCount=$maxSetupCount,flags=0x${Hexdump.toHexString(_tflags, 2)},timeout=$timeout,parameterCount=$parameterCount,parameterOffset=$parameterOffset,parameterDisplacement=$parameterDisplacement,dataCount=$dataCount,dataOffset=$dataOffset,dataDisplacement=$dataDisplacement,setupCount=$setupCount,pad=$_pad1,pad1=$_pad2";
  }
}
