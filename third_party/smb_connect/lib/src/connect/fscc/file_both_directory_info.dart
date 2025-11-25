import 'dart:typed_data';

import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/decodable.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/smb/file_entry.dart';
import 'package:smb_connect/src/smb_constants.dart';
import 'package:smb_connect/src/utils/strings.dart';

// TODO: all vars to final decode to factory constructor
class FileBothDirectoryInfo implements FileEntry, Decodable {
  int _nextEntryOffset = 0;
  int _fileIndex = 0;
  int _creationTime = 0;
  int _lastAccessTime = 0;
  int _lastWriteTime = 0;
  // int _changeTime = 0;
  int _endOfFile = 0;
  int _allocationSize = 0;
  int _extFileAttributes = 0;
  int _eaSize = 0;
  String? _shortName;
  String? _filename;
  final Configuration config;
  final bool unicode;

  FileBothDirectoryInfo(this.config, this.unicode);

  @override
  String getName() {
    return _filename!;
  }

  @override
  int getType() {
    return SmbConstants.TYPE_FILESYSTEM;
  }

  @override
  int getFileIndex() {
    return _fileIndex;
  }

  String? getFilename() {
    return _filename;
  }

  @override
  int getAttributes() {
    return _extFileAttributes;
  }

  @override
  int createTime() {
    return _creationTime;
  }

  @override
  int lastModified() {
    return _lastWriteTime;
  }

  @override
  int lastAccess() {
    return _lastAccessTime;
  }

  @override
  int length() {
    return _endOfFile;
  }

  int getNextEntryOffset() {
    return _nextEntryOffset;
  }

  @override
  int decode(Uint8List buffer, int bufferIndex, int len) {
    int start = bufferIndex;
    _nextEntryOffset = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    _fileIndex = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    _creationTime = SMBUtil.readTime(buffer, bufferIndex);
    bufferIndex += 8;
    _lastAccessTime = SMBUtil.readTime(buffer, bufferIndex);
    bufferIndex += 8;
    _lastWriteTime = SMBUtil.readTime(buffer, bufferIndex);
    bufferIndex += 8;
    // _changeTime = SMBUtil.readTime(buffer, bufferIndex);
    bufferIndex += 8;
    _endOfFile = SMBUtil.readInt8(buffer, bufferIndex);
    bufferIndex += 8;
    _allocationSize = SMBUtil.readInt8(buffer, bufferIndex);
    bufferIndex += 8;
    _extFileAttributes = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    int fileNameLength = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    _eaSize = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;

    int shortNameLength = buffer[bufferIndex] & 0xFF;
    bufferIndex += 2;

    _shortName = fromUNIBytes(buffer, bufferIndex, shortNameLength);
    bufferIndex += 24;

    String str;
    if (unicode) {
      if (fileNameLength > 0 &&
          buffer[bufferIndex + fileNameLength - 1] == 0 && //'\0'
          buffer[bufferIndex + fileNameLength - 2] == 0) {
        //'\0'
        fileNameLength -= 2;
      }
      str = fromUNIBytes(buffer, bufferIndex, fileNameLength);
    } else {
      if (fileNameLength > 0 && buffer[bufferIndex + fileNameLength - 1] == 0) {
        //'\0'
        fileNameLength -= 1;
      }
      str = fromOEMBytes(buffer, bufferIndex, fileNameLength, config);
    }
    _filename = str;
    bufferIndex += fileNameLength;

    return start - bufferIndex;
  }

  @override
  String toString() {
    return "SmbFindFileBothDirectoryInfo[nextEntryOffset=$_nextEntryOffset,fileIndex=$_fileIndex,creationTime=$DateTime.fromMillisecondsSinceEpoch(_creationTime),lastAccessTime=$DateTime.fromMillisecondsSinceEpoch(_lastAccessTime),lastWriteTime=$DateTime.fromMillisecondsSinceEpoch(_lastWriteTime),changeTime=$DateTime.fromMillisecondsSinceEpoch(_changeTime),endOfFile=$_endOfFile,allocationSize=$_allocationSize,extFileAttributes=$_extFileAttributes,eaSize=$_eaSize,shortName=$_shortName,filename=$_filename]";
  }
}
