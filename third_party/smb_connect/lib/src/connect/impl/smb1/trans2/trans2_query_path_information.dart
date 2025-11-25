import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/fscc/file_information.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/connect/impl/smb1/trans/smb_com_transaction.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/strings.dart';

class Trans2QueryPathInformation extends SmbComTransaction {
  final int informationLevel;

  Trans2QueryPathInformation(
      Configuration config, String path, this.informationLevel)
      : super(config, SmbComConstants.SMB_COM_TRANSACTION2,
            subCommand: SmbComTransaction.TRANS2_QUERY_PATH_INFORMATION) {
    this.path = path;
    totalDataCount = 0;
    maxParameterCount = 2;
    maxDataCount = 40;
    maxSetupCount = 0x00;
  }

  @override
  @protected
  int writeSetupWireFormat(Uint8List dst, int dstIndex) {
    dst[dstIndex++] = getSubCommand();
    dst[dstIndex++] = 0x00;
    return 2;
  }

  @override
  @protected
  int writeParametersWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;

    SMBUtil.writeInt2(mapInformationLevel(informationLevel), dst, dstIndex);
    dstIndex += 2;
    dst[dstIndex++] = 0x00;
    dst[dstIndex++] = 0x00;
    dst[dstIndex++] = 0x00;
    dst[dstIndex++] = 0x00;
    dstIndex += writeString(path!, dst, dstIndex);

    return dstIndex - start;
  }

  static int mapInformationLevel(int il) {
    switch (il) {
      case FileInformation.FILE_BASIC_INFO:
        return 0x0101;
      case FileInformation.FILE_STANDARD_INFO:
        return 0x0102;
      case FileInformation.FILE_ENDOFFILE_INFO:
        return 0x0104;
    }
    throw SmbIllegalArgumentException("Unsupported information level $il");
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
    return 0;
  }

  @override
  String toString() {
    return "Trans2QueryPathInformation[${super.toString()},informationLevel=0x${Hexdump.toHexString(informationLevel, 3)},filename=$path]";
  }
}
