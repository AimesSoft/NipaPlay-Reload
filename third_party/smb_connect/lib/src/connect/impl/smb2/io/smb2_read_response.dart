import 'dart:math';
import 'dart:typed_data';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_response.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_constants.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/smb/nt_status.dart';
import 'package:smb_connect/src/utils/extensions.dart';

class Smb2ReadResponse extends ServerMessageBlock2Response {
  static const int OVERHEAD = Smb2Constants.SMB2_HEADER_LENGTH + 16;

  int dataRemaining = 0;
  int dataLength = 0;
  final Uint8List outputBuffer;
  final int outputBufferOffset;

  Smb2ReadResponse(
      super.config, this.outputBuffer, this.outputBufferOffset); // {

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
    if (structureSize == 9) {
      return readErrorResponse(buffer, bufferIndex);
    } else if (structureSize != 17) {
      throw SmbProtocolDecodingException("Expected structureSize = 17");
    }

    int dataOffset = buffer[bufferIndex + 2];
    bufferIndex += 4;
    dataLength = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    dataRemaining = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    bufferIndex += 4; // Reserved2

    int dataStart = getHeaderStart() + dataOffset;

    if (dataLength + outputBufferOffset > outputBuffer.length) {
      throw SmbProtocolDecodingException("Buffer to small for read response");
    }
    byteArrayCopy(
        src: buffer,
        srcOffset: dataStart,
        dst: outputBuffer,
        dstOffset: outputBufferOffset,
        length: dataLength);
    bufferIndex = max(bufferIndex, dataStart + dataLength);
    return bufferIndex - start;
  }

  @override
  @protected
  bool isErrorResponseStatus() {
    return getStatus() != NtStatus.NT_STATUS_BUFFER_OVERFLOW &&
        super.isErrorResponseStatus();
  }
}
