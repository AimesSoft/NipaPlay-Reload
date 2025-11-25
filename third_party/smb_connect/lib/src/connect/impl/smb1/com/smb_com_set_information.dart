import 'dart:typed_data';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/connect/impl/smb1/server_message_block.dart';
import 'package:smb_connect/src/connect/smb_util.dart';

class SmbComSetInformation extends ServerMessageBlock {
  final int _fileAttributes;
  final int _lastWriteTime;

  SmbComSetInformation(super.config, String filename, int attrs, int mtime)
      : _fileAttributes = attrs,
        _lastWriteTime = mtime,
        super(command: SmbComConstants.SMB_COM_SET_INFORMATION, path: filename);

  @override
  @protected
  int writeParameterWordsWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;
    SMBUtil.writeInt2(_fileAttributes, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeUTime(_lastWriteTime, dst, dstIndex);
    dstIndex += 4;
    // reserved
    dstIndex += 10;
    int len = dstIndex - start;
    return len;
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;
    dst[dstIndex++] = 0x04;
    dstIndex += writeString(path!, dst, dstIndex);
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
    return "SmbComSetInformation[${super.toString()},filename=$path,fileAttributes=$_fileAttributes,lastWriteTime=$_lastWriteTime]";
  }
}
