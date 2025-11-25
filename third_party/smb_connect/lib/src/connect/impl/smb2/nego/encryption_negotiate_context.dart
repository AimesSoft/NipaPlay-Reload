import 'dart:typed_data';

import 'package:smb_connect/src/connect/impl/smb2/nego/negotiate_context_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/nego/negotiate_context_response.dart';
import 'package:smb_connect/src/connect/smb_util.dart';

class EncryptionNegotiateContext
    implements NegotiateContextRequest, NegotiateContextResponse {
  /// Context type
  static const int NEGO_CTX_ENC_TYPE = 0x2;

  /// AES 128 CCM
  static const int CIPHER_AES128_CCM = 0x1;

  /// AES 128 GCM
  static const int CIPHER_AES128_GCM = 0x2;

  List<int>? ciphers;

  EncryptionNegotiateContext({this.ciphers});

  @override
  int getContextType() {
    return NEGO_CTX_ENC_TYPE;
  }

  @override
  int encode(Uint8List dst, int dstIndex) {
    int start = dstIndex;
    SMBUtil.writeInt2(ciphers?.length ?? 0, dst, dstIndex);
    dstIndex += 2;

    if (ciphers != null) {
      for (int cipher in ciphers!) {
        SMBUtil.writeInt2(cipher, dst, dstIndex);
        dstIndex += 2;
      }
    }
    return dstIndex - start;
  }

  @override
  int decode(Uint8List buffer, int bufferIndex, int len) {
    int start = bufferIndex;
    int nciphers = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;

    ciphers = Uint8List(nciphers);
    for (int i = 0; i < nciphers; i++) {
      ciphers![i] = SMBUtil.readInt2(buffer, bufferIndex);
      bufferIndex += 2;
    }

    return bufferIndex - start;
  }

  @override
  int size() {
    return 4 + (ciphers != null ? 2 * ciphers!.length : 0);
  }
}
