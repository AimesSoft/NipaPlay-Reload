import 'dart:typed_data';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/connect/impl/smb1/server_message_block.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/smb_constants.dart';
import 'package:smb_connect/src/utils/strings.dart';

class SmbComDelete extends ServerMessageBlock {
  final int _searchAttributes;

  SmbComDelete(super.config, {super.path})
      : _searchAttributes = SmbConstants.ATTR_HIDDEN | SmbConstants.ATTR_SYSTEM,
        super(command: SmbComConstants.SMB_COM_DELETE);

  @override
  @protected
  int writeParameterWordsWireFormat(Uint8List dst, int dstIndex) {
    SMBUtil.writeInt2(_searchAttributes, dst, dstIndex);
    return 2;
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;

    dst[dstIndex++] = 0x04;
    dstIndex += writeString(path!, dst, dstIndex);

    return dstIndex - start;
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
    return "SmbComDelete[${super.toString()},searchAttributes=0x${Hexdump.toHexString(_searchAttributes, 4)},fileName=$path]";
  }
}
