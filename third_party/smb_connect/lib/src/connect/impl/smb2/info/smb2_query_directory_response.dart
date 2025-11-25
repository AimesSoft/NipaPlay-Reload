import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/connect/fscc/file_both_directory_info.dart';
import 'package:smb_connect/src/connect/impl/smb2/info/smb2_query_directory_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_response.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_constants.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/smb/file_entry.dart';
import 'package:smb_connect/src/utils/base.dart';

class Smb2QueryDirectoryResponse extends ServerMessageBlock2Response {
  static const int OVERHEAD = Smb2Constants.SMB2_HEADER_LENGTH + 8;

  final int _expectInfoClass;
  List<FileEntry>? _results;

  Smb2QueryDirectoryResponse(super.config, this._expectInfoClass);

  List<FileEntry>? getResults() {
    return _results;
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    return 0;
  }

  @override
  @protected
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    int start = bufferIndex;
    int structureSize = SMBUtil.readInt2(buffer, bufferIndex);

    if (structureSize != 9) {
      throw SmbProtocolDecodingException("Expected structureSize = 9");
    }

    int bufferOffset =
        SMBUtil.readInt2(buffer, bufferIndex + 2) + getHeaderStart();
    bufferIndex += 4;
    int bufferLength = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;

    List<FileEntry> infos = [];
    do {
      FileBothDirectoryInfo? cur = _createFileInfo();
      if (cur == null) {
        break;
      }
      cur.decode(buffer, bufferIndex, bufferLength);
      infos.add(cur);
      int nextEntryOffset = cur.getNextEntryOffset();
      if (nextEntryOffset > 0) {
        bufferIndex += nextEntryOffset;
      } else {
        break;
      }
    } while (bufferIndex < bufferOffset + bufferLength);
    _results = infos;
    return bufferIndex - start;
  }

  FileBothDirectoryInfo? _createFileInfo() {
    if (_expectInfoClass ==
        Smb2QueryDirectoryRequest.FILE_BOTH_DIRECTORY_INFO) {
      return FileBothDirectoryInfo(config, true);
    }
    return null;
  }
}
