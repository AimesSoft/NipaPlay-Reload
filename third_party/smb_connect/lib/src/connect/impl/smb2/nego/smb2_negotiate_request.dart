import 'dart:typed_data';

import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/dialect_version.dart';
import 'package:smb_connect/src/connect/impl/smb2/nego/smb2_negotiate_response.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_constants.dart';
import 'package:smb_connect/src/connect/common/smb_negotiation_request.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/extensions.dart';

import 'encryption_negotiate_context.dart';
import 'negotiate_context_request.dart';
import 'preauth_integrity_negotiate_context.dart';

class Smb2NegotiateRequest
    extends ServerMessageBlock2Request<Smb2NegotiateResponse>
    implements SmbNegotiationRequest {
  late final List<int> dialects;
  int capabilities = 0;
  final Uint8List clientGuid = Uint8List(16);
  final int securityMode;
  final List<NegotiateContextRequest> negotiateContexts = [];
  late final Uint8List? preauthSalt;

  Smb2NegotiateRequest(super.config, this.securityMode) {
    if (!Configuration.isDfsDisabled) {
      capabilities |= Smb2Constants.SMB2_GLOBAL_CAP_DFS;
    }

    if (Configuration.isEncryptionEnabled &&
        // config.getMaximumVersion() != null &&
        config.maximumVersion.atLeast(DialectVersion.SMB300)) {
      capabilities |= Smb2Constants.SMB2_GLOBAL_CAP_ENCRYPTION;
    }

    Set<DialectVersion> dvs = DialectVersion.range(
        DialectVersion.max(DialectVersion.SMB202, config.minimumVersion),
        config.maximumVersion);

    dialects = dvs.map((e) => e.getDialect()).toList();

    if (config.maximumVersion.atLeast(DialectVersion.SMB210)) {
      byteArrayCopy(
          src: config.machineId,
          srcOffset: 0,
          dst: clientGuid,
          dstOffset: 0,
          length: clientGuid.length);
    }

    if ( //config.getMaximumVersion() != null &&
        config.maximumVersion.atLeast(DialectVersion.SMB311)) {
      Uint8List salt = config.random.nextBytes(32);
      negotiateContexts.add(PreauthIntegrityNegotiateContext(
          hashAlgos: [PreauthIntegrityNegotiateContext.HASH_ALGO_SHA512],
          salt: salt));
      preauthSalt = salt;

      if (Configuration.isEncryptionEnabled) {
        negotiateContexts.add(EncryptionNegotiateContext(ciphers: [
          EncryptionNegotiateContext.CIPHER_AES128_GCM,
          EncryptionNegotiateContext.CIPHER_AES128_CCM
        ]));
      }
    }
  }

  @override
  bool isSigningEnforced() {
    return (securityMode & Smb2Constants.SMB2_NEGOTIATE_SIGNING_REQUIRED) != 0;
  }

  @override
  @protected
  Smb2NegotiateResponse createResponse(Configuration config,
      ServerMessageBlock2Request<Smb2NegotiateResponse> req) {
    return Smb2NegotiateResponse(config);
  }

  @override
  int size() {
    int size = Smb2Constants.SMB2_HEADER_LENGTH +
        36 +
        ServerMessageBlock2.size8(2 * dialects.length, align: 4);
    // if (_negotiateContexts != null) {
    for (NegotiateContextRequest ncr in negotiateContexts) {
      size += 8 + ServerMessageBlock2.size8(ncr.size());
    }
    // }
    return ServerMessageBlock2.size8(size);
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;
    SMBUtil.writeInt2(36, dst, dstIndex);
    SMBUtil.writeInt2(dialects.length, dst, dstIndex + 2);
    dstIndex += 4;

    SMBUtil.writeInt2(securityMode, dst, dstIndex);
    SMBUtil.writeInt2(0, dst, dstIndex + 2); // Reserved
    dstIndex += 4;

    SMBUtil.writeInt4(capabilities, dst, dstIndex);
    dstIndex += 4;

    byteArrayCopy(
        src: clientGuid,
        srcOffset: 0,
        dst: dst,
        dstOffset: dstIndex,
        length: 16);
    dstIndex += 16;

    // if SMB 3.11 support negotiateContextOffset/negotiateContextCount
    int negotitateContextOffsetOffset = 0;
    if (negotiateContexts.isEmpty) {
      SMBUtil.writeInt8(0, dst, dstIndex);
    } else {
      negotitateContextOffsetOffset = dstIndex;
      SMBUtil.writeInt2(negotiateContexts.length, dst, dstIndex + 4);
      SMBUtil.writeInt2(0, dst, dstIndex + 6);
    }
    dstIndex += 8;

    for (int dialect in dialects) {
      SMBUtil.writeInt2(dialect, dst, dstIndex);
      dstIndex += 2;
    }

    dstIndex += pad8(dstIndex);

    if (negotiateContexts.isNotEmpty) {
      SMBUtil.writeInt4(
          dstIndex - getHeaderStart(), dst, negotitateContextOffsetOffset);
      for (NegotiateContextRequest nc in negotiateContexts) {
        SMBUtil.writeInt2(nc.getContextType(), dst, dstIndex);
        int lenOffset = dstIndex + 2;
        dstIndex += 4;
        SMBUtil.writeInt4(0, dst, dstIndex);
        dstIndex += 4; // Reserved
        int dataLen = ServerMessageBlock2.size8(nc.encode(dst, dstIndex));
        SMBUtil.writeInt2(dataLen, dst, lenOffset);
        dstIndex += dataLen;
      }
    }
    return dstIndex - start;
  }

  @override
  @protected
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }
}
