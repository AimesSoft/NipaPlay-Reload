import 'dart:typed_data';

import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_constants.dart';
import 'package:smb_connect/src/connect/impl/smb2/tree/smb2_tree_connect_response.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/extensions.dart';
import 'package:smb_connect/src/utils/strings.dart';

class Smb2TreeConnectRequest
    extends ServerMessageBlock2Request<Smb2TreeConnectResponse> {
  int treeFlags = 0;
  String path;

  Smb2TreeConnectRequest(super.config, this.path)
      : super(command: Smb2Constants.SMB2_TREE_CONNECT);

  @override
  @protected
  Smb2TreeConnectResponse createResponse(Configuration config,
      ServerMessageBlock2Request<Smb2TreeConnectResponse> req) {
    return Smb2TreeConnectResponse(config);
  }

  @override
  bool chain(ServerMessageBlock2 n) {
    n.setTreeId(Smb2Constants.UNSPECIFIED_TREEID);
    return super.chain(n);
  }

  @override
  int size() {
    return ServerMessageBlock2.size8(
        Smb2Constants.SMB2_HEADER_LENGTH + 8 + path.length * 2);
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;
    SMBUtil.writeInt2(9, dst, dstIndex);
    SMBUtil.writeInt2(treeFlags, dst, dstIndex + 2);
    dstIndex += 4;

    Uint8List data = path.getUNIBytes();
    int offsetOffset = dstIndex;
    SMBUtil.writeInt2(data.length, dst, dstIndex + 2);
    dstIndex += 4;
    SMBUtil.writeInt2(dstIndex - getHeaderStart(), dst, offsetOffset);

    byteArrayCopy(
        src: data,
        srcOffset: 0,
        dst: dst,
        dstOffset: dstIndex,
        length: data.length);
    dstIndex += data.length;
    return dstIndex - start;
  }

  @override
  @protected
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }
}
