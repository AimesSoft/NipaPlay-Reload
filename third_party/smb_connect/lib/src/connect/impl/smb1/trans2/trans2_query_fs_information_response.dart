import 'dart:typed_data';

import 'package:smb_connect/src/connect/common/alloc_info.dart';
import 'package:smb_connect/src/connect/fscc/file_fs_full_size_information.dart';
import 'package:smb_connect/src/connect/fscc/file_fs_size_information.dart';
import 'package:smb_connect/src/connect/fscc/file_system_information.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/connect/impl/smb1/trans/smb_com_transaction.dart';
import 'package:smb_connect/src/connect/impl/smb1/trans/smb_com_transaction_response.dart';
import 'package:smb_connect/src/utils/base.dart';

import '../../../fscc/smb_info_allocation.dart';

class Trans2QueryFSInformationResponse extends SmbComTransactionResponse {
  final int _informationLevel;
  FileSystemInformation? _info;

  Trans2QueryFSInformationResponse(super.config, int informationLevel)
      : _informationLevel = informationLevel,
        super(
            command: SmbComConstants.SMB_COM_TRANSACTION2,
            subCommand: SmbComTransaction.TRANS2_QUERY_FS_INFORMATION);

  int getInformationLevel() {
    return _informationLevel;
  }

  FileSystemInformation? getInfo() {
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
    return 0;
  }

  @override
  @protected
  int readDataWireFormat(Uint8List buffer, int bufferIndex, int len) {
    int start = bufferIndex;
    AllocInfo? inf = createInfo();
    if (inf != null) {
      bufferIndex += inf.decode(buffer, bufferIndex, dataCount);
      _info = inf;
    }
    return bufferIndex - start;
  }

  AllocInfo? createInfo() {
    AllocInfo inf;
    switch (_informationLevel) {
      case FileSystemInformation.SMB_INFO_ALLOCATION:
        inf = SmbInfoAllocation();
        break;
      case FileSystemInformation.FS_SIZE_INFO:
        inf = FileFsSizeInformation();
        break;
      case FileSystemInformation.FS_FULL_SIZE_INFO:
        inf = FileFsFullSizeInformation();
        break;
      default:
        return null;
    }
    return inf;
  }

  @override
  String toString() {
    return "Trans2QueryFSInformationResponse[${super.toString()}]";
  }
}
