import 'dart:typed_data';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/connect/impl/smb1/trans/smb_com_transaction_response.dart';
import 'package:smb_connect/src/utils/extensions.dart';

class TransTransactNamedPipeResponse extends SmbComTransactionResponse {
  final Uint8List _outputBuffer;

  TransTransactNamedPipeResponse(super.config, this._outputBuffer);

  @override
  @protected
  int writeSetupWireFormat(Uint8List dst, int dstIndex) {
    return 0;
  }

  @override
  @protected
  int writeParametersWireFormat(Uint8List dst, int dstIndex) {
    return 0;
  }

  @override
  @protected
  int writeDataWireFormat(Uint8List dst, int dstIndex) {
    return 0;
  }

  @override
  @protected
  int readSetupWireFormat(Uint8List buffer, int bufferIndex, int len) {
    return 0;
  }

  @override
  @protected
  int readParametersWireFormat(Uint8List buffer, int bufferIndex, int len) {
    return 0;
  }

  @override
  @protected
  int readDataWireFormat(Uint8List buffer, int bufferIndex, int len) {
    if (len > _outputBuffer.length) {
      throw SmbProtocolDecodingException("Payload exceeds buffer size");
    }
    byteArrayCopy(
        src: buffer,
        srcOffset: bufferIndex,
        dst: _outputBuffer,
        dstOffset: 0,
        length: len);
    return len;
  }

  @override
  String toString() {
    return "TransTransactNamedPipeResponse[${super.toString()}]";
  }

  int getResponseLength() {
    return dataCount;
  }
}
