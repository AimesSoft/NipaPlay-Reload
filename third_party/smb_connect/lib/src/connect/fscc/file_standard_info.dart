import 'dart:typed_data';

import 'package:smb_connect/src/connect/fscc/basic_file_information.dart';
import 'package:smb_connect/src/connect/fscc/file_information.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/smb_constants.dart';

// TODO: all vars to final decode to factory constructor
class FileStandardInfo implements BasicFileInformation {
  int allocationSize = 0;
  int endOfFile = 0;
  int numberOfLinks = 0;
  bool deletePending = false;
  bool directory = false;

  @override
  int getFileInformationLevel() {
    return FileInformation.FILE_STANDARD_INFO;
  }

  @override
  int getAttributes() {
    return (directory ? SmbConstants.ATTR_DIRECTORY : 0);
  }

  @override
  int getCreateTime() {
    return 0;
  }

  @override
  int getLastWriteTime() {
    return 0;
  }

  @override
  int getLastAccessTime() {
    return 0;
  }

  @override
  int getSize() {
    return endOfFile;
  }

  @override
  int decode(Uint8List buffer, int bufferIndex, int len) {
    int start = bufferIndex;
    allocationSize = SMBUtil.readInt8(buffer, bufferIndex);
    bufferIndex += 8;
    endOfFile = SMBUtil.readInt8(buffer, bufferIndex);
    bufferIndex += 8;
    numberOfLinks = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    deletePending = (buffer[bufferIndex++] & 0xFF) > 0;
    directory = (buffer[bufferIndex++] & 0xFF) > 0;
    return bufferIndex - start;
  }

  @override
  int size() {
    return 22;
  }

  @override
  int encode(Uint8List dst, int dstIndex) {
    int start = dstIndex;
    SMBUtil.writeInt8(allocationSize, dst, dstIndex);
    dstIndex += 8;
    SMBUtil.writeInt8(endOfFile, dst, dstIndex);
    dstIndex += 8;
    SMBUtil.writeInt4(numberOfLinks, dst, dstIndex);
    dstIndex += 4;
    dst[dstIndex++] = deletePending ? 1 : 0;
    dst[dstIndex++] = directory ? 1 : 0;
    return dstIndex - start;
  }

  @override
  String toString() {
    return "SmbQueryInfoStandard[allocationSize=$allocationSize,endOfFile=$endOfFile,numberOfLinks=$numberOfLinks,deletePending=$deletePending,directory=$directory]";
  }
}
