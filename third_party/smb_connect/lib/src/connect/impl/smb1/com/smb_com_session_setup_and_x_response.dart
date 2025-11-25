import 'dart:typed_data';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/connect/impl/smb1/and_x_server_message_block.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/extensions.dart';

class SmbComSessionSetupAndXResponse extends AndXServerMessageBlock {
  String nativeOs = "";
  String nativeLanMan = "";
  String primaryDomain = "";

  bool isLoggedInAsGuest = false;
  Uint8List? blob;

  SmbComSessionSetupAndXResponse(super.config, {super.andx});

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
    int start = bufferIndex;
    isLoggedInAsGuest = (buffer[bufferIndex] & 0x01) == 0x01 ? true : false;
    bufferIndex += 2;
    if (isExtendedSecurity()) {
      int blobLength = SMBUtil.readInt2(buffer, bufferIndex);
      bufferIndex += 2;
      blob = Uint8List(blobLength);
    }
    return bufferIndex - start;
  }

  @override
  @protected
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    int start = bufferIndex;

    if (isExtendedSecurity()) {
      byteArrayCopy(
          src: buffer,
          srcOffset: bufferIndex,
          dst: blob!,
          dstOffset: 0,
          length: blob!.length);
      bufferIndex += blob!.length;
    }

    nativeOs = readString(buffer, bufferIndex);
    bufferIndex += stringWireLength(nativeOs, bufferIndex);
    nativeLanMan = readString5(
        buffer, bufferIndex, start + byteCount, 255, isUseUnicode());
    bufferIndex += stringWireLength(nativeLanMan, bufferIndex);
    if (!isExtendedSecurity()) {
      primaryDomain = readString5(
          buffer, bufferIndex, start + byteCount, 255, isUseUnicode());
      bufferIndex += stringWireLength(primaryDomain, bufferIndex);
    }

    return bufferIndex - start;
  }

  @override
  String toString() {
    return "SmbComSessionSetupAndXResponse[${super.toString()},isLoggedInAsGuest=$isLoggedInAsGuest,nativeOs=$nativeOs,nativeLanMan=$nativeLanMan,primaryDomain=$primaryDomain]";
  }
}
