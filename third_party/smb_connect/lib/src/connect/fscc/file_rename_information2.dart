import 'dart:typed_data';

import 'package:smb_connect/src/connect/fscc/file_information.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/extensions.dart';
import 'package:smb_connect/src/utils/strings.dart';

// TODO: all vars to final decode to factory constructor
class FileRenameInformation2 implements FileInformation {
  bool _replaceIfExists;
  String? _fileName;

  FileRenameInformation2([String? name, bool replaceIfExists = false])
      : _fileName = name,
        _replaceIfExists = replaceIfExists;

  @override
  int decode(Uint8List buffer, int bufferIndex, int len) {
    int start = bufferIndex;
    _replaceIfExists = buffer[bufferIndex] != 0;
    bufferIndex += 8;
    bufferIndex += 8;

    int nameLen = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    Uint8List nameBytes = Uint8List(nameLen);
    byteArrayCopy(
        src: buffer,
        srcOffset: bufferIndex,
        dst: nameBytes,
        dstOffset: 0,
        length: nameBytes.length);
    bufferIndex += nameLen;
    _fileName = fromUNIBytes(nameBytes, 0, nameBytes.length);
    return bufferIndex - start;
  }

  @override
  int encode(Uint8List dst, int dstIndex) {
    int start = dstIndex;
    dst[dstIndex] = (_replaceIfExists ? 1 : 0);
    dstIndex += 8; // 7 Reserved
    dstIndex += 8; // RootDirectory = 0

    Uint8List nameBytes = _fileName.getUNIBytes();

    SMBUtil.writeInt4(nameBytes.length, dst, dstIndex);
    dstIndex += 4;

    byteArrayCopy(
        src: nameBytes,
        srcOffset: 0,
        dst: dst,
        dstOffset: dstIndex,
        length: nameBytes.length);
    dstIndex += nameBytes.length;

    return dstIndex - start;
  }

  @override
  int size() {
    return 20 + 2 * (_fileName?.length ?? 0);
  }

  @override
  int getFileInformationLevel() => FileInformation.FILE_RENAME_INFO;
}
