import 'dart:typed_data';

import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/impl/smb1/and_x_server_message_block.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/base.dart';

class SmbComReadAndX extends AndXServerMessageBlock {
  int offset;
  int fid;
  int openTimeout = 0xFFFFFFFF;
  late int maxCount, minCount;
  int remaining = 0;

  SmbComReadAndX(super.config, this.fid, this.offset, int maxCount,
      {super.andx})
      : super(command: SmbComConstants.SMB_COM_READ_ANDX) {
    this.maxCount = minCount = maxCount;
  }

  void setOpenTimeout(int openTimeout) {
    this.openTimeout = openTimeout;
  }

  void setParam(int fid, int offset, int maxCount) {
    this.fid = fid;
    this.offset = offset;
    this.maxCount = minCount = maxCount;
  }

  @override
  @protected
  int getBatchLimit(Configuration cfg, int cmd) {
    return cmd == SmbComConstants.SMB_COM_CLOSE
        ? cfg.getBatchLimit(cmd) //"ReadAndX.Close")
        : 0;
  }

  @override
  @protected
  int writeParameterWordsWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;

    SMBUtil.writeInt2(fid, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt4(offset, dst, dstIndex);
    dstIndex += 4;
    SMBUtil.writeInt2(maxCount, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt2(minCount, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt4(openTimeout, dst, dstIndex);
    dstIndex += 4;
    SMBUtil.writeInt2(remaining, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt4(offset >> 32, dst, dstIndex);
    dstIndex += 4;

    return dstIndex - start;
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    return 0;
  }

  @override
  @protected
  int readParameterWordsWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }

  @override
  @protected
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }

  @override
  String toString() {
    return "SmbComReadAndX[${super.toString()},fid=$fid,offset=$offset,maxCount=$maxCount,minCount=$minCount,openTimeout=$openTimeout,remaining=$remaining,offset=$offset]";
  }
}
