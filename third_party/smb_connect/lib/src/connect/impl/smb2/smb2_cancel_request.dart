import 'dart:typed_data';

import 'package:smb_connect/src/connect/common/common_server_message_block_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_response.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_constants.dart';
import 'package:smb_connect/src/connect/smb_util.dart';

class Smb2CancelRequest extends ServerMessageBlock2
    implements CommonServerMessageBlockRequest {
  Smb2CancelRequest(super.config, int mid, int asyncId) {
    setMid(mid);
    this.asyncId = asyncId;
    if (asyncId != 0) {
      addFlags(Smb2Constants.SMB2_FLAGS_ASYNC_COMMAND);
    }
  }

  @override
  int getCreditCost() {
    return 1;
  }

  @override
  ServerMessageBlock2Request<ServerMessageBlock2Response>? getNext() {
    return null;
  }

  @override
  int? getOverrideTimeout() {
    return null;
  }

  @override
  void setRequestCredits(int value) {
    credit = value;
  }

  @override
  void setTid(int t) {
    setTreeId(t);
  }

  @override
  int size() {
    return ServerMessageBlock2.size8(Smb2Constants.SMB2_HEADER_LENGTH + 4);
  }

  @override
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;
    SMBUtil.writeInt2(4, dst, dstIndex);
    dstIndex += 4;
    return dstIndex - start;
  }

  @override
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }
}
