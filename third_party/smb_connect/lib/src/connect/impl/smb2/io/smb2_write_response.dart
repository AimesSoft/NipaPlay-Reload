import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_response.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/base.dart';

class Smb2WriteResponse extends ServerMessageBlock2Response {
  int count = 0;
  int remaining = 0;

  Smb2WriteResponse(super.config);

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
    if (structureSize != 17) {
      throw SmbProtocolDecodingException("Expected structureSize = 17");
    }
    bufferIndex += 4;

    count = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    remaining = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    bufferIndex += 4; // WriteChannelInfoOffset/WriteChannelInfoLength
    return bufferIndex - start;
  }
}
