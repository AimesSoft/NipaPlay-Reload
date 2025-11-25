import 'dart:math';
import 'dart:typed_data';

import 'package:smb_connect/src/connect/impl/smb2/ioctl/smb2_ioctl_request.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/decodable.dart';
import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/utils/extensions.dart';

import '../../../../smb/nt_status.dart';
import '../server_message_block2_response.dart';

class Smb2IoctlResponse extends ServerMessageBlock2Response {
  Uint8List? outputBuffer;
  int ctlCode;
  Uint8List? fileId;
  int ioctlFlags = 0;
  Decodable? outputData;
  // Decodable? inputData;
  int outputLength = 0;

  Smb2IoctlResponse(super.config, {this.outputBuffer, this.ctlCode = 0});

  @override
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    return 0;
  }

  @override
  bool isErrorResponseStatus() {
    int status = getStatus();
    return status != NtStatus.NT_STATUS_INVALID_PARAMETER &&
        !(status == NtStatus.NT_STATUS_INVALID_PARAMETER
        // && (ctlCode == Smb2IoctlRequest.FSCTL_SRV_COPYCHUNK || ctlCode == Smb2IoctlRequest.FSCTL_SRV_COPYCHUNK_WRITE)
        ) &&
        !(status == NtStatus.NT_STATUS_BUFFER_OVERFLOW &&
            (ctlCode == Smb2IoctlRequest.FSCTL_PIPE_TRANSCEIVE
            // || ctlCode == Smb2IoctlRequest.FSCTL_PIPE_PEEK
            // || ctlCode == Smb2IoctlRequest.FSCTL_DFS_GET_REFERRALS
            )) &&
        super.isErrorResponseStatus();
  }

  @override
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    int start = bufferIndex;
    int structureSize = SMBUtil.readInt2(buffer, bufferIndex);
    if (structureSize == 9) {
      return super.readErrorResponse(buffer, bufferIndex);
    } else if (structureSize != 49) {
      throw SmbProtocolDecodingException("Expected structureSize = 49");
    }
    bufferIndex += 4;
    ctlCode = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;

    fileId = Uint8List(16);
    byteArrayCopy(
        src: buffer,
        srcOffset: bufferIndex,
        dst: fileId!,
        dstOffset: 0,
        length: 16);
    bufferIndex += 16;

    int inputOffset = SMBUtil.readInt4(buffer, bufferIndex) + getHeaderStart();
    bufferIndex += 4;

    int inputCount = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;

    int outputOffset = SMBUtil.readInt4(buffer, bufferIndex) + getHeaderStart();
    bufferIndex += 4;

    int outputCount = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;

    ioctlFlags = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    bufferIndex += 4; // Reserved2

    // inputData = createInputDecodable();
    outputData = outputBuffer == null ? createOutputDecodable() : null;

    // if (inputData != null) {
    //   inputData!.decode(buffer, inputOffset, inputCount);
    // }
    bufferIndex = max(inputOffset + inputCount, bufferIndex);

    if (outputBuffer != null) {
      if (outputCount > outputBuffer!.length) {
        throw SmbProtocolDecodingException("Output length exceeds buffer size");
      }
      byteArrayCopy(
          src: buffer,
          srcOffset: outputOffset,
          dst: outputBuffer!,
          dstOffset: 0,
          length: outputCount);
    } else if (outputData != null) {
      outputData!.decode(buffer, outputOffset, outputCount);
    }
    outputLength = outputCount;
    bufferIndex = max(outputOffset + outputCount, bufferIndex);
    return bufferIndex - start;
  }

  Decodable? createOutputDecodable() {
    switch (ctlCode) {
      // case Smb2IoctlRequest.FSCTL_DFS_GET_REFERRALS:
      //   return DfsReferralResponseBuffer();
      // case Smb2IoctlRequest.FSCTL_SRV_REQUEST_RESUME_KEY:
      //   return SrvRequestResumeKeyResponse();
      // case Smb2IoctlRequest.FSCTL_SRV_COPYCHUNK:
      // case Smb2IoctlRequest.FSCTL_SRV_COPYCHUNK_WRITE:
      //   return SrvCopyChunkCopyResponse();
      // case Smb2IoctlRequest.FSCTL_VALIDATE_NEGOTIATE_INFO:
      //   return ValidateNegotiateInfoResponse();
      // case Smb2IoctlRequest.FSCTL_PIPE_PEEK:
      //   return SrvPipePeekResponse();
    }
    return null;
  }

  // Decodable? createInputDecodable() {
  //   return null;
  // }
}
