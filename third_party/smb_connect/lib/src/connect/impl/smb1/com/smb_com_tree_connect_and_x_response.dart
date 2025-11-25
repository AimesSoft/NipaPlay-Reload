import 'dart:typed_data';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/connect/impl/smb1/and_x_server_message_block.dart';
import 'package:smb_connect/src/connect/impl/smb1/server_message_block.dart';
import 'package:smb_connect/src/connect/common/tree_connect_response.dart';
import 'package:smb_connect/src/utils/strings.dart';

class SmbComTreeConnectAndXResponse extends AndXServerMessageBlock
    implements TreeConnectResponse {
  static const int SMB_SUPPORT_SEARCH_BITS = 0x0001;
  static const int SMB_SHARE_IS_IN_DFS = 0x0002;

  bool supportSearchBits = false, shareIsInDfs = false;
  String? service;
  String nativeFileSystem = "";

  SmbComTreeConnectAndXResponse(super.config, ServerMessageBlock? andx)
      : super(andx: andx);

  // @override
  // String? getService() {
  //   return service;
  // }

  String getNativeFileSystem() {
    return nativeFileSystem;
  }

  bool isSupportSearchBits() {
    return supportSearchBits;
  }

  // @override
  // bool isShareDfs() {
  //   return shareIsInDfs;
  // }

  // @override
  // bool isValidTid() {
  //   return getTid() != 0xFFFF;
  // }

  @override
  @protected
  int writeParameterWordsWireFormat(Uint8List dst, int dstIndex) {
    return 0;
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    return 0;
  }

  @override
  @protected
  int readParameterWordsWireFormat(Uint8List buffer, int bufferIndex) {
    supportSearchBits = (buffer[bufferIndex] & SMB_SUPPORT_SEARCH_BITS) ==
        SMB_SUPPORT_SEARCH_BITS;
    shareIsInDfs =
        (buffer[bufferIndex] & SMB_SHARE_IS_IN_DFS) == SMB_SHARE_IS_IN_DFS;
    return 2;
  }

  @override
  @protected
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    int start = bufferIndex;

    int len = readStringLength(buffer, bufferIndex, 32);
    try {
      service = fromASCIIBytes(buffer, bufferIndex, len);
      //String(buffer, bufferIndex, len, "ASCII");
    } catch (uee) {
      //UnsupportedEncodingException
      return 0;
    }
    bufferIndex += len + 1;
    // win98 observed not returning nativeFileSystem
    return bufferIndex - start;
  }

  @override
  String toString() {
    return "SmbComTreeConnectAndXResponse[${super.toString()},supportSearchBits=$supportSearchBits,shareIsInDfs=$shareIsInDfs,service=$service,nativeFileSystem=$nativeFileSystem]";
  }
}
