import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_constants.dart';
import 'package:smb_connect/src/utils/extensions.dart';
import 'package:smb_connect/src/utils/extensions/kdf/kdf_counter_bytes_generator.dart';
import 'package:smb_connect/src/utils/extensions/kdf/kdf_counter_parameters.dart';
import 'package:smb_connect/src/utils/strings.dart';

///
/// SMB3 SP800-108 Counter Mode Key Derivation
///
/// @author mbechler
///
class Smb3KeyDerivation {
  static final Uint8List SIGNCONTEXT_300 = toCBytes("SmbSign");
  static final Uint8List SIGNLABEL_300 = toCBytes("SMB2AESCMAC");
  static final Uint8List SIGNLABEL_311 = toCBytes("SMBSigningKey");

  static final Uint8List APPCONTEXT_300 = toCBytes("SmbRpc");
  static final Uint8List APPLABEL_300 = toCBytes("SMB2APP");
  static final Uint8List APPLABEL_311 = toCBytes("SMBAppKey");

  static final Uint8List ENCCONTEXT_300 =
      toCBytes("ServerIn "); // there really is a space there
  static final Uint8List ENCLABEL_300 = toCBytes("SMB2AESCCM");
  static final Uint8List ENCLABEL_311 = toCBytes("SMB2C2SCipherKey");

  static final Uint8List DECCONTEXT_300 = toCBytes("ServerOut");
  static final Uint8List DECLABEL_300 = toCBytes("SMB2AESCCM");
  static final Uint8List DECLABEL_311 = toCBytes("SMB2S2CCipherKey");

  Smb3KeyDerivation();

  static Uint8List deriveSigningKey(
      int dialect, Uint8List sessionKey, Uint8List preauthIntegrity) {
    return derive(
        sessionKey,
        dialect == Smb2Constants.SMB2_DIALECT_0311
            ? SIGNLABEL_311
            : SIGNLABEL_300,
        dialect == Smb2Constants.SMB2_DIALECT_0311
            ? preauthIntegrity
            : SIGNCONTEXT_300);
  }

  static Uint8List dervieApplicationKey(
      int dialect, Uint8List sessionKey, Uint8List preauthIntegrity) {
    return derive(
        sessionKey,
        dialect == Smb2Constants.SMB2_DIALECT_0311
            ? APPLABEL_311
            : APPLABEL_300,
        dialect == Smb2Constants.SMB2_DIALECT_0311
            ? preauthIntegrity
            : APPCONTEXT_300);
  }

  static Uint8List deriveEncryptionKey(
      int dialect, Uint8List sessionKey, Uint8List preauthIntegrity) {
    return derive(
        sessionKey,
        dialect == Smb2Constants.SMB2_DIALECT_0311
            ? ENCLABEL_311
            : ENCLABEL_300,
        dialect == Smb2Constants.SMB2_DIALECT_0311
            ? preauthIntegrity
            : ENCCONTEXT_300);
  }

  static Uint8List deriveDecryptionKey(
      int dialect, Uint8List sessionKey, Uint8List preauthIntegrity) {
    return derive(
        sessionKey,
        dialect == Smb2Constants.SMB2_DIALECT_0311
            ? DECLABEL_311
            : DECLABEL_300,
        dialect == Smb2Constants.SMB2_DIALECT_0311
            ? preauthIntegrity
            : DECCONTEXT_300);
  }

  static Uint8List derive(
      Uint8List sessionKey, Uint8List label, Uint8List context) {
    // KDFCounterBytesGenerator gen = new KDFCounterBytesGenerator(new HMac(new SHA256Digest()));
    // final gen = KeyDerivator("SHA-256/HMAC/PBKDF2");
    var gen = KDFCounterBytesGenerator(Mac("SHA-256/HMAC"));

    int r = 32;
    Uint8List suffix = Uint8List(label.length + context.length + 5);
    // per bouncycastle
    // <li>1: K(i) := PRF( KI, [i]_2 || Label || 0x00 || Context || [L]_2 ) with the counter at the very beginning
    // of the fixedInputData (The default implementation has this format)</li>
    // with the parameters
    // <li>1. KDFCounterParameters(ki, null, "Label || 0x00 || Context || [L]_2]", 8);

    // all fixed inputs go into the suffix:
    // + label
    byteArrayCopy(
        src: label,
        srcOffset: 0,
        dst: suffix,
        dstOffset: 0,
        length: label.length);
    // + 1 byte 0x00
    // + context
    byteArrayCopy(
        src: context,
        srcOffset: 0,
        dst: suffix,
        dstOffset: label.length + 1,
        length: context.length);
    // + 4 byte (== r bits) big endian encoding of L
    suffix[suffix.length - 1] = 128;

    var param = KDFCounterParameters(sessionKey, null, suffix, r);
    gen.init(param);

    Uint8List derived = Uint8List(16);
    gen.generateBytes(derived, 0, 16);
    return derived;
  }

  static Uint8List toCBytes(String string) {
    Uint8List data = Uint8List(string.length + 1);
    byteArrayCopy(
        src: string.getASCIIBytes(),
        srcOffset: 0,
        dst: data,
        dstOffset: 0,
        length: string.length);
    return data;
  }
}
