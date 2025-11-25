import 'dart:typed_data';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/connect/impl/smb1/and_x_server_message_block.dart';
import 'package:smb_connect/src/connect/fscc/smb_basic_file_info.dart';
import 'package:smb_connect/src/connect/smb_util.dart';

import 'smb_com_seek_response.dart';

class SmbComOpenAndXResponse extends AndXServerMessageBlock
    implements SmbBasicFileInfo {
  int _fid = 0,
      _fileAttributes = 0,
      _fileDataSize = 0,
      _grantedAccess = 0,
      _fileType = 0,
      _deviceState = 0,
      _action = 0,
      _serverFid = 0;
  int _lastWriteTime = 0;

  SmbComOpenAndXResponse(super.config, {SmbComSeekResponse? andxResp})
      : super(andx: andxResp);

  int getFid() {
    return _fid;
  }

  int getDataSize() {
    return _fileDataSize;
  }

  @override
  int getSize() {
    return getDataSize();
  }

  int getGrantedAccess() {
    return _grantedAccess;
  }

  int getFileAttributes() {
    return _fileAttributes;
  }

  @override
  int getAttributes() {
    return getFileAttributes();
  }

  int getFileType() {
    return _fileType;
  }

  int getDeviceState() {
    return _deviceState;
  }

  int getAction() {
    return _action;
  }

  int getServerFid() {
    return _serverFid;
  }

  @override
  int getLastWriteTime() {
    return _lastWriteTime;
  }

  @override
  int getCreateTime() {
    return 0;
  }

  @override
  int getLastAccessTime() {
    return 0;
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

    _fid = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;
    _fileAttributes = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;
    _lastWriteTime = SMBUtil.readUTime(buffer, bufferIndex);
    bufferIndex += 4;
    _fileDataSize = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    _grantedAccess = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;
    _fileType = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;
    _deviceState = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;
    _action = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;
    _serverFid = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 6;

    return bufferIndex - start;
  }

  @override
  @protected
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }

  @override
  String toString() {
    return "SmbComOpenAndXResponse[${super.toString()},fid=$_fid,fileAttributes=$_fileAttributes,lastWriteTime=$_lastWriteTime,dataSize=$_fileDataSize,grantedAccess=$_grantedAccess,fileType=$_fileType,deviceState=$_deviceState,action=$_action,serverFid=$_serverFid]";
  }
}
