import 'dart:typed_data';

import 'package:smb_connect/src/decodable.dart';
import 'package:smb_connect/src/connect/fscc/file_system_information.dart';
import 'package:smb_connect/src/connect/smb_util.dart';

import '../common/alloc_info.dart';

// TODO: all vars to final decode to factory constructor
class FileFsFullSizeInformation
    implements AllocInfo, FileSystemInformation, Decodable {
  int _alloc = 0; // Also handles SmbQueryFSSizeInfo
  int _free = 0;
  int _sectPerAlloc = 0;
  int _intsPerSect = 0;

  @override
  int getFileSystemInformationClass() {
    return FileSystemInformation.FS_FULL_SIZE_INFO;
  }

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

    // Read total allocation units.
    _alloc = SMBUtil.readInt8(buffer, bufferIndex);
    bufferIndex += 8;

    // read caller available allocation units
    _free = SMBUtil.readInt8(buffer, bufferIndex);
    bufferIndex += 8;

    // skip actual free units
    bufferIndex += 8;

    _sectPerAlloc = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;

    _intsPerSect = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;

    return bufferIndex - start;
  }

  @override
  String toString() {
    return "SmbInfoAllocation[alloc=$_alloc,free=$_free,sectPerAlloc=$_sectPerAlloc,intsPerSect=$_intsPerSect]";
  }
}
