import 'dart:typed_data';

import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/impl/smb2/nego/smb2_negotiate_response.dart';
import 'package:smb_connect/src/connect/impl/smb2/session/smb2_logoff_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/session/smb2_session_setup_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/session/smb2_session_setup_response.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_constants.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_signing_digest.dart';
import 'package:smb_connect/src/connect/smb_session.dart';
import 'package:smb_connect/src/dialect_version.dart';
import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/smb/request_param.dart';
import 'package:smb_connect/src/smb/ssp_context.dart';
import 'package:smb_connect/src/utils/extensions.dart';

class Smb2Session extends SmbSession {
  Smb2Session(super.config, super.transport, [super.credentials]);

  @override
  Future close() async {
    Smb2LogoffRequest logoffReq = Smb2LogoffRequest(config);
    prepareRequest(logoffReq);
    await transport.sendrecv(logoffReq);
  }

  @override
  Future<bool> setup() async {
    var res = await transport.ensureConnected();
    if (!res) {
      if (config.debugPrint) {
        print("Can't connect!");
      }
      return false;
    }
    var negoResp = transport.getNegotiatedResponse()! as Smb2NegotiateResponse;

    var token = negoResp.securityBuffer;
    int securityMode = ((negoResp.securityMode &
                    Smb2Constants.SMB2_NEGOTIATE_SIGNING_REQUIRED) !=
                0) ||
            transport.isSigningEnforced()
        ? Smb2Constants.SMB2_NEGOTIATE_SIGNING_REQUIRED
        : Smb2Constants.SMB2_NEGOTIATE_SIGNING_ENABLED;
    bool anonymous = credentials.isAnonymous();

    String? tdomain;
    SSPContext ctx = createContext(tdomain, negoResp, !anonymous);

    token = createToken(ctx, token!);

    var request1 = Smb2SessionSetupRequest(
        config, securityMode, negoResp.commonCapabilities, 0, token,
        retainPayload: true, credit: 512);
    // request1.setRetainPayload();
    // request1.credit = 512;
    Smb2SessionSetupResponse response1 = await transport
        .sendrecv(request1, params: {RequestParam.RETAIN_PAYLOAD});
    // sessId = response.getSessionId();
    if (config.debugPrint) {
      print("SessionId: ${response1.sessionId}");
    }
    token = response1.blob;

    if (config.debugPrint) {
      print("Smb session token1: ${token?.toHexString()}");
    }

    token = createToken(ctx, token!);
    if (config.debugPrint) {
      print("Smb session createToken1: ${token?.toHexString()}");
    }
    var request2 = Smb2SessionSetupRequest(
        config, securityMode, negoResp.commonCapabilities, 0, token,
        credit: 512, retainPayload: true);
    // request2.credit = 512;
    request2.setSessionId(response1.sessionId);
    // request2.setRetainPayload();
    Smb2SessionSetupResponse response2 = await transport
        .sendrecv(request2, params: {RequestParam.RETAIN_PAYLOAD});
    token = response2.blob;
    if (config.debugPrint) {
      print("Smb session token2: ${token?.toHexString()}");
    }
    if (token == null) {
      final s = SmbException.getMessageByCode(response2.status);
      throw SmbAuthException(s);
      // print(object)
      // throw SmbException("Signing enabled but no session key available");
      // return false;
    }

    token = createToken(ctx, token);
    if (config.debugPrint) {
      print("Smb session createToken2: ${token?.toHexString()}");
    }

    if (token == null && ctx.isEstablished()) {
      sessionId = response2.getSessionId();
      Uint8List? signingKey = sessionKey = ctx.getSigningKey();
      if (config.debugPrint) {
        print(
            "Context is established SessionId=$sessionId (${sessionId.toRadixString(16)}), SessionKey=${sessionKey?.toHexString()}");
      }
      bool signed = response2.isSigned();
      if (!anonymous && (isSignatureSetupRequired() || signed)) {
        if (signingKey != null) {
          Smb2SigningDigest dgst = Smb2SigningDigest(
              sessionKey!, negoResp.dialectRevision, preauthIntegrityHash);
          // verify the server signature here, this is not done automatically as we don't set the
          // request digest
          // Ignore a missing signature for SMB < 3.0, as
          // - the specification does not clearly require that (it does for SMB3+)
          // - there seem to be server implementations (known: EMC Isilon) that do not sign the final
          // response
          if (negoResp.getSelectedDialect()?.atLeast(DialectVersion.SMB300) ==
                  true ||
              response2.isSigned()) {
            response2.setDigest(dgst);
            Uint8List? payload = response2.getRawPayload();
            if (payload == null ||
                !response2.verifySignature(payload, 0, payload.length)) {
              throw SmbException("Signature validation failed");
            }
          }
          setDigest(dgst);
        } else if (Configuration.isSigningEnabled) {
          throw SmbException("Signing enabled but no session key available");
        }
      }
      return true;
    }
    return false;
  }

  SSPContext createContext(
      String? tdomain, Smb2NegotiateResponse negoResp, bool doSigning) {
    String? host = getTargetHost();
    return credentials.createContext(
        config, tdomain, host, negoResp.securityBuffer!, doSigning);
  }

  static Uint8List? createToken(SSPContext ctx, Uint8List token) {
    return ctx.initSecContext(token, 0, token.length);
  }
}
