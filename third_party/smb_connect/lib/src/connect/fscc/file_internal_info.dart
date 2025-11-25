import 'dart:typed_data';

import 'package:smb_connect/src/connect/fscc/file_information.dart';
import 'package:smb_connect/src/connect/smb_util.dart';

// TODO: all vars to final decode to factory constructor
class FileInternalInfo implements FileInformation {
  int _indexNumber = 0;

  @override
  int getFileInformationLevel() => FileInformation.FILE_INTERNAL_INFO;

  int getIndexNumber() {
    return _indexNumber;
  }

  @override
  int decode(Uint8List buffer, int bufferIndex, int len) {
    _indexNumber = SMBUtil.readInt8(buffer, bufferIndex);
    return 8;
  }

  @override
  int size() {
    return 8;
  }

  @override
  int encode(Uint8List dst, int dstIndex) {
    SMBUtil.writeInt8(_indexNumber, dst, dstIndex);
    return 8;
  }

  @override
  String toString() {
    return "SmbQueryFileInternalInfo[indexNumber=$_indexNumber]";
  }
}
