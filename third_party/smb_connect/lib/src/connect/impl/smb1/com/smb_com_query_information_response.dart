import 'dart:typed_data';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/connect/impl/smb1/server_message_block.dart';
import 'package:smb_connect/src/connect/fscc/smb_basic_file_info.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/strings.dart';

class SmbComQueryInformationResponse extends ServerMessageBlock
    implements SmbBasicFileInfo {
  int _fileAttributes = 0x0000;
  int _lastWriteTime = 0;
  final int _serverTimeZoneOffset;
  int _fileSize = 0;

  SmbComQueryInformationResponse(super.config, this._serverTimeZoneOffset)
      : super(command: SmbComConstants.SMB_COM_QUERY_INFORMATION);

  @override
  int getAttributes() {
    return _fileAttributes;
  }

  @override
  int getCreateTime() {
    return _convertTime(_lastWriteTime);
  }

  int _convertTime(int time) {
    return time + _serverTimeZoneOffset;
  }

  @override
  int getLastWriteTime() {
    return _convertTime(_lastWriteTime);
  }

  @override
  int getLastAccessTime() {
    // Fake access time
    return _convertTime(_lastWriteTime);
  }

  @override
  int getSize() {
    return _fileSize;
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
    if (wordCount == 0) {
      return 0;
    }
    _fileAttributes = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;
    _lastWriteTime = SMBUtil.readUTime(buffer, bufferIndex);
    bufferIndex += 4;
    _fileSize = SMBUtil.readInt4(buffer, bufferIndex);
    return 20;
  }

  @override
  @protected
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }

  @override
  String toString() {
    return "SmbComQueryInformationResponse[${super.toString()},fileAttributes=0x${Hexdump.toHexString(_fileAttributes, 4)},lastWriteTime=${DateTime.fromMillisecondsSinceEpoch(_lastWriteTime)},fileSize=$_fileSize]";
  }
}
