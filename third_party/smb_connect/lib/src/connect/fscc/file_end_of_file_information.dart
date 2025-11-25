import 'dart:typed_data';

import 'package:smb_connect/src/encodable.dart';
import 'package:smb_connect/src/connect/fscc/file_information.dart';
import 'package:smb_connect/src/connect/smb_util.dart';

// TODO: all vars to final decode to factory constructor
class FileEndOfFileInformation implements FileInformation, Encodable {
  int _endOfFile = 0;

  FileEndOfFileInformation([int eofOfFile = 0]) : _endOfFile = eofOfFile;

  @override
  int getFileInformationLevel() {
    return FileInformation.FILE_ENDOFFILE_INFO;
  }

  @override
  int decode(Uint8List buffer, int bufferIndex, int len) {
    _endOfFile = SMBUtil.readInt8(buffer, bufferIndex);
    return 8;
  }

  @override
  int size() {
    return 8;
  }

  @override
  int encode(Uint8List dst, int dstIndex) {
    SMBUtil.writeInt8(_endOfFile, dst, dstIndex);
    return 8;
  }

  @override
  String toString() {
    return "EndOfFileInformation[endOfFile=$_endOfFile]";
  }
}
