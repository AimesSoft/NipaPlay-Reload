import 'dart:typed_data';

import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/strings.dart';

import '../../../fscc/smb_basic_file_info.dart';
import '../and_x_server_message_block.dart';

class SmbComNTCreateAndXResponse extends AndXServerMessageBlock
    implements SmbBasicFileInfo {
  static const int EXCLUSIVE_OPLOCK_GRANTED = 1;
  static const int BATCH_OPLOCK_GRANTED = 2;
  static const int LEVEL_II_OPLOCK_GRANTED = 3;

  int oplockLevel = 0;
  int fid = 0,
      createAction = 0,
      extFileAttributes = 0,
      fileType = 0,
      deviceState = 0;
  int creationTime = 0,
      lastAccessTime = 0,
      lastWriteTime = 0,
      changeTime = 0,
      allocationSize = 0,
      endOfFile = 0;
  bool directory = false;
  bool _isExtended = false;

  SmbComNTCreateAndXResponse(super.config);

  int getFileType() {
    return fileType;
  }

  bool isExtended() {
    return _isExtended;
  }

  void setExtended(bool isExtended) {
    _isExtended = isExtended;
  }

  int getOplockLevel() {
    return oplockLevel;
  }

  int getFid() {
    return fid;
  }

  int getCreateAction() {
    return createAction;
  }

  int getExtFileAttributes() {
    return extFileAttributes;
  }

  @override
  int getAttributes() {
    return getExtFileAttributes();
  }

  int getDeviceState() {
    return deviceState;
  }

  int getCreationTime() {
    return creationTime;
  }

  @override
  int getCreateTime() {
    return getCreationTime();
  }

  @override
  int getLastAccessTime() {
    return lastAccessTime;
  }

  @override
  int getLastWriteTime() {
    return lastWriteTime;
  }

  int getAllocationSize() {
    return allocationSize;
  }

  int getEndOfFile() {
    return endOfFile;
  }

  @override
  int getSize() {
    return getEndOfFile();
  }

  @override
  int writeParameterWordsWireFormat(Uint8List dst, int dstIndex) {
    return 0;
  }

  @override
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    return 0;
  }

  @override
  int readParameterWordsWireFormat(Uint8List buffer, int bufferIndex) {
    int start = bufferIndex;

    oplockLevel = buffer[bufferIndex++];
    fid = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;
    createAction = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    creationTime = SMBUtil.readTime(buffer, bufferIndex);
    bufferIndex += 8;
    lastAccessTime = SMBUtil.readTime(buffer, bufferIndex);
    bufferIndex += 8;
    lastWriteTime = SMBUtil.readTime(buffer, bufferIndex);
    bufferIndex += 8;
    changeTime = SMBUtil.readTime(buffer, bufferIndex);
    bufferIndex += 8;
    extFileAttributes = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    allocationSize = SMBUtil.readInt8(buffer, bufferIndex);
    bufferIndex += 8;
    endOfFile = SMBUtil.readInt8(buffer, bufferIndex);
    bufferIndex += 8;
    fileType = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;
    deviceState = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;
    directory = (buffer[bufferIndex++] & 0xFF) > 0;
    return bufferIndex - start;
  }

  @override
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }

  @override
  String toString() {
    return "SmbComNTCreateAndXResponse[${super.toString()},oplockLevel=$oplockLevel,fid=$fid,createAction=0x${Hexdump.toHexString(createAction, 4)},creationTime=${DateTime.fromMillisecondsSinceEpoch(creationTime)},lastAccessTime=${DateTime.fromMillisecondsSinceEpoch(lastAccessTime)},lastWriteTime=${DateTime.fromMillisecondsSinceEpoch(lastWriteTime)},changeTime=${DateTime.fromMillisecondsSinceEpoch(changeTime)},extFileAttributes=0x${Hexdump.toHexString(extFileAttributes, 4)},allocationSize=$allocationSize,endOfFile=$endOfFile,fileType=$fileType,deviceState=$deviceState,directory=$directory]";
  }
}
