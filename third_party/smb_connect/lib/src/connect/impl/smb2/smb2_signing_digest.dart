import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_constants.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/extensions.dart';

import '../../common/common_server_message_block.dart';
import '../../common/smb_signing_digest.dart';
import 'smb3_key_derivation.dart';

class Smb2SigningDigest implements SMBSigningDigest {
  static const int SIGNATURE_OFFSET = 48;
  static const int SIGNATURE_LENGTH = 16;
  late final Mac _digest;

  Smb2SigningDigest(
      Uint8List sessionKey, int dialect, Uint8List? preauthIntegrityHash) {
    Mac m;
    Uint8List signingKey;
    switch (dialect) {
      case Smb2Constants.SMB2_DIALECT_0202:
      case Smb2Constants.SMB2_DIALECT_0210:
        m = Mac("SHA-256/HMAC");
        signingKey = sessionKey;
        break;
      case Smb2Constants.SMB2_DIALECT_0300:
      case Smb2Constants.SMB2_DIALECT_0302:
        signingKey = Smb3KeyDerivation.deriveSigningKey(
            dialect, sessionKey, Uint8List(0) /* unimplemented */);
        m = Mac("AES/CMAC");
        break;
      case Smb2Constants.SMB2_DIALECT_0311:
        if (preauthIntegrityHash == null) {
          throw SmbIllegalArgumentException(
              "Missing preauthIntegrityHash for SMB 3.1");
        }
        signingKey = Smb3KeyDerivation.deriveSigningKey(
            dialect, sessionKey, preauthIntegrityHash);
        m = Mac("AES/CMAC");
        break;
      default:
        throw SmbIllegalArgumentException("Unknown dialect");
    }
    m.init(KeyParameter(signingKey));
    _digest = m;
  }

  @override
  void sign(Uint8List data, int offset, int length,
      CommonServerMessageBlock? request, CommonServerMessageBlock? response) {
    _digest.reset();

    // zero out signature field
    int index = offset + SIGNATURE_OFFSET;
    for (int i = 0; i < SIGNATURE_LENGTH; i++) {
      data[index + i] = 0;
    }

    // set signed flag
    int oldFlags = SMBUtil.readInt4(data, offset + 16);
    int flags = oldFlags | Smb2Constants.SMB2_FLAGS_SIGNED;
    SMBUtil.writeInt4(flags, data, offset + 16);

    _digest.update(data, offset, length);

    Uint8List sig = Uint8List(_digest.macSize);
    _digest.doFinal(sig, 0);
    byteArrayCopy(
        src: sig,
        srcOffset: 0,
        dst: data,
        dstOffset: offset + SIGNATURE_OFFSET,
        length: SIGNATURE_LENGTH);
  }

  @override
  bool verify(Uint8List data, int offset, int length, int extraPad,
      CommonServerMessageBlock msg) {
    _digest.reset();

    int flags = SMBUtil.readInt4(data, offset + 16);
    if ((flags & Smb2Constants.SMB2_FLAGS_SIGNED) == 0) {
      // log.error("The server did not sign a message we expected to be signed");
      return true;
    }

    Uint8List sig = Uint8List(SIGNATURE_LENGTH);
    byteArrayCopy(
        src: data,
        srcOffset: offset + SIGNATURE_OFFSET,
        dst: sig,
        dstOffset: 0,
        length: SIGNATURE_LENGTH);

    int index = offset + SIGNATURE_OFFSET;
    for (int i = 0; i < SIGNATURE_LENGTH; i++) {
      data[index + i] = 0;
    }

    _digest.update(data, offset, length);

    Uint8List cmp = Uint8List(SIGNATURE_LENGTH);
    Uint8List sig2 = Uint8List(_digest.macSize);
    _digest.doFinal(sig2, 0);
    byteArrayCopy(
        src: sig2,
        srcOffset: 0,
        dst: cmp,
        dstOffset: 0,
        length: SIGNATURE_LENGTH);
    if (!isEqualMessageDigest(sig, cmp)) {
      return true;
    }
    return false;
  }
}
