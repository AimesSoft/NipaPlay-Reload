import 'dart:typed_data';

import 'package:pointycastle/pointycastle.dart';
import 'package:smb_connect/src/crypto/dex/des_cipher_internal.dart';
import 'package:smb_connect/src/crypto/dex/des_crypt.dart';
import 'package:smb_connect/src/crypto/dex/dex_consts.dart';

class DESCypher implements StreamCipher {
  final DESCipherInternal core = DESCipherInternal(DESCrypt(), DES_BLOCK_SIZE);
  @override
  String get algorithmName => "DES";

  @override
  void init(bool forEncryption, CipherParameters? params) {
    core.init(forEncryption, params);
  }

  @override
  Uint8List process(Uint8List data) {
    return core.process(data);
  }

  @override
  void processBytes(
      Uint8List inp, int inpOff, int len, Uint8List out, int outOff) {
    core.processBytes(inp, inpOff, len, out, outOff);
  }

  @override
  void reset() {
    // TODO: implement reset
  }

  @override
  int returnByte(int inp) {
    // TODO: implement returnByte
    throw UnimplementedError();
  }
}
