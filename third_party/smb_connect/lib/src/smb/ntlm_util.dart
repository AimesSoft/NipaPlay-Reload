import 'dart:typed_data';

import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/crypto/crypto.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/extensions.dart';
import 'package:smb_connect/src/utils/strings.dart';

import '../utils/encdec.dart';

/// @author mbechler
class NtlmUtil {
  /// the calculated response
  static Uint8List getNTLMv2Response(
      Uint8List responseKeyNT,
      Uint8List serverChallenge,
      Uint8List clientChallenge,
      int nanos1601,
      Uint8List? avPairs) {
    int avPairsLength = avPairs != null ? avPairs.length : 0;
    Uint8List temp = Uint8List(28 + avPairsLength + 4);

    Encdec.encUint32LE(0x00000101, temp, 0); // Header
    Encdec.encUint32LE(0x00000000, temp, 4); // Reserved
    Encdec.encUint64LE(nanos1601, temp, 8);
    byteArrayCopy(
        src: clientChallenge,
        srcOffset: 0,
        dst: temp,
        dstOffset: 16,
        length: 8);
    Encdec.encUint32LE(0x00000000, temp, 24); // Unknown
    if (avPairs != null) {
      byteArrayCopy(
          src: avPairs,
          srcOffset: 0,
          dst: temp,
          dstOffset: 28,
          length: avPairsLength);
    }
    Encdec.encUint32LE(0x00000000, temp, 28 + avPairsLength); // mystery bytes!

    return NtlmUtil.computeResponse(
        responseKeyNT, serverChallenge, temp, 0, temp.length);
  }

  /// the calculated response
  static Uint8List getLMv2ResponseBuff(Uint8List responseKeyLM,
      Uint8List serverChallenge, Uint8List clientChallenge) {
    return NtlmUtil.computeResponse(responseKeyLM, serverChallenge,
        clientChallenge, 0, clientChallenge.length);
  }

  static Uint8List computeResponse(Uint8List responseKey,
      Uint8List serverChallenge, Uint8List clientData, int offset, int length) {
    MessageDigest hmac = Crypto.getHMACT64(responseKey);
    hmac.updateBuff(serverChallenge);
    hmac.update(clientData, offset, length);
    Uint8List mac = hmac.digest();
    Uint8List ret = Uint8List(mac.length + clientData.length);
    byteArrayCopy(
        src: mac, srcOffset: 0, dst: ret, dstOffset: 0, length: mac.length);
    byteArrayCopy(
        src: clientData,
        srcOffset: 0,
        dst: ret,
        dstOffset: mac.length,
        length: clientData.length);
    return ret;
  }

  /// the caclulated mac
  static Uint8List nTOWFv2Pass(
      String domain, String username, String password) {
    return nTOWFv2Hash(domain, username, getNTHash(password));
  }

  /// NT password hash
  /// the caclulated mac
  static Uint8List nTOWFv2Hash(
      String domain, String username, Uint8List passwordHash) {
    MessageDigest hmac = Crypto.getHMACT64(passwordHash);
    hmac.updateBuff(username.toUpperCase().getUNIBytes());
    hmac.updateBuff(domain.getUNIBytes());
    return hmac.digest();
  }

  /// nt password hash
  static Uint8List getNTHash(String password) {
    MessageDigest md4 = Crypto.getMD4();
    md4.updateBuff(password.getUNIBytes());
    return md4.digest();
  }

  /// the calculated hash
  static Uint8List nTOWFv1(String password) {
    return getNTHash(password);
  }

  /// the calculated response
  static Uint8List getNTLM2Response(Uint8List passwordHash,
      Uint8List serverChallenge, Uint8List clientChallenge) {
    Uint8List sessionHash = Uint8List(8);

    MessageDigest md5 = Crypto.getMD5();
    md5.updateBuff(serverChallenge);
    md5.update(clientChallenge, 0, 8);
    byteArrayCopy(
        src: md5.digest(),
        srcOffset: 0,
        dst: sessionHash,
        dstOffset: 0,
        length: 8);

    Uint8List key = Uint8List(21);
    byteArrayCopy(
        src: passwordHash, srcOffset: 0, dst: key, dstOffset: 0, length: 16);
    Uint8List ntResponse = Uint8List(24);
    NtlmUtil.E(key, sessionHash, ntResponse);
    return ntResponse;
  }

  /// Creates the LMv2 response for the supplied information.
  static Uint8List getLMv2ResponsePass(String domain, String user,
      String password, Uint8List challenge, Uint8List clientChallenge) {
    return getLMv2ResponseHash(
        domain, user, getNTHash(password), challenge, clientChallenge);
  }

  /// Creates the LMv2 response for the supplied information.
  static Uint8List getLMv2ResponseHash(String domain, String user,
      Uint8List passwordHash, Uint8List challenge, Uint8List clientChallenge) {
    Uint8List response = Uint8List(24);
    MessageDigest hmac = Crypto.getHMACT64(passwordHash);
    hmac.updateBuff(user.toUpperCase().getUNIBytes());
    hmac.updateBuff(domain.toUpperCase().getUNIBytes());
    hmac = Crypto.getHMACT64(hmac.digest());
    hmac.updateBuff(challenge);
    hmac.updateBuff(clientChallenge);
    hmac.digestTo(response, 0, 16);

    byteArrayCopy(
        src: clientChallenge,
        srcOffset: 0,
        dst: response,
        dstOffset: 16,
        length: 8);
    return response;
  }

  /// Generate the Unicode MD4 hash for the password associated with these credentials.
  /// the calculated response
  static Uint8List getNTLMResponsePass(String password, Uint8List challenge) {
    return getNTLMResponseHash(getNTHash(password), challenge);
  }

  /// Generate the Unicode MD4 hash for the password associated with these credentials.
  /// the calculated response
  static Uint8List getNTLMResponseHash(
      Uint8List passwordHash, Uint8List challenge) {
    Uint8List p21 = Uint8List(21);
    Uint8List p24 = Uint8List(24);
    byteArrayCopy(
        src: passwordHash, srcOffset: 0, dst: p21, dstOffset: 0, length: 16);
    NtlmUtil.E(p21, challenge, p24);
    return p24;
  }

  /// Generate the ANSI DES hash for the password associated with these credentials.
  static Uint8List getPreNTLMResponse(
      Configuration config, String password, Uint8List challenge) {
    Uint8List p14 = Uint8List(14);
    Uint8List p21 = Uint8List(21);
    Uint8List p24 = Uint8List(24);
    Uint8List passwordBytes = password.getOEMBytes(config);
    int passwordLength = passwordBytes.length;

    // Only encrypt the first 14 bytes of the password for Pre 0.12 NT LM
    if (passwordLength > 14) {
      passwordLength = 14;
    }
    byteArrayCopy(
        src: passwordBytes,
        srcOffset: 0,
        dst: p14,
        dstOffset: 0,
        length: passwordLength);
    NtlmUtil.E(p14, NtlmUtil.S8, p21);
    NtlmUtil.E(p21, challenge, p24);
    return p24;
  }

  // KGS!@#$%
  static final Uint8List S8 =
      Uint8List.fromList([0x4b, 0x47, 0x53, 0x21, 0x40, 0x23, 0x24, 0x25]);

  /// Accepts key multiple of 7
  /// Returns enc multiple of 8
  /// Multiple is the same like: 21 byte key gives 24 byte result
  static void E(Uint8List key, Uint8List data, Uint8List e) {
    Uint8List key7 = Uint8List(7);
    Uint8List e8 = Uint8List(8);

    for (int i = 0; i < key.length / 7; i++) {
      byteArrayCopy(
          src: key, srcOffset: i * 7, dst: key7, dstOffset: 0, length: 7);

      final des = Crypto.getDES(key7);
      des.processBlock(data, 0, e8, 0);
      byteArrayCopy(src: e8, srcOffset: 0, dst: e, dstOffset: i * 8, length: 8);
    }
  }
}
