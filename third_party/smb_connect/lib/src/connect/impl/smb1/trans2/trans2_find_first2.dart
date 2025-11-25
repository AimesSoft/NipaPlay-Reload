import 'dart:typed_data';

import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/connect/impl/smb1/trans/smb_com_transaction.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/strings.dart';

class Trans2FindFirst2 extends SmbComTransaction {
  // flags

  static const int FLAGS_CLOSE_AFTER_THIS_REQUEST = 0x01;
  static const int FLAGS_CLOSE_IF_END_REACHED = 0x02;
  static const int FLAGS_RETURN_RESUME_KEYS = 0x04;
  static const int FLAGS_RESUME_FROM_PREVIOUS_END = 0x08;
  static const int FLAGS_FIND_WITH_BACKUP_INTENT = 0x10;

  int _searchAttributes = 0;
  int _tflags = 0;
  int _informationLevel = 0;
  final int _searchStorageType = 0;
  int _maxItems = 0;
  String? _wildcard;

  // information levels

  static const int SMB_INFO_STANDARD = 1;
  static const int SMB_INFO_QUERY_EA_SIZE = 2;
  static const int SMB_INFO_QUERY_EAS_FROM_LIST = 3;
  static const int SMB_FIND_FILE_DIRECTORY_INFO = 0x101;
  static const int SMB_FIND_FILE_FULL_DIRECTORY_INFO = 0x102;
  static const int SMB_FILE_NAMES_INFO = 0x103;
  static const int SMB_FILE_BOTH_DIRECTORY_INFO = 0x104;

  Trans2FindFirst2(
    Configuration config,
    String filename,
    String wildcard,
    int searchAttributes,
    int batchCount,
    int batchSize,
  ) : super(config, SmbComConstants.SMB_COM_TRANSACTION2,
            subCommand: SmbComTransaction.TRANS2_FIND_FIRST2) {
    if (filename == "\\") {
      path = filename;
    } else if (filename[filename.length - 1] != "\\") {
      path = "$filename\\";
    } else {
      path = filename;
    }
    _wildcard = wildcard;
    _searchAttributes = searchAttributes & 0x37; /* generally ignored tho */

    _tflags = 0x00;
    _informationLevel = SMB_FILE_BOTH_DIRECTORY_INFO;

    totalDataCount = 0;
    maxParameterCount = 10;
    _maxItems = batchCount;
    maxDataCount = batchSize;
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

    SMBUtil.writeInt2(_searchAttributes, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt2(_maxItems, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt2(_tflags, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt2(_informationLevel, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt4(_searchStorageType, dst, dstIndex);
    dstIndex += 4;
    dstIndex += writeString(path! + _wildcard!, dst, dstIndex);

    return dstIndex - start;
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
    return "Trans2FindFirst2[${super.toString()},searchAttributes=0x${Hexdump.toHexString(_searchAttributes, 2)},searchCount=$_maxItems,flags=0x${Hexdump.toHexString(_tflags, 2)},informationLevel=0x${Hexdump.toHexString(_informationLevel, 3)},searchStorageType=$_searchStorageType,filename=$path]";
  }
}
