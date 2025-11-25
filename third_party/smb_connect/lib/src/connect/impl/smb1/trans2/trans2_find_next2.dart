import 'dart:typed_data';

import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/connect/impl/smb1/trans/smb_com_transaction.dart';
import 'package:smb_connect/src/connect/impl/smb1/trans2/trans2_find_first2.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/strings.dart';

class Trans2FindNext2 extends SmbComTransaction {
  final int _sid, _informationLevel, _tflags, _maxItems;
  int _resumeKey;
  String _filename;

  Trans2FindNext2(Configuration config, this._sid, this._resumeKey,
      this._filename, int batchCount, int batchSize)
      : _informationLevel = Trans2FindFirst2.SMB_FILE_BOTH_DIRECTORY_INFO,
        _tflags = 0x00,
        _maxItems = batchCount,
        super(config, SmbComConstants.SMB_COM_TRANSACTION2,
            subCommand: SmbComTransaction.TRANS2_FIND_NEXT2) {
    maxParameterCount = 8;
    maxDataCount = batchSize;
    maxSetupCount = 0;
  }

  @override
  void reset2(int key, String? lastName) {
    super.reset();
    _resumeKey = key;
    _filename = lastName!;
    flags2 = 0;
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

    SMBUtil.writeInt2(_sid, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt2(_maxItems, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt2(_informationLevel, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt4(_resumeKey, dst, dstIndex);
    dstIndex += 4;
    SMBUtil.writeInt2(_tflags, dst, dstIndex);
    dstIndex += 2;
    dstIndex += writeString(_filename, dst, dstIndex);

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
    return "Trans2FindNext2[${super.toString()},sid=$_sid,searchCount=${config.listSize},informationLevel=0x${Hexdump.toHexString(_informationLevel, 3)},resumeKey=0x${Hexdump.toHexString(_resumeKey, 4)},flags=0x${Hexdump.toHexString(_tflags, 2)},filename=$_filename]";
  }
}
