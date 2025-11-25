import 'dart:typed_data';

import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/connect/impl/smb1/trans/smb_com_transaction.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/extensions.dart';

class TransTransactNamedPipe extends SmbComTransaction {
  final Uint8List _pipeData;
  final int _pipeFid, _pipeDataOff, _pipeDataLen;

  TransTransactNamedPipe(
      Configuration config, int fid, Uint8List data, int off, int len)
      : _pipeFid = fid,
        _pipeData = data,
        _pipeDataOff = off,
        _pipeDataLen = len,
        super(config, SmbComConstants.SMB_COM_TRANSACTION,
            subCommand: SmbComTransaction.TRANS_TRANSACT_NAMED_PIPE) {
    maxParameterCount = 0;
    maxDataCount = 0xFFFF;
    maxSetupCount = 0x00;
    setupCount = 2;
    name = "\\PIPE\\";
  }

  @override
  @protected
  int writeSetupWireFormat(Uint8List dst, int dstIndex) {
    dst[dstIndex++] = getSubCommand();
    dst[dstIndex++] = 0x00;
    SMBUtil.writeInt2(_pipeFid, dst, dstIndex);
    dstIndex += 2;
    return 4;
  }

  @override
  @protected
  int readSetupWireFormat(Uint8List buffer, int bufferIndex, int len) {
    return 0;
  }

  @override
  @protected
  int writeParametersWireFormat(Uint8List dst, int dstIndex) {
    return 0;
  }

  @override
  @protected
  int writeDataWireFormat(Uint8List dst, int dstIndex) {
    if ((dst.length - dstIndex) < _pipeDataLen) {
      return 0;
    }
    byteArrayCopy(
        src: _pipeData,
        srcOffset: _pipeDataOff,
        dst: dst,
        dstOffset: dstIndex,
        length: _pipeDataLen);
    return _pipeDataLen;
  }

  @override
  @protected
  int readParametersWireFormat(Uint8List buffer, int bufferIndex, int len) {
    return 0;
  }

  @override
  @protected
  int readDataWireFormat(Uint8List buffer, int bufferIndex, int len) {
    return 0;
  }

  @override
  String toString() {
    return "TransTransactNamedPipe[${super.toString()},pipeFid=$_pipeFid]";
  }
}
