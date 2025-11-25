import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/fscc/file_system_information.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/connect/impl/smb1/trans/smb_com_transaction.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/strings.dart';

class Trans2QueryFSInformation extends SmbComTransaction {
  final int _informationLevel;

  Trans2QueryFSInformation(Configuration config, int informationLevel)
      : _informationLevel = informationLevel,
        super(config, SmbComConstants.SMB_COM_TRANSACTION2,
            subCommand: SmbComTransaction.TRANS2_QUERY_FS_INFORMATION) {
    totalParameterCount = 2;
    totalDataCount = 0;
    maxParameterCount = 0;
    maxDataCount = 800;
    maxSetupCount = 0;
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

    SMBUtil.writeInt2(_mapInformationLevel(_informationLevel), dst, dstIndex);
    dstIndex += 2;

    /// windows98 has what appears to be another 4 0's followed by the share
    /// name as a zero terminated ascii string "\TMP" + '\0'
    ///
    /// As is this works, but it deviates from the spec section 4.1.6.6 but
    /// maybe I should put it in. Wonder what NT does?

    return dstIndex - start;
  }

  static int _mapInformationLevel(int il) {
    switch (il) {
      case FileSystemInformation.SMB_INFO_ALLOCATION:
        return 0x1;
      case FileSystemInformation.FS_SIZE_INFO:
        return 0x103;
    }
    throw SmbIllegalArgumentException("Unhandled information level");
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
    return "Trans2QueryFSInformation[${super.toString()},informationLevel=0x${Hexdump.toHexString(_informationLevel, 3)}]";
  }
}
