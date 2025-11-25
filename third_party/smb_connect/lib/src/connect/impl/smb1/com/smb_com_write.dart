import 'dart:typed_data';

import 'package:smb_connect/src/connect/impl/smb1/server_message_block.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/extensions.dart';

class SmbComWrite extends ServerMessageBlock {
  int _fid, _count, _offset, _remaining, _off;
  Uint8List? _data1;
  List<int>? _data2;

  SmbComWrite(super.config,
      [int fid = 0,
      int offset = 0,
      int remaining = 0,
      Uint8List? data,
      int off = 0,
      int len = 0])
      : _fid = fid,
        _count = len,
        _offset = offset,
        _remaining = remaining,
        _data1 = data,
        _off = off,
        super(command: SmbComConstants.SMB_COM_WRITE);

  void setParam(
      int fid, int offset, int remaining, Uint8List data, int off, int len) {
    _fid = fid;
    _offset = (offset & 0xFFFFFFFF);
    _remaining = remaining;
    _data1 = data;
    _off = off;
    _count = len;
    digest = null;

    /// otherwise recycled commands
    /// like writeandx will choke if session
    /// closes in between
  }

  void setParam2(
      int fid, int offset, int remaining, List<int> data, int off, int len) {
    _fid = fid;
    _offset = (offset & 0xFFFFFFFF);
    _remaining = remaining;
    _data2 = data;
    _off = off;
    _count = len;
    digest = null;

    /// otherwise recycled commands
    /// like writeandx will choke if session
    /// closes in between
  }

  @override
  @protected
  int writeParameterWordsWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;

    SMBUtil.writeInt2(_fid, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt2(_count, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt4(_offset, dst, dstIndex);
    dstIndex += 4;
    SMBUtil.writeInt2(_remaining, dst, dstIndex);
    dstIndex += 2;

    return dstIndex - start;
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;

    dst[dstIndex++] = 0x01;
    SMBUtil.writeInt2(_count, dst, dstIndex);
    dstIndex += 2;
    if (_data1 != null) {
      byteArrayCopy(
          src: _data1!,
          srcOffset: _off,
          dst: dst,
          dstOffset: dstIndex,
          length: _count);
    } else {
      intArrayCopy(
          src: _data2!,
          srcOffset: _off,
          dst: dst,
          dstOffset: dstIndex,
          length: _count);
    }
    dstIndex += _count;

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
    return "SmbComWrite[${super.toString()},fid=$_fid,count=$_count,offset=$_offset,remaining=$_remaining]";
  }
}
