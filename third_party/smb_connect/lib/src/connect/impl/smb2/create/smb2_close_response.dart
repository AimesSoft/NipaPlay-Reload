import 'dart:typed_data';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_response.dart';
import 'package:smb_connect/src/connect/fscc/smb_basic_file_info.dart';
import 'package:smb_connect/src/connect/smb_util.dart';

class Smb2CloseResponse extends ServerMessageBlock2Response
    implements SmbBasicFileInfo {
  static const int SMB2_CLOSE_FLAG_POSTQUERY_ATTRIB = 0x1;

  final Uint8List _fileId;
  final String _fileName;
  int _closeFlags = 0;
  int _creationTime = 0;
  int _lastAccessTime = 0;
  int _lastWriteTime = 0;
  int _changeTime = 0;
  int _allocationSize = 0;
  int _endOfFile = 0;
  int _fileAttributes = 0;

  Smb2CloseResponse(super.config, Uint8List fileId, String fileName)
      : _fileId = fileId,
        _fileName = fileName;

  int getCloseFlags() {
    return _closeFlags;
  }

  int getCreationTime() {
    return _creationTime;
  }

  @override
  int getCreateTime() {
    return getCreationTime();
  }

  @override
  int getLastAccessTime() {
    return _lastAccessTime;
  }

  @override
  int getLastWriteTime() {
    return _lastWriteTime;
  }

  int getChangeTime() {
    return _changeTime;
  }

  int getAllocationSize() {
    return _allocationSize;
  }

  int getEndOfFile() {
    return _endOfFile;
  }

  Uint8List getFileId() {
    return _fileId;
  }

  String getFileName() {
    return _fileName;
  }

  @override
  int getSize() {
    return getEndOfFile();
  }

  int getFileAttributes() {
    return _fileAttributes;
  }

  @override
  int getAttributes() {
    return getFileAttributes();
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    return 0;
  }

  @override
  @protected
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    int start = bufferIndex;
    int structureSize = SMBUtil.readInt2(buffer, bufferIndex);
    if (structureSize != 60) {
      throw SmbProtocolDecodingException("Expected structureSize = 60");
    }
    _closeFlags = SMBUtil.readInt2(buffer, bufferIndex + 2);
    bufferIndex += 4;
    bufferIndex += 4; // Reserved
    _creationTime = SMBUtil.readTime(buffer, bufferIndex);
    bufferIndex += 8;
    _lastAccessTime = SMBUtil.readTime(buffer, bufferIndex);
    bufferIndex += 8;
    _lastWriteTime = SMBUtil.readTime(buffer, bufferIndex);
    bufferIndex += 8;
    _changeTime = SMBUtil.readTime(buffer, bufferIndex);
    bufferIndex += 8;
    _allocationSize = SMBUtil.readInt8(buffer, bufferIndex);
    bufferIndex += 8;
    _endOfFile = SMBUtil.readInt8(buffer, bufferIndex);
    bufferIndex += 8;
    _fileAttributes = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    return bufferIndex - start;
  }
}
