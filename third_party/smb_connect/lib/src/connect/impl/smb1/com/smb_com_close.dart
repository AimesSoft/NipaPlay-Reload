import 'dart:typed_data';
import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/connect/common/request.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_blank_response.dart';
import 'package:smb_connect/src/connect/impl/smb1/server_message_block.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb1_signing_digest.dart';
import 'package:smb_connect/src/connect/smb_util.dart';

class SmbComClose extends ServerMessageBlock
    implements Request<SmbComBlankResponse> {
  final int _fid;
  final int _lastWriteTime;

  SmbComClose(super.config, this._fid, this._lastWriteTime)
      : super(command: SmbComConstants.SMB_COM_CLOSE);

  @override
  SmbComBlankResponse getResponse() {
    return super.getResponse() as SmbComBlankResponse;
  }

  @override
  SmbComBlankResponse initResponse(Configuration config) {
    SmbComBlankResponse resp = SmbComBlankResponse(config);
    setResponse(resp);
    return resp;
  }

  @override
  @protected
  int writeParameterWordsWireFormat(Uint8List dst, int dstIndex) {
    SMBUtil.writeInt2(_fid, dst, dstIndex);
    dstIndex += 2;
    if (digest != null) {
      SMB1SigningDigest.writeUTime(config, _lastWriteTime, dst, dstIndex);
    } else {
      // log.trace("SmbComClose without a digest");
    }
    return 6;
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    return 0;
  }

  @override
  @protected
  int readParameterWordsWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }

  @override
  @protected
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }

  @override
  String toString() {
    return "SmbComClose[${super.toString()},fid=$_fid,lastWriteTime=$_lastWriteTime]";
  }
}
