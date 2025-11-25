import 'dart:typed_data';

import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/session/smb2_session_setup_response.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_constants.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/extensions.dart';

class Smb2SessionSetupRequest
    extends ServerMessageBlock2Request<Smb2SessionSetupResponse> {
  Uint8List? token;
  int capabilities;
  bool sessionBinding = false;
  int previousSessionId;
  int securityMode;

  Smb2SessionSetupRequest(
    super.config,
    this.securityMode,
    this.capabilities,
    this.previousSessionId,
    this.token, {
    super.credit,
    super.retainPayload,
  }) : super(command: Smb2Constants.SMB2_SESSION_SETUP);

  @override
  @protected
  Smb2SessionSetupResponse createResponse(Configuration config,
      ServerMessageBlock2Request<Smb2SessionSetupResponse> req) {
    return Smb2SessionSetupResponse(config);
  }

  @override
  bool chain(ServerMessageBlock2 n) {
    n.setSessionId(Smb2Constants.UNSPECIFIED_SESSIONID);
    return super.chain(n);
  }

  @override
  int size() {
    return ServerMessageBlock2.size8(
        Smb2Constants.SMB2_HEADER_LENGTH + 24 + (token?.length ?? 0));
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;

    SMBUtil.writeInt2(25, dst, dstIndex);

    dst[dstIndex + 2] = (sessionBinding ? 0x1 : 0);
    dst[dstIndex + 3] = (securityMode);
    dstIndex += 4;

    SMBUtil.writeInt4(capabilities, dst, dstIndex);
    dstIndex += 4;
    SMBUtil.writeInt4(0, dst, dstIndex); // Channel
    dstIndex += 4;

    int offsetOffset = dstIndex;
    dstIndex += 2;
    SMBUtil.writeInt2(token?.length ?? 0, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt8(previousSessionId, dst, dstIndex);
    dstIndex += 8;
    SMBUtil.writeInt2(dstIndex - getHeaderStart(), dst, offsetOffset);

    dstIndex += pad8(dstIndex);

    if (token != null) {
      // print("Smb2SessionSetup token: ${token!.toHexString()}");
      byteArrayCopy(
          src: token!,
          srcOffset: 0,
          dst: dst,
          dstOffset: dstIndex,
          length: token!.length);
      dstIndex += token!.length;
    }

    return dstIndex - start;
  }

  @override
  @protected
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }
}
