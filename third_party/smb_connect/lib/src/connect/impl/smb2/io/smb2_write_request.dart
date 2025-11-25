import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/impl/smb2/request_with_file_id.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_constants.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/extensions.dart';

import 'smb2_write_response.dart';

class Smb2WriteRequest extends ServerMessageBlock2Request<Smb2WriteResponse>
    implements RequestWithFileId {
  static const int OVERHEAD = Smb2Constants.SMB2_HEADER_LENGTH + 48;

  final Uint8List? data1;
  final List<int>? data2;
  final int dataOffset;
  final int dataLength;

  Uint8List fileId;
  final int offset;
  final int channel;
  final int remainingBytes;
  final int writeFlags;

  Smb2WriteRequest(
    super.config,
    this.fileId, {
    this.data1,
    this.data2,
    this.dataOffset = 0,
    this.dataLength = 0,
    this.offset = 0,
    this.channel = 0,
    this.remainingBytes = 0,
    this.writeFlags = 0,
    super.credit = 0,
  }) : super(command: Smb2Constants.SMB2_WRITE);

  @override
  void setFileId(Uint8List fileId) {
    this.fileId = fileId;
  }

  @override
  @protected
  Smb2WriteResponse createResponse(
      Configuration config, ServerMessageBlock2Request<Smb2WriteResponse> req) {
    return Smb2WriteResponse(config);
  }

  @override
  int size() {
    return ServerMessageBlock2.size8(
        Smb2Constants.SMB2_HEADER_LENGTH + 48 + dataLength);
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;
    SMBUtil.writeInt2(49, dst, dstIndex);
    int dataOffsetOffset = dstIndex + 2;
    dstIndex += 4;
    SMBUtil.writeInt4(dataLength, dst, dstIndex);
    dstIndex += 4;
    SMBUtil.writeInt8(offset, dst, dstIndex);
    dstIndex += 8;
    byteArrayCopy(
        src: fileId, srcOffset: 0, dst: dst, dstOffset: dstIndex, length: 16);
    dstIndex += 16;
    SMBUtil.writeInt4(channel, dst, dstIndex);
    dstIndex += 4;
    SMBUtil.writeInt4(remainingBytes, dst, dstIndex);
    dstIndex += 4;

    SMBUtil.writeInt2(0, dst, dstIndex); // writeChannelInfoOffset
    SMBUtil.writeInt2(0, dst, dstIndex + 2); // writeChannelInfoLength
    dstIndex += 4;

    SMBUtil.writeInt4(writeFlags, dst, dstIndex);
    dstIndex += 4;

    SMBUtil.writeInt2(dstIndex - getHeaderStart(), dst, dataOffsetOffset);

    if (dstIndex + dataLength > dst.length) {
      throw SmbIllegalArgumentException(
          "Data exceeds buffer size ( remain buffer: ${dst.length - dstIndex} data length: $dataLength)");
    }

    if (data1 != null) {
      byteArrayCopy(
          src: data1!,
          srcOffset: dataOffset,
          dst: dst,
          dstOffset: dstIndex,
          length: dataLength);
    } else {
      intArrayCopy(
          src: data2!,
          srcOffset: dataOffset,
          dst: dst,
          dstOffset: dstIndex,
          length: dataLength);
    }
    dstIndex += dataLength;
    return dstIndex - start;
  }

  @override
  @protected
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }
}
