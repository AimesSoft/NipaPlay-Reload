import 'dart:typed_data';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/connect/impl/smb1/and_x_server_message_block.dart';
import 'package:smb_connect/src/connect/smb_util.dart';

class SmbComWriteAndXResponse extends AndXServerMessageBlock {
  int _count = 0;

  SmbComWriteAndXResponse(super.config);

  int getCount() {
    return _count;
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
    _count = SMBUtil.readInt2(buffer, bufferIndex) & 0xFFFF;
    return 8;
  }

  @override
  @protected
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }

  @override
  String toString() {
    return "SmbComWriteAndXResponse[${super.toString()},count=$_count]";
  }
}
