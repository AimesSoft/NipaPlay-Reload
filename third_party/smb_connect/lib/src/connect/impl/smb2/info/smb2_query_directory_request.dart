import 'dart:math';
import 'dart:typed_data';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/impl/smb2/info/smb2_query_directory_response.dart';
import 'package:smb_connect/src/connect/impl/smb2/request_with_file_id.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_constants.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/extensions.dart';
import 'package:smb_connect/src/utils/strings.dart';

class Smb2QueryDirectoryRequest
    extends ServerMessageBlock2Request<Smb2QueryDirectoryResponse>
    implements RequestWithFileId {
  static const int FILE_DIRECTORY_INFO = 0x1;
  static const int FILE_FULL_DIRECTORY_INFO = 0x2;
  static const int FILE_BOTH_DIRECTORY_INFO = 0x03;
  static const int FILE_NAMES_INFO = 0x0C;
  static const int FILE_ID_BOTH_DIRECTORY_INFO = 0x24;
  static const int FILE_ID_FULL_DIRECTORY_INFO = 0x26;
  static const int SMB2_RESTART_SCANS = 0x1;
  static const int SMB2_RETURN_SINGLE_ENTRY = 0x2;
  static const int SMB2_INDEX_SPECIFIED = 0x4;
  static const int SMB2_REOPEN = 0x10;

  int _fileInformationClass = FILE_BOTH_DIRECTORY_INFO;
  int _queryFlags = 0;
  int _fileIndex = 0;
  Uint8List _fileId;
  int _outputBufferLength = 0;
  String? _fileName;

  Smb2QueryDirectoryRequest(Configuration config, {Uint8List? fileId})
      : _fileId = fileId ?? Smb2Constants.UNSPECIFIED_FILEID,
        super(config, command: Smb2Constants.SMB2_QUERY_DIRECTORY) {
    _outputBufferLength = (min(config.maximumBufferSize, config.listSize) -
            Smb2QueryDirectoryResponse.OVERHEAD) &
        ~0x7;
  }

  @override
  void setFileId(Uint8List fileId) {
    _fileId = fileId;
  }

  void setFileInformationClass(int fileInformationClass) {
    _fileInformationClass = fileInformationClass;
  }

  void setQueryFlags(int queryFlags) {
    _queryFlags = queryFlags;
  }

  void setFileIndex(int fileIndex) {
    _fileIndex = fileIndex;
  }

  void setFileName(String fileName) {
    _fileName = fileName;
  }

  @override
  @protected
  Smb2QueryDirectoryResponse createResponse(Configuration config,
      ServerMessageBlock2Request<Smb2QueryDirectoryResponse> req) {
    return Smb2QueryDirectoryResponse(config, _fileInformationClass);
  }

  @override
  int size() {
    return ServerMessageBlock2.size8(Smb2Constants.SMB2_HEADER_LENGTH +
        32 +
        (_fileName != null ? 2 * _fileName!.length : 0));
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;
    SMBUtil.writeInt2(33, dst, dstIndex);
    dst[dstIndex + 2] = _fileInformationClass;
    dst[dstIndex + 3] = _queryFlags;
    dstIndex += 4;
    SMBUtil.writeInt4(_fileIndex, dst, dstIndex);
    dstIndex += 4;
    byteArrayCopy(
        src: _fileId, srcOffset: 0, dst: dst, dstOffset: dstIndex, length: 16);
    dstIndex += 16;

    int fnOffsetOffset = dstIndex;
    int fnLengthOffset = dstIndex + 2;
    dstIndex += 4;

    SMBUtil.writeInt4(_outputBufferLength, dst, dstIndex);
    dstIndex += 4;

    if (_fileName == null) {
      SMBUtil.writeInt2(0, dst, fnOffsetOffset);
      SMBUtil.writeInt2(0, dst, fnLengthOffset);
    } else {
      Uint8List fnBytes = _fileName.getUNIBytes();
      SMBUtil.writeInt2(dstIndex - getHeaderStart(), dst, fnOffsetOffset);
      SMBUtil.writeInt2(fnBytes.length, dst, fnLengthOffset);
      byteArrayCopy(
          src: fnBytes,
          srcOffset: 0,
          dst: dst,
          dstOffset: dstIndex,
          length: fnBytes.length);
      dstIndex += fnBytes.length;
    }
    return dstIndex - start;
  }

  @override
  @protected
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }
}
