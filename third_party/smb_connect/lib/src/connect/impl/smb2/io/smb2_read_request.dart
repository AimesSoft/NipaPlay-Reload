import 'dart:typed_data';
import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/connect/impl/smb2/io/smb2_read_response.dart';
import 'package:smb_connect/src/connect/impl/smb2/request_with_file_id.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_constants.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/extensions.dart';

class Smb2ReadRequest extends ServerMessageBlock2Request<Smb2ReadResponse>
    implements RequestWithFileId {
  static int SMB2_READFLAG_READ_UNBUFFERED = 0x1;
  static int SMB2_CHANNEL_NONE = 0x0;
  static int SMB2_CHANNEL_RDMA_V1 = 0x1;
  static int SMB2_CHANNEL_RDMA_V1_INVALIDATE = 0x2;

  Uint8List fileId;
  final Uint8List outputBuffer;
  final int outputBufferOffset;
  final int padding;
  final int readFlags;
  final int readLength;
  final int offset;
  final int minimumCount;
  final int channel;
  final int remainingBytes;

  Smb2ReadRequest(
    super.config,
    this.fileId,
    this.outputBuffer,
    this.outputBufferOffset, {
    this.padding = 0,
    this.readFlags = 0,
    this.readLength = 0,
    this.offset = 0,
    this.minimumCount = 0,
    this.channel = 0,
    this.remainingBytes = 0,
  }) : super(command: Smb2Constants.SMB2_READ);

  @override
  @protected
  Smb2ReadResponse createResponse(
      Configuration config, ServerMessageBlock2Request<Smb2ReadResponse> req) {
    return Smb2ReadResponse(config, outputBuffer, outputBufferOffset);
  }

  @override
  void setFileId(Uint8List fileId) {
    this.fileId = fileId;
  }

  @override
  int size() {
    return ServerMessageBlock2.size8(Smb2Constants.SMB2_HEADER_LENGTH + 49);
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;
    SMBUtil.writeInt2(49, dst, dstIndex);
    dst[dstIndex + 2] = padding;
    dst[dstIndex + 3] = readFlags;
    dstIndex += 4;
    SMBUtil.writeInt4(readLength, dst, dstIndex);
    dstIndex += 4;
    SMBUtil.writeInt8(offset, dst, dstIndex);
    dstIndex += 8;
    byteArrayCopy(
        src: fileId, srcOffset: 0, dst: dst, dstOffset: dstIndex, length: 16);
    dstIndex += 16;
    SMBUtil.writeInt4(minimumCount, dst, dstIndex);
    dstIndex += 4;
    SMBUtil.writeInt4(channel, dst, dstIndex);
    dstIndex += 4;
    SMBUtil.writeInt4(remainingBytes, dst, dstIndex);
    dstIndex += 4;

    // ReadChannelInfo
    SMBUtil.writeInt2(0, dst, dstIndex);
    SMBUtil.writeInt2(0, dst, dstIndex + 2);
    dstIndex += 4;

    // one int in buffer must be zero
    dst[dstIndex] = 0;
    dstIndex += 1;

    return dstIndex - start;
  }

  @override
  @protected
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }

  @override
  String toString() {
    return "${super.toString()},offset=$offset";
  }
}
