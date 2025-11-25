import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

///
/// This is an implementation of the HMACT64 keyed hashing algorithm.
/// HMACT64 is defined by Luke Leighton as a modified HMAC-MD5 (RFC 2104)
/// in which the key is truncated at 64 bytes (rather than being hashed
/// via MD5).
class HMACT64 implements Digest {
  static const int BLOCK_LENGTH = 64;

  static const int IPAD = 0x36;

  static const int OPAD = 0x5c;

  late Digest md5;

  Uint8List ipad = Uint8List(BLOCK_LENGTH);

  Uint8List opad = Uint8List(BLOCK_LENGTH);

  @override
  String get algorithmName => "HMACT64";
  @override
  int get digestSize => md5.digestSize;

  @override
  int get byteLength => BLOCK_LENGTH;

  /// Creates an HMACT64 instance which uses the given secret key material.
  HMACT64(List<int> key) {
    int length = min(key.length, BLOCK_LENGTH);

    for (int i = 0; i < length; i++) {
      ipad[i] = (key[i] ^ IPAD);
      opad[i] = (key[i] ^ OPAD);
    }
    for (int i = length; i < BLOCK_LENGTH; i++) {
      ipad[i] = IPAD;
      opad[i] = OPAD;
    }

    md5 = MD5Digest();
    reset();
  }

  @override
  Uint8List process(Uint8List data) {
    update(data, 0, data.length);
    var out = Uint8List(digestSize);
    var len = doFinal(out, 0);
    return out.sublist(0, len);
  }

  @override
  int doFinal(Uint8List out, int outOff) {
    var digest = md5.process(Uint8List(0));
    // int res = md5.doFinal(out, outOff);
    md5.update(opad, 0, opad.length);
    md5.update(digest, 0, digest.length);
    return md5.doFinal(out, outOff);
  }

  @override
  void reset() {
    md5.reset();
    md5.update(ipad, 0, ipad.length);
  }

  @override
  void updateByte(int inp) {
    md5.updateByte(inp);
  }

  @override
  void update(Uint8List inp, int inpOff, int len) {
    md5.update(inp, inpOff, len);
  }
}
