import 'dart:typed_data';

import 'package:smb_connect/src/connect/common/alloc_info.dart';
import 'package:smb_connect/src/connect/fscc/file_system_information.dart';
import 'package:smb_connect/src/connect/smb_util.dart';

// TODO: all vars to final decode to factory constructor
class SmbInfoAllocation implements AllocInfo {
  int _alloc = 0; // Also handles SmbQueryFSSizeInfo
  int _free = 0;
  int _sectPerAlloc = 0;
  int _intsPerSect = 0;

  @override
  int getFileSystemInformationClass() =>
      FileSystemInformation.SMB_INFO_ALLOCATION;

  @override
  int getCapacity() {
    return _alloc * _sectPerAlloc * _intsPerSect;
  }

  // @override
  // int getFree() {
  //   return _free * _sectPerAlloc * _intsPerSect;
  // }

  @override
  int decode(Uint8List buffer, int bufferIndex, int len) {
    int start = bufferIndex;
    bufferIndex += 4; // skip idFileSystem

    _sectPerAlloc = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;

    _alloc = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;

    _free = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;

    _intsPerSect = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 4;

    return bufferIndex - start;
  }

  @override
  String toString() {
    return "SmbInfoAllocation[alloc=$_alloc,free=$_free,sectPerAlloc=$_sectPerAlloc,intsPerSect=$_intsPerSect]";
  }
}
