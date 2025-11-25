import 'dart:typed_data';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/connect/impl/smb1/server_message_block.dart';
import 'package:smb_connect/src/connect/smb_util.dart';

class SmbComSeek extends ServerMessageBlock {
  int fid;
  int _mode = 0;
  int _offset = 0;

  SmbComSeek(super.config, this.fid)
      : super(command: SmbComConstants.SMB_COM_SEEK);

  void setFid(int fid) {
    this.fid = fid;
  }

  void setMode(int mode) {
    _mode = mode;
  }

  void setOffset(int offset) {
    _offset = offset;
  }

  @override
  @protected
  int writeParameterWordsWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;
    SMBUtil.writeInt2(fid, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt2(_mode, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt4(_offset, dst, dstIndex);
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
}
