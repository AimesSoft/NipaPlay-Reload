import 'dart:typed_data';

import 'package:smb_connect/src/connect/impl/smb2/nego/negotiate_context_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/nego/negotiate_context_response.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/extensions.dart';

class PreauthIntegrityNegotiateContext
    implements NegotiateContextRequest, NegotiateContextResponse {
  /// Context type
  static const int NEGO_CTX_PREAUTH_TYPE = 0x1;

  /// SHA-512
  static const int HASH_ALGO_SHA512 = 0x1;

  List<int>? hashAlgos;
  Uint8List? salt;

  PreauthIntegrityNegotiateContext({this.hashAlgos, this.salt});

  @override
  int getContextType() {
    return NEGO_CTX_PREAUTH_TYPE;
  }

  @override
  int encode(Uint8List dst, int dstIndex) {
    int start = dstIndex;

    SMBUtil.writeInt2(hashAlgos?.length ?? 0, dst, dstIndex);
    SMBUtil.writeInt2(salt?.length ?? 0, dst, dstIndex + 2);
    dstIndex += 4;

    if (hashAlgos != null) {
      for (int hashAlgo in hashAlgos!) {
        SMBUtil.writeInt2(hashAlgo, dst, dstIndex);
        dstIndex += 2;
      }
    }

    if (salt != null) {
      byteArrayCopy(
          src: salt!,
          srcOffset: 0,
          dst: dst,
          dstOffset: dstIndex,
          length: salt!.length);
      dstIndex += salt!.length;
    }

    return dstIndex - start;
  }

  @override
  int decode(Uint8List buffer, int bufferIndex, int len) {
    int start = bufferIndex;
    int nalgos = SMBUtil.readInt2(buffer, bufferIndex);
    int nsalt = SMBUtil.readInt2(buffer, bufferIndex + 2);
    bufferIndex += 4;

    hashAlgos = [];
    for (int i = 0; i < nalgos; i++) {
      hashAlgos!.add(SMBUtil.readInt2(buffer, bufferIndex));
      bufferIndex += 2;
    }

    salt = Uint8List(nsalt);
    byteArrayCopy(
        src: buffer,
        srcOffset: bufferIndex,
        dst: salt!,
        dstOffset: 0,
        length: nsalt);
    bufferIndex += nsalt;

    return bufferIndex - start;
  }

  @override
  int size() {
    return 4 +
        (hashAlgos != null ? 2 * hashAlgos!.length : 0) +
        (salt?.length ?? 0);
  }
}
