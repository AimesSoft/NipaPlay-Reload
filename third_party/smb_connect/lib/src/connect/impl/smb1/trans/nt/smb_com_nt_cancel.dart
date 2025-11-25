import 'dart:typed_data';

import 'package:smb_connect/src/connect/impl/smb1/server_message_block.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';

class SmbComNtCancel extends ServerMessageBlock {
  SmbComNtCancel(super.config, int mid)
      : super(command: SmbComConstants.SMB_COM_NT_CANCEL) {
    setMid(mid);
  }

  @override
  int writeParameterWordsWireFormat(Uint8List dst, int dstIndex) {
    return 0;
  }

  @override
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    return 0;
  }

  @override
  int readParameterWordsWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }

  @override
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }
}
