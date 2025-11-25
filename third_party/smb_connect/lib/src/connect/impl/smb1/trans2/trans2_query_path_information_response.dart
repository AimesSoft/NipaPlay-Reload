import 'dart:typed_data';

import 'package:smb_connect/src/connect/fscc/file_basic_info.dart';
import 'package:smb_connect/src/connect/fscc/file_information.dart';
import 'package:smb_connect/src/connect/fscc/file_standard_info.dart';
import 'package:smb_connect/src/connect/impl/smb1/trans/smb_com_transaction.dart';
import 'package:smb_connect/src/connect/impl/smb1/trans/smb_com_transaction_response.dart';
import 'package:smb_connect/src/utils/base.dart';

import '../../../fscc/file_internal_info.dart';

class Trans2QueryPathInformationResponse extends SmbComTransactionResponse {
  final int informationLevel;
  FileInformation? _info;

  Trans2QueryPathInformationResponse(super.config, this.informationLevel)
      : super(subCommand: SmbComTransaction.TRANS2_QUERY_PATH_INFORMATION);

  FileInformation? getInfo() {
    return _info;
  }

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
    // observed two zero ints here with at least win98
    return 2;
  }

  @override
  @protected
  int readDataWireFormat(Uint8List buffer, int bufferIndex, int len) {
    int start = bufferIndex;
    FileInformation? inf = _createFileInformation();
    if (inf != null) {
      bufferIndex += inf.decode(buffer, bufferIndex, dataCount);
      _info = inf;
    }
    return bufferIndex - start;
  }

  FileInformation? _createFileInformation() {
    FileInformation inf;
    switch (informationLevel) {
      case FileInformation.FILE_BASIC_INFO:
        inf = FileBasicInfo();
        break;
      case FileInformation.FILE_STANDARD_INFO:
        inf = FileStandardInfo();
        break;
      case FileInformation.FILE_INTERNAL_INFO:
        inf = FileInternalInfo();
        break;
      default:
        return null;
    }
    return inf;
  }

  @override
  String toString() {
    return "Trans2QueryPathInformationResponse[${super.toString()}]";
  }
}
