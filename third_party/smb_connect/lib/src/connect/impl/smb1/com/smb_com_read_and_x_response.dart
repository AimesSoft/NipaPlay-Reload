import 'dart:typed_data';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/connect/impl/smb1/and_x_server_message_block.dart';
import 'package:smb_connect/src/connect/smb_util.dart';

class SmbComReadAndXResponse extends AndXServerMessageBlock {
  Uint8List? _data;
  int _offset = 0, _dataCompactionMode = 0, _dataLength = 0, _dataOffset = 0;

  SmbComReadAndXResponse(super.config, [this._data, this._offset = 0]);

  void setParam(Uint8List b, int off) {
    _data = b;
    _offset = off;
  }

  Uint8List? getData() {
    return _data;
  }

  int getOffset() {
    return _offset;
  }

  void adjustOffset(int n) {
    _offset += n;
  }

  int getDataLength() {
    return _dataLength;
  }

  int getDataOffset() {
    return _dataOffset;
  }

  @override
  @protected
  int writeParameterWordsWireFormat(Uint8List dst, int dstIndex) {
    return 0;
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    return 0;
  }

  @override
  @protected
  int readParameterWordsWireFormat(Uint8List buffer, int bufferIndex) {
    int start = bufferIndex;

    bufferIndex += 2; // reserved
    _dataCompactionMode = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 4; // 2 reserved
    _dataLength = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;
    _dataOffset = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 12; // 10 reserved

    return bufferIndex - start;
  }

  @override
  @protected
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    // handled special in SmbTransport.doRecv()
    return 0;
  }

  @override
  String toString() {
    return "SmbComReadAndXResponse[${super.toString()},dataCompactionMode=$_dataCompactionMode,dataLength=$_dataLength,dataOffset=$_dataOffset]";
  }
}
