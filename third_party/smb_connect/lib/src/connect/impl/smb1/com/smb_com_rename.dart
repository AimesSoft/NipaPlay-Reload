import 'dart:typed_data';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/connect/impl/smb1/server_message_block.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/smb_constants.dart';
import 'package:smb_connect/src/utils/strings.dart';

class SmbComRename extends ServerMessageBlock {
  int searchAttributes = 0;
  String oldFileName;
  String newFileName;

  SmbComRename(super.config, this.oldFileName, this.newFileName)
      : super(command: SmbComConstants.SMB_COM_RENAME) {
    searchAttributes = SmbConstants.ATTR_HIDDEN |
        SmbConstants.ATTR_SYSTEM |
        SmbConstants.ATTR_DIRECTORY;
  }

  @override
  @protected
  int writeParameterWordsWireFormat(Uint8List dst, int dstIndex) {
    SMBUtil.writeInt2(searchAttributes, dst, dstIndex);
    return 2;
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;

    dst[dstIndex++] = 0x04;
    dstIndex += writeString(oldFileName, dst, dstIndex);
    dst[dstIndex++] = 0x04;
    if (isUseUnicode()) {
      dst[dstIndex++] = 0; //'\0';
    }
    dstIndex += writeString(newFileName, dst, dstIndex);

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
    return "SmbComRename[${super.toString()},searchAttributes=0x${Hexdump.toHexString(searchAttributes, 4)},oldFileName=$oldFileName,newFileName=$newFileName]";
  }
}
