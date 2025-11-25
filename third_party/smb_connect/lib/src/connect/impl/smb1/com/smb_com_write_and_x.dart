import 'dart:typed_data';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/impl/smb1/and_x_server_message_block.dart';
import 'package:smb_connect/src/connect/impl/smb1/server_message_block.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/extensions.dart';

class SmbComWriteAndX extends AndXServerMessageBlock {
  int _fid = 0, _remaining = 0, _dataLength = 0, _dataOffset = 0, _off = 0;
  Uint8List? _data1;
  List<int>? _data2;
  int _offset = 0;
  int _pad = 0;
  int _writeMode = 0;

  SmbComWriteAndX(super.config,
      [int fid = 0,
      int offset = 0,
      int remaining = 0,
      Uint8List? data,
      int off = 0,
      int len = 0,
      ServerMessageBlock? andx])
      : _fid = fid,
        _offset = offset,
        _remaining = remaining,
        _data1 = data,
        _off = off,
        _dataLength = len,
        super(command: SmbComConstants.SMB_COM_WRITE_ANDX, andx: andx);

  void setParam1(
      int fid, int offset, int remaining, Uint8List data, int off, int len) {
    _fid = fid;
    _offset = offset;
    _remaining = remaining;
    _data1 = data;
    _off = off;
    _dataLength = len;
    digest = null;

    ///
    /// otherwise recycled commands
    /// like writeandx will choke if session
    /// closes in between
    ///
  }

  void setParam2(
      int fid, int offset, int remaining, List<int> data, int off, int len) {
    _fid = fid;
    _offset = offset;
    _remaining = remaining;
    _data2 = data;
    _off = off;
    _dataLength = len;
    digest = null;

    ///
    /// otherwise recycled commands
    /// like writeandx will choke if session
    /// closes in between
    ///
  }

  void setWriteMode(int writeMode) {
    _writeMode = writeMode;
  }

  @override
  @protected
  int getBatchLimit(Configuration cfg, int cmd) {
    if (cmd == SmbComConstants.SMB_COM_READ_ANDX) {
      return cfg.getBatchLimit(cmd); //"WriteAndX.ReadAndX");
    }
    if (cmd == SmbComConstants.SMB_COM_CLOSE) {
      return cfg.getBatchLimit(cmd); //"WriteAndX.Close");
    }
    return 0;
  }

  @override
  @protected
  int writeParameterWordsWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;

    _dataOffset = (dstIndex - headerStart) + 26; // 26 = off from here to pad

    _pad = (_dataOffset - headerStart) % 4;
    _pad = _pad == 0 ? 0 : 4 - _pad;
    _dataOffset += _pad;

    SMBUtil.writeInt2(_fid, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt4(_offset, dst, dstIndex);
    dstIndex += 4;
    for (int i = 0; i < 4; i++) {
      dst[dstIndex++] = 0xFF;
    }
    SMBUtil.writeInt2(_writeMode, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt2(_remaining, dst, dstIndex);
    dstIndex += 2;
    dst[dstIndex++] = 0x00;
    dst[dstIndex++] = 0x00;
    SMBUtil.writeInt2(_dataLength, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt2(_dataOffset, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt4(_offset >> 32, dst, dstIndex);
    dstIndex += 4;

    return dstIndex - start;
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;

    while (_pad-- > 0) {
      dst[dstIndex++] = 0xEE;
    }
    if (_data1 != null) {
      byteArrayCopy(
          src: _data1!,
          srcOffset: _off,
          dst: dst,
          dstOffset: dstIndex,
          length: _dataLength);
      dstIndex += _dataLength;
    } else {
      intArrayCopy(
          src: _data2!,
          srcOffset: _off,
          dst: dst,
          dstOffset: dstIndex,
          length: _dataLength);
      dstIndex += _dataLength;
    }

    return dstIndex - start;
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
    return "SmbComWriteAndX[${super.toString()},fid=$_fid,offset=$_offset,writeMode=$_writeMode,remaining=$_remaining,dataLength=$_dataLength,dataOffset=$_dataOffset]";
  }
}
