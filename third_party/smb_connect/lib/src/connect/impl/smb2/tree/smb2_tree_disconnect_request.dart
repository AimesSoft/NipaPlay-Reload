import 'dart:typed_data';

import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_constants.dart';
import 'package:smb_connect/src/connect/impl/smb2/tree/smb2_tree_disconnect_response.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/base.dart';

class Smb2TreeDisconnectRequest
    extends ServerMessageBlock2Request<Smb2TreeDisconnectResponse> {
  Smb2TreeDisconnectRequest(super.config)
      : super(command: Smb2Constants.SMB2_TREE_DISCONNECT);
  @override
  @protected
  Smb2TreeDisconnectResponse createResponse(Configuration config,
      ServerMessageBlock2Request<Smb2TreeDisconnectResponse> req) {
    return Smb2TreeDisconnectResponse(config);
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
