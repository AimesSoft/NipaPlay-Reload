import 'dart:typed_data';
import 'package:smb_connect/src/utils/base.dart';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_response.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/smb/nt_status.dart';
import 'package:smb_connect/src/utils/extensions.dart';

class Smb2SessionSetupResponse extends ServerMessageBlock2Response {
  static const int SMB2_SESSION_FLAGS_IS_GUEST = 0x1;
  static const int SMB2_SESSION_FLAGS_IS_NULL = 0x2;
  static const int SMB2_SESSION_FLAG_ENCRYPT_DATA = 0x4;

  int _sessionFlags = 0;
  Uint8List? blob;

  Smb2SessionSetupResponse(super.config);

  @override
  void prepare(CommonServerMessageBlockRequest next) {
    if (isReceived()) {
      next.setSessionId(getSessionId());
    }
    super.prepare(next);
  }

  @override
  @protected
  bool isErrorResponseStatus() {
    return getStatus() != NtStatus.NT_STATUS_MORE_PROCESSING_REQUIRED &&
        super.isErrorResponseStatus();
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
      throw SmbProtocolDecodingException("Structure size != 9");
    }

    _sessionFlags = SMBUtil.readInt2(buffer, bufferIndex + 2);
    bufferIndex += 4;

    int securityBufferOffset = SMBUtil.readInt2(buffer, bufferIndex);
    int securityBufferLength = SMBUtil.readInt2(buffer, bufferIndex + 2);
    bufferIndex += 4;

    int pad = bufferIndex - (getHeaderStart() + securityBufferOffset);
    blob = Uint8List(securityBufferLength);
    byteArrayCopy(
        src: buffer,
        srcOffset: getHeaderStart() + securityBufferOffset,
        dst: blob!,
        dstOffset: 0,
        length: securityBufferLength);
    bufferIndex += pad;
    bufferIndex += securityBufferLength;

    return bufferIndex - start;
  }

  bool isLoggedInAsGuest() {
    return (_sessionFlags &
            (SMB2_SESSION_FLAGS_IS_GUEST | SMB2_SESSION_FLAGS_IS_NULL)) !=
        0;
  }
}
