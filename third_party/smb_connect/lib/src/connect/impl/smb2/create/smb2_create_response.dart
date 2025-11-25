import 'dart:math';
import 'dart:typed_data';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/request_with_file_id.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_response.dart';
import 'package:smb_connect/src/connect/fscc/smb_basic_file_info.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/extensions.dart';

class Smb2CreateResponse extends ServerMessageBlock2Response
    implements SmbBasicFileInfo {
  int _oplockLevel = 0;
  int _openFlags = 0;
  int _createAction = 0;
  int _creationTime = 0;
  int _lastAccessTime = 0;
  int _lastWriteTime = 0;
  int _changeTime = 0;
  int _allocationSize = 0;
  int _endOfFile = 0;
  int _fileAttributes = 0;
  final Uint8List fileId = Uint8List(16);
  late final String _fileName;

  Smb2CreateResponse(super.config, this._fileName);

  @override
  void prepare(CommonServerMessageBlockRequest next) {
    if (isReceived() && (next is RequestWithFileId)) {
      (next as RequestWithFileId).setFileId(fileId);
    }
    super.prepare(next);
  }

  int getOplockLevel() => _oplockLevel;
  int getOpenFlags() => _openFlags;
  int getCreateAction() => _createAction;
  int getCreationTime() => _creationTime;
  int getChangeTime() => _changeTime;
  int getAllocationSize() => _allocationSize;
  int getEndOfFile() => _endOfFile;
  int getFileAttributes() => _fileAttributes;

  String getFileName() => _fileName;

  @override
  int getCreateTime() {
    return _creationTime;
  }

  @override
  int getLastAccessTime() {
    return _lastAccessTime;
  }

  @override
  int getLastWriteTime() {
    return _lastWriteTime;
  }

  @override
  int getSize() {
    return _endOfFile;
  }

  @override
  int getAttributes() {
    return _fileAttributes;
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

    if (structureSize != 89) {
      throw SmbProtocolDecodingException("Structure size is not 89");
    }

    _oplockLevel = buffer[bufferIndex + 2];
    _openFlags = buffer[bufferIndex + 3];
    bufferIndex += 4;

    _createAction = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;

    _creationTime = SMBUtil.readTime(buffer, bufferIndex);
    bufferIndex += 8;
    _lastAccessTime = SMBUtil.readTime(buffer, bufferIndex);
    bufferIndex += 8;
    _lastWriteTime = SMBUtil.readTime(buffer, bufferIndex);
    bufferIndex += 8;
    _changeTime = SMBUtil.readTime(buffer, bufferIndex);
    bufferIndex += 8;

    _allocationSize = SMBUtil.readInt8(buffer, bufferIndex);
    bufferIndex += 8;
    _endOfFile = SMBUtil.readInt8(buffer, bufferIndex);
    bufferIndex += 8;

    _fileAttributes = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    bufferIndex += 4; // Reserved2

    byteArrayCopy(
        src: buffer,
        srcOffset: bufferIndex,
        dst: fileId,
        dstOffset: 0,
        length: 16);
    bufferIndex += 16;

    int createContextOffset = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    int createContextLength = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;

    if (createContextOffset > 0 && createContextLength > 0) {
      int createContextStart = getHeaderStart() + createContextOffset;
      int next = 0;
      do {
        int cci = createContextStart;
        next = SMBUtil.readInt4(buffer, cci);
        cci += 4;

        int nameOffset = SMBUtil.readInt2(buffer, cci);
        int nameLength = SMBUtil.readInt2(buffer, cci + 2);
        cci += 4;

        int dataOffset = SMBUtil.readInt2(buffer, cci + 2);
        cci += 4;
        int dataLength = SMBUtil.readInt4(buffer, cci);
        cci += 4;

        Uint8List nameBytes = Uint8List(nameLength);
        byteArrayCopy(
            src: buffer,
            srcOffset: createContextStart + nameOffset,
            dst: nameBytes,
            dstOffset: 0,
            length: nameBytes.length);
        cci = max(cci, createContextStart + nameOffset + nameLength);

        // CreateContextResponse? cc = createContext(nameBytes);
        // if (cc != null) {
        //   cc.decode(buffer, createContextStart + dataOffset, dataLength);
        //   contexts.add(cc);
        // }

        cci = max(cci, createContextStart + dataOffset + dataLength);

        if (next > 0) {
          createContextStart += next;
        }
        bufferIndex = max(bufferIndex, cci);
      } while (next > 0);
      // _createContexts = [];
    }
    return bufferIndex - start;
  }

  // static CreateContextResponse? createContext(Uint8List nameBytes) {
  //   return null;
  // }
}
