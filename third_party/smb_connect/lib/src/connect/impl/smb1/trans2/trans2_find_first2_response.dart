import 'dart:typed_data';

import 'package:smb_connect/src/connect/fscc/file_both_directory_info.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/connect/impl/smb1/trans/smb_com_transaction.dart';
import 'package:smb_connect/src/connect/impl/smb1/trans/smb_com_transaction_response.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/base.dart';

class Trans2FindFirst2Response extends SmbComTransactionResponse {
  int _sid = 0;
  bool _isEndOfSearch = false;
  int _eaErrorOffset = 0;
  int _lastNameOffset = 0, _lastNameBufferIndex = 0;
  String? _lastName;
  int _resumeKey = 0;

  Trans2FindFirst2Response(super.config)
      : super(
            command: SmbComConstants.SMB_COM_TRANSACTION2,
            subCommand: SmbComTransaction.TRANS2_FIND_FIRST2);

  int getSid() {
    return _sid;
  }

  bool isEndOfSearch() {
    return _isEndOfSearch;
  }

  String? getLastName() {
    return _lastName;
  }

  int getResumeKey() {
    return _resumeKey;
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
    int start = bufferIndex;

    if (subCommand == SmbComTransaction.TRANS2_FIND_FIRST2) {
      _sid = SMBUtil.readInt2(buffer, bufferIndex);
      bufferIndex += 2;
    }
    numEntries = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;
    _isEndOfSearch = (buffer[bufferIndex] & 0x01) == 0x01 ? true : false;
    bufferIndex += 2;
    _eaErrorOffset = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;
    _lastNameOffset = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;

    return bufferIndex - start;
  }

  @override
  @protected
  int readDataWireFormat(Uint8List buffer, int bufferIndex, int len) {
    FileBothDirectoryInfo e;

    _lastNameBufferIndex = bufferIndex + _lastNameOffset;

    List<FileBothDirectoryInfo> results =
        []; //FileBothDirectoryInfo[getNumEntries()];
    for (int i = 0; i < numEntries; i++) {
      e = FileBothDirectoryInfo(config, isUseUnicode());
      results.add(e);

      e.decode(buffer, bufferIndex, len);

      /// lastNameOffset ends up pointing to either to
      /// the exact location of the filename(e.g. Win98)
      /// or to the start of the entry containing the
      /// filename(e.g. NT). Ahhrg! In either case the
      /// lastNameOffset falls between the start of the
      /// entry and the next entry.
      if (_lastNameBufferIndex >= bufferIndex &&
          (e.getNextEntryOffset() == 0 ||
              _lastNameBufferIndex < (bufferIndex + e.getNextEntryOffset()))) {
        _lastName = e.getFilename();
        _resumeKey = e.getFileIndex();
      }

      bufferIndex += e.getNextEntryOffset();
    }

    this.results = results;

    /// last nextEntryOffset for NT 4(but not 98) is 0 so we must
    /// use dataCount or our accounting will report an error for NT :~(
    return dataCount;
  }

  @override
  String toString() {
    String c;
    if (subCommand == SmbComTransaction.TRANS2_FIND_FIRST2) {
      c = "Trans2FindFirst2Response[";
    } else {
      c = "Trans2FindNext2Response[";
    }
    return "$c${super.toString()},sid=$_sid,searchCount=$numEntries,isEndOfSearch=$_isEndOfSearch,eaErrorOffset=$_eaErrorOffset,lastNameOffset=$_lastNameOffset,lastName=$_lastName]";
  }
}
