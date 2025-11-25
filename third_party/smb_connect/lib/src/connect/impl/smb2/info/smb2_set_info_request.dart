import 'dart:typed_data';

import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/encodable.dart';
import 'package:smb_connect/src/connect/fscc/file_information.dart';
import 'package:smb_connect/src/connect/impl/smb2/request_with_file_id.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_constants.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/extensions.dart';

import 'smb2_set_info_response.dart';

class Smb2SetInfoRequest extends ServerMessageBlock2Request<Smb2SetInfoResponse>
    implements RequestWithFileId {
  Uint8List _fileId;
  final int infoType;
  final int _fileInfoClass;
  final int additionalInformation;
  final Encodable _info;

  Smb2SetInfoRequest(
    super.config,
    FileInformation fi,
    this._info, {
    Uint8List? fileId,
    this.infoType = Smb2Constants.SMB2_0_INFO_FILE,
    this.additionalInformation = 0,
  })  : _fileId = fileId ?? Smb2Constants.UNSPECIFIED_FILEID,
        _fileInfoClass = fi.getFileInformationLevel(),
        super(command: Smb2Constants.SMB2_SET_INFO);

  @override
  void setFileId(Uint8List fileId) {
    _fileId = fileId;
  }

  @override
  @protected
  Smb2SetInfoResponse createResponse(Configuration config,
      ServerMessageBlock2Request<Smb2SetInfoResponse> req) {
    return Smb2SetInfoResponse(config);
  }

  @override
  int size() {
    return ServerMessageBlock2.size8(
        Smb2Constants.SMB2_HEADER_LENGTH + 32 + _info.size());
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;
    SMBUtil.writeInt2(33, dst, dstIndex);
    dst[dstIndex + 2] = infoType;
    dst[dstIndex + 3] = _fileInfoClass;
    dstIndex += 4;

    int bufferLengthOffset = dstIndex;
    dstIndex += 4;
    int bufferOffsetOffset = dstIndex;
    dstIndex += 4;

    SMBUtil.writeInt4(additionalInformation, dst, dstIndex);
    dstIndex += 4;

    byteArrayCopy(
        src: _fileId, srcOffset: 0, dst: dst, dstOffset: dstIndex, length: 16);
    dstIndex += 16;

    SMBUtil.writeInt2(dstIndex - getHeaderStart(), dst, bufferOffsetOffset);
    int len = _info.encode(dst, dstIndex);
    SMBUtil.writeInt4(len, dst, bufferLengthOffset);
    dstIndex += len;
    return dstIndex - start;
  }

  @override
  @protected
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }
}
