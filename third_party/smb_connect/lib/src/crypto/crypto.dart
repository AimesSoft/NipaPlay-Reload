import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:smb_connect/src/crypto/dex/des_crypt.dart';
import 'package:smb_connect/src/crypto/hmact64.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/extensions.dart';

class Crypto {
  static MessageDigest getMD4() {
    return MD4Digest();
  }

  static MessageDigest getMD5() {
    return MD5Digest();
  }

  static MessageDigest getSHA512() {
    return SHA512Digest();
  }

  static MessageDigest getHMACT64(List<int> key) {
    return HMACT64(key);
  }

  static StreamCipher getArcfour(List<int> key) {
    final c = RC4Engine();
    c.init(true, KeyParameter(key.toUint8List()));
    return c;
  }

  static BlockCipher getDES(List<int> key) {
    if (key.length == 7) {
      return getDES(des7to8(key));
    }
    var c = DESCrypt();
    c.init(true, KeyParameter(key.toUint8List()));
    return c;
  }

  static Uint8List des7to8(List<int> key) {
    Uint8List key8 = Uint8List(8);
    // byte key8[] = new byte[8];
    key8[0] = key[0] & 0xFE;
    key8[1] = (key[0] << 7) | ((key[1] & 0xFF) >>> 1);
    key8[2] = (key[1] << 6) | ((key[2] & 0xFF) >>> 2);
    key8[3] = (key[2] << 5) | ((key[3] & 0xFF) >>> 3);
    key8[4] = (key[3] << 4) | ((key[4] & 0xFF) >>> 4);
    key8[5] = (key[4] << 3) | ((key[5] & 0xFF) >>> 5);
    key8[6] = (key[5] << 2) | ((key[6] & 0xFF) >>> 6);
    key8[7] = key[6] << 1;
    for (int i = 0; i < key8.length; i++) {
      key8[i] ^= bitCount(key8[i] ^ 1) & 1;
    }
    return key8;
  }
}
