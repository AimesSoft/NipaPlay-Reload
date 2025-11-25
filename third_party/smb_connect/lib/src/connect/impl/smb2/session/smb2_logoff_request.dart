import 'dart:typed_data';

import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/session/smb2_logoff_response.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_constants.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/base.dart';

class Smb2LogoffRequest extends ServerMessageBlock2Request<Smb2LogoffResponse> {
  Smb2LogoffRequest(super.config) : super(command: Smb2Constants.SMB2_LOGOFF);

  @override
  @protected
  Smb2LogoffResponse createResponse(Configuration config,
      ServerMessageBlock2Request<Smb2LogoffResponse> req) {
    return Smb2LogoffResponse(config);
  }

  @override
  int size() {
    return ServerMessageBlock2.size8(Smb2Constants.SMB2_HEADER_LENGTH + 4);
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    SMBUtil.writeInt2(4, dst, dstIndex);
    SMBUtil.writeInt2(0, dst, dstIndex + 2);
    return 4;
  }

  @override
  @protected
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }
}
