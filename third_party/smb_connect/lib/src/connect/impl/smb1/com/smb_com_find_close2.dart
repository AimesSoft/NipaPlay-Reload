import 'dart:typed_data';

import 'package:smb_connect/src/connect/impl/smb1/server_message_block.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/base.dart';

class SmbComFindClose2 extends ServerMessageBlock {
  final int _sid;

  SmbComFindClose2(super.config, this._sid)
      : super(command: SmbComConstants.SMB_COM_FIND_CLOSE2);

  @override
  @protected
  int writeParameterWordsWireFormat(Uint8List dst, int dstIndex) {
    SMBUtil.writeInt2(_sid, dst, dstIndex);
    return 2;
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
    return "SmbComFindClose2[${super.toString()},sid=$_sid]";
  }
}
