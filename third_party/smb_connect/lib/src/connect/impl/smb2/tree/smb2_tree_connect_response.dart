import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_response.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/connect/common/tree_connect_response.dart';
import 'package:smb_connect/src/utils/base.dart';

class Smb2TreeConnectResponse extends ServerMessageBlock2Response
    implements TreeConnectResponse {
  int shareType = 0;
  int shareFlags = 0;
  int capabilities = 0;
  int maximalAccess = 0;

  Smb2TreeConnectResponse(super.config);

  @override
  void prepare(CommonServerMessageBlockRequest next) {
    if (isReceived()) {
      (next as ServerMessageBlock2).setTreeId(getTreeId());
    }
    super.prepare(next);
  }

  @override
  int getTid() {
    return getTreeId();
  }

  // @override
  // bool isShareDfs() {
  //   return (shareFlags &
  //               (Smb2Constants.SMB2_SHAREFLAG_DFS |
  //                   Smb2Constants.SMB2_SHAREFLAG_DFS_ROOT)) !=
  //           0 ||
  //       (capabilities & Smb2Constants.SMB2_SHARE_CAP_DFS) ==
  //           Smb2Constants.SMB2_SHARE_CAP_DFS;
  // }

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
    if (structureSize != 16) {
      throw SmbProtocolDecodingException("Structure size is not 16");
    }

    shareType = buffer[bufferIndex + 2];
    bufferIndex += 4;
    shareFlags = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    capabilities = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    maximalAccess = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    return bufferIndex - start;
  }
}
