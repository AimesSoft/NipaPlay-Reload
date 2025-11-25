import 'dart:typed_data';

import 'package:smb_connect/src/connect/fscc/basic_file_information.dart';
import 'package:smb_connect/src/connect/fscc/file_information.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/strings.dart';

// TODO: all vars to final decode to factory constructor
class FileBasicInfo implements BasicFileInformation {
  int createTime = 0;
  int lastAccessTime = 0;
  int lastWriteTime = 0;
  int changeTime = 0;
  int attributes = 0;

  FileBasicInfo({
    this.createTime = 0,
    this.lastAccessTime = 0,
    this.lastWriteTime = 0,
    this.changeTime = 0,
    this.attributes = 0,
  });

  FileBasicInfo.all(
    this.createTime,
    this.lastAccessTime,
    this.lastWriteTime,
    this.changeTime,
    this.attributes,
  );

  @override
  int getFileInformationLevel() => FileInformation.FILE_BASIC_INFO;

  @override
  int getAttributes() {
    return attributes;
  }

  @override
  int getCreateTime() {
    return createTime;
  }

  @override
  int getLastWriteTime() {
    return lastWriteTime;
  }

  @override
  int getLastAccessTime() {
    return lastAccessTime;
  }

  @override
  int getSize() {
    return 0;
  }

  @override
  int decode(Uint8List buffer, int bufferIndex, int len) {
    int start = bufferIndex;
    createTime = SMBUtil.readTime(buffer, bufferIndex);
    bufferIndex += 8;
    lastAccessTime = SMBUtil.readTime(buffer, bufferIndex);
    bufferIndex += 8;
    lastWriteTime = SMBUtil.readTime(buffer, bufferIndex);
    bufferIndex += 8;
    changeTime = SMBUtil.readTime(buffer, bufferIndex);
    bufferIndex += 8;
    attributes = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    return bufferIndex - start;
  }

  @override
  int size() {
    return 40;
  }

  @override
  int encode(Uint8List dst, int dstIndex) {
    int start = dstIndex;
    SMBUtil.writeTime(createTime, dst, dstIndex);
    dstIndex += 8;
    SMBUtil.writeTime(lastAccessTime, dst, dstIndex);
    dstIndex += 8;
    SMBUtil.writeTime(lastWriteTime, dst, dstIndex);
    dstIndex += 8;
    SMBUtil.writeTime(changeTime, dst, dstIndex);
    dstIndex += 8;
    SMBUtil.writeInt4(attributes, dst, dstIndex);
    dstIndex += 4;
    dstIndex += 4;
    return dstIndex - start;
  }

  @override
  String toString() {
    return "SmbQueryFileBasicInfo[createTime=${DateTime.fromMillisecondsSinceEpoch(createTime)},lastAccessTime=${DateTime.fromMillisecondsSinceEpoch(lastAccessTime)},lastWriteTime=${DateTime.fromMillisecondsSinceEpoch(lastWriteTime)},changeTime=${DateTime.fromMillisecondsSinceEpoch(changeTime)},attributes=0x${Hexdump.toHexString(attributes, 4)}]";
  }
}
