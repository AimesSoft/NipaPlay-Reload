import 'dart:math';
import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/dialect_version.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_response.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_constants.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/connect/transport/response.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/extensions.dart';
import 'package:smb_connect/src/utils/strings.dart';

import '../../../common/smb_negotiation_request.dart';
import '../../../common/smb_negotiation_response.dart';
import '../io/smb2_read_response.dart';
import '../io/smb2_write_request.dart';
import 'encryption_negotiate_context.dart';
import 'negotiate_context_request.dart';
import 'negotiate_context_response.dart';
import 'preauth_integrity_negotiate_context.dart';
import 'smb2_negotiate_request.dart';

class Smb2NegotiateResponse extends ServerMessageBlock2Response
    implements SmbNegotiationResponse {
  int securityMode = 0;
  int dialectRevision = 0;
  final Uint8List _serverGuid = Uint8List(16);
  int capabilities = 0;
  int commonCapabilities = 0;
  int maxTransactSize = 0;
  int maxReadSize = 0;
  int maxWriteSize = 0;
  int systemTime = 0;
  int serverStartTime = 0;
  List<NegotiateContextResponse?>? _negotiateContexts;
  Uint8List? securityBuffer;
  DialectVersion? selectedDialect;

  bool supportsEncryption = false;
  int selectedCipher = -1;
  int selectedPreauthHash = -1;

  Smb2NegotiateResponse(super.config);

  @override
  int getInitialCredits() {
    return credit;
  }

  @override
  DialectVersion? getSelectedDialect() {
    return selectedDialect;
  }

  @override
  int getTransactionBufferSize() {
    return maxTransactSize;
  }

  @override
  bool haveCapabilitiy(int cap) {
    return (commonCapabilities & cap) == cap;
  }

  // @override
  // bool isDFSSupported() {
  //   return !config.isDfsDisabled() &&
  //       haveCapabilitiy(Smb2Constants.SMB2_GLOBAL_CAP_DFS);
  // }

  @override
  bool isValid(SmbNegotiationRequest req) {
    if (!isReceived() || getStatus() != 0) {
      return false;
    }

    if (req.isSigningEnforced() && !isSigningEnabled()) {
      // log.error("Signing is enforced but server does not allow it");
      return false;
    }

    if (dialectRevision == Smb2Constants.SMB2_DIALECT_ANY) {
      // log.error("Server returned ANY dialect");
      return false;
    }

    Smb2NegotiateRequest r = req as Smb2NegotiateRequest;

    DialectVersion? selected;
    for (DialectVersion dv in DialectVersion.values) {
      if (!dv.isSMB2()) {
        continue;
      }
      if (dv.getDialect() == dialectRevision) {
        selected = dv;
      }
    }

    if (selected == null) {
      // log.error("Server returned an unknown dialect");
      return false;
    }

    if (!selected.atLeast(config.minimumVersion) ||
        !selected.atMost(config.maximumVersion)) {
      return false;
    }
    selectedDialect = selected;

    // Filter out unsupported capabilities
    commonCapabilities = r.capabilities & capabilities;

    if ((commonCapabilities & Smb2Constants.SMB2_GLOBAL_CAP_ENCRYPTION) != 0) {
      supportsEncryption = Configuration.isEncryptionEnabled;
    }

    if (selectedDialect?.atLeast(DialectVersion.SMB311) == true) {
      if (!checkNegotiateContexts(r, commonCapabilities)) {
        return false;
      }
    }

    int maxBufferSize = config.transactionBufferSize;
    maxReadSize = min(maxBufferSize - Smb2ReadResponse.OVERHEAD,
            min(config.receiveBufferSize, maxReadSize)) &
        ~0x7;
    maxWriteSize = min(maxBufferSize - Smb2WriteRequest.OVERHEAD,
            min(config.sendBufferSize, maxWriteSize)) &
        ~0x7;
    maxTransactSize = min(maxBufferSize - 512, maxTransactSize) & ~0x7;

    return true;
  }

  bool checkNegotiateContexts(Smb2NegotiateRequest req, int caps) {
    if (_negotiateContexts == null || _negotiateContexts!.isEmpty) {
      // log.error("Response lacks negotiate contexts");
      return false;
    }

    bool foundPreauth = false, foundEnc = false;
    for (NegotiateContextResponse? ncr in _negotiateContexts!) {
      if (ncr == null) {
        continue;
      } else if (!foundEnc &&
          ncr.getContextType() ==
              EncryptionNegotiateContext.NEGO_CTX_ENC_TYPE) {
        foundEnc = true;
        EncryptionNegotiateContext enc = ncr as EncryptionNegotiateContext;
        if (!checkEncryptionContext(req, enc)) {
          return false;
        }
        selectedCipher = enc.ciphers![0];
        supportsEncryption = true;
      } else if (ncr.getContextType() ==
          EncryptionNegotiateContext.NEGO_CTX_ENC_TYPE) {
        // log.error("Multiple encryption negotiate contexts");
        return false;
      } else if (!foundPreauth &&
          ncr.getContextType() ==
              PreauthIntegrityNegotiateContext.NEGO_CTX_PREAUTH_TYPE) {
        foundPreauth = true;
        PreauthIntegrityNegotiateContext pi =
            ncr as PreauthIntegrityNegotiateContext;
        if (!checkPreauthContext(req, pi)) {
          return false;
        }
        selectedPreauthHash = pi.hashAlgos![0];
      } else if (ncr.getContextType() ==
          PreauthIntegrityNegotiateContext.NEGO_CTX_PREAUTH_TYPE) {
        // log.error("Multiple preauth negotiate contexts");
        return false;
      }
    }

    if (!foundPreauth) {
      // log.error("Missing preauth negotiate context");
      return false;
    }
    if (!foundEnc && (caps & Smb2Constants.SMB2_GLOBAL_CAP_ENCRYPTION) != 0) {
      // log.error("Missing encryption negotiate context");
      return false;
    } else if (!foundEnc) {
      // log.debug("No encryption support");
    }
    return true;
  }

  static bool checkPreauthContext(
      Smb2NegotiateRequest req, PreauthIntegrityNegotiateContext pc) {
    if (pc.hashAlgos == null || pc.hashAlgos!.length != 1) {
      // log.error("Server returned no hash selection");
      return false;
    }

    PreauthIntegrityNegotiateContext? rpc;
    for (NegotiateContextRequest rnc in req.negotiateContexts) {
      if (rnc is PreauthIntegrityNegotiateContext) {
        rpc = rnc;
      }
    }
    if (rpc == null) {
      return false;
    }

    bool valid = false;
    for (int hash in rpc.hashAlgos!) {
      if (hash == pc.hashAlgos![0]) {
        valid = true;
      }
    }
    if (!valid) {
      // log.error("Server returned invalid hash selection");
      return false;
    }
    return true;
  }

  static bool checkEncryptionContext(
      Smb2NegotiateRequest req, EncryptionNegotiateContext ec) {
    var ecCiphers = ec.ciphers;
    if (ecCiphers == null || ecCiphers.length != 1) {
      // log.error("Server returned no cipher selection");
      return false;
    }

    EncryptionNegotiateContext? rec;
    for (NegotiateContextRequest rnc in req.negotiateContexts) {
      if (rnc is EncryptionNegotiateContext) {
        rec = rnc;
      }
    }
    if (rec == null) {
      return false;
    }

    bool valid = false;
    var ciphers = rec.ciphers!;
    for (int cipher in ciphers) {
      if (cipher == ec.ciphers![0]) {
        valid = true;
      }
    }
    if (!valid) {
      // log.error("Server returned invalid cipher selection");
      return false;
    }
    return true;
  }

  @override
  int getReceiveBufferSize() {
    return maxReadSize;
  }

  @override
  int getSendBufferSize() {
    return maxWriteSize;
  }

  @override
  bool isSigningEnabled() {
    return (securityMode & (Smb2Constants.SMB2_NEGOTIATE_SIGNING_ENABLED)) != 0;
  }

  @override
  bool isSigningRequired() {
    return (securityMode & Smb2Constants.SMB2_NEGOTIATE_SIGNING_REQUIRED) != 0;
  }

  @override
  bool isSigningNegotiated() {
    return isSigningRequired();
  }

  @override
  void setupRequest(CommonServerMessageBlock request) {}

  @override
  void setupResponse(Response resp) {}

  @override
  @protected
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    int start = bufferIndex;

    int structureSize = SMBUtil.readInt2(buffer, bufferIndex);
    if (structureSize != 65) {
      throw SmbProtocolDecodingException("Structure size is not 65");
    }

    securityMode = SMBUtil.readInt2(buffer, bufferIndex + 2);
    bufferIndex += 4;

    dialectRevision = SMBUtil.readInt2(buffer, bufferIndex);
    int negotiateContextCount = SMBUtil.readInt2(buffer, bufferIndex + 2);
    bufferIndex += 4;

    byteArrayCopy(
        src: buffer,
        srcOffset: bufferIndex,
        dst: _serverGuid,
        dstOffset: 0,
        length: 16);
    bufferIndex += 16;

    capabilities = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;

    maxTransactSize = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    maxReadSize = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    maxWriteSize = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;

    systemTime = SMBUtil.readTime(buffer, bufferIndex);
    bufferIndex += 8;
    serverStartTime = SMBUtil.readTime(buffer, bufferIndex);
    bufferIndex += 8;

    int securityBufferOffset = SMBUtil.readInt2(buffer, bufferIndex);
    int securityBufferLength = SMBUtil.readInt2(buffer, bufferIndex + 2);
    bufferIndex += 4;

    int negotiateContextOffset = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;

    int hdrStart = getHeaderStart();
    if (hdrStart + securityBufferOffset + securityBufferLength <
        buffer.length) {
      securityBuffer = Uint8List(securityBufferLength);
      byteArrayCopy(
          src: buffer,
          srcOffset: hdrStart + securityBufferOffset,
          dst: securityBuffer!,
          dstOffset: 0,
          length: securityBufferLength);
      bufferIndex += securityBufferLength;
    }

    int pad = (bufferIndex - hdrStart) % 8;
    bufferIndex += pad;

    if (dialectRevision == 0x0311 &&
        negotiateContextOffset != 0 &&
        negotiateContextCount != 0) {
      int ncpos = getHeaderStart() + negotiateContextOffset;
      List<NegotiateContextResponse?> contexts =
          List.generate(length, (index) => null);
      for (int i = 0; i < negotiateContextCount; i++) {
        int type = SMBUtil.readInt2(buffer, ncpos);
        int dataLen = SMBUtil.readInt2(buffer, ncpos + 2);
        ncpos += 4;
        ncpos += 4; // Reserved
        NegotiateContextResponse? ctx = createContext(type);
        if (ctx != null) {
          ctx.decode(buffer, ncpos, dataLen);
          contexts[i] = ctx;
        }
        ncpos += dataLen;
        if (i != negotiateContextCount - 1) {
          ncpos += pad8(ncpos);
        }
      }
      _negotiateContexts = contexts;
      return max(bufferIndex, ncpos) - start;
    }

    return bufferIndex - start;
  }

  static NegotiateContextResponse? createContext(int type) {
    switch (type) {
      case EncryptionNegotiateContext.NEGO_CTX_ENC_TYPE:
        return EncryptionNegotiateContext();
      case PreauthIntegrityNegotiateContext.NEGO_CTX_PREAUTH_TYPE:
        return PreauthIntegrityNegotiateContext();
    }
    return null;
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    return 0;
  }

  @override
  String toString() {
    return "Smb2NegotiateResponse[${super.toString()},dialectRevision=$dialectRevision,securityMode=0x${Hexdump.toHexString(securityMode, 1)},capabilities=0x${Hexdump.toHexString(capabilities, 8)},serverTime=${DateTime.fromMillisecondsSinceEpoch(systemTime)}";
  }
}
