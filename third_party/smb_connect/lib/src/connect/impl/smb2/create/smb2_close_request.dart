import 'dart:typed_data';

import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/impl/smb2/request_with_file_id.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_constants.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/extensions.dart';

import 'smb2_close_response.dart';

class Smb2CloseRequest extends ServerMessageBlock2Request<Smb2CloseResponse>
    implements RequestWithFileId {
  Uint8List _fileId;
  final String _fileName;
  int closeFlags = 0;

  Smb2CloseRequest(super.config, {Uint8List? fileId, String fileName = ""})
      : _fileId = fileId ?? Smb2Constants.UNSPECIFIED_FILEID,
        _fileName = fileName,
        super(command: Smb2Constants.SMB2_CLOSE);

  @override
  void setFileId(Uint8List fileId) {
    _fileId = fileId;
  }

  @override
  @protected
  Smb2CloseResponse createResponse(
      Configuration config, ServerMessageBlock2Request<Smb2CloseResponse> req) {
    return Smb2CloseResponse(config, _fileId, _fileName);
  }

  void setCloseFlags(int flags) {
    closeFlags = flags;
  }

  @override
  int size() {
    return ServerMessageBlock2.size8(Smb2Constants.SMB2_HEADER_LENGTH + 24);
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;
    SMBUtil.writeInt2(24, dst, dstIndex);
    SMBUtil.writeInt2(closeFlags, dst, dstIndex + 2);
    dstIndex += 4;
    dstIndex += 4; // Reserved
    byteArrayCopy(
        src: _fileId, srcOffset: 0, dst: dst, dstOffset: dstIndex, length: 16);
    dstIndex += 16;
    return dstIndex - start;
  }

  @override
  @protected
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }
}
