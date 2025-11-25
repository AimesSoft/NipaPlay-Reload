import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/smb_session.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_blank_response.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_logoff_and_x.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_negotiate_response.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_session_setup_and_x.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_session_setup_and_x_response.dart';
import 'package:smb_connect/src/connect/impl/smb1/server_message_block.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb1_signing_digest.dart';
import 'package:smb_connect/src/smb/nt_status.dart';
import 'package:smb_connect/src/smb/ntlm_password_authenticator.dart';
import 'package:smb_connect/src/smb/ssp_context.dart';
import 'package:smb_connect/src/smb_constants.dart';

class Smb1Session extends SmbSession {
  Smb1Session(super.config, super.transport, [super.credentials]);

  @override
  Future<bool> setup(
      {ServerMessageBlock? andx, ServerMessageBlock? andxResponse}) async {
    var res = await transport.ensureConnected();
    if (!res) {
      if (config.debugPrint) {
        print("Can't connect!");
      }
      return false;
    }
    // var token = Uint8List(0);
    var negoResp =
        transport.getNegotiatedResponse()! as SmbComNegotiateResponse;

    bool anonymous = credentials.isAnonymous();
    if (transport
            .getNegotiatedResponse()
            ?.haveCapabilitiy(SmbConstants.CAP_EXTENDED_SECURITY) ==
        true) {
      String host = getTargetHost();
      String? tdomain = config.domain;
      // var s = credentials.getSubject();
      final doSigning = !anonymous &&
          (negoResp.getNegotiatedFlags2() &
                  SmbConstants.FLAGS2_SECURITY_SIGNATURES) !=
              0;
      final ctx = credentials.createContext(config, tdomain, host,
          negoResp.getServerData().encryptionKey!, doSigning);

      var resp1 =
          await ntlmSSP(ctx, anonymous, doSigning, negoResp, Uint8List(0));
      var nextToken = resp1?.blob;
      if (nextToken == null) {
        var errorCode = resp1?.errorCode ?? NtStatus.NT_STATUS_LOGON_FAILURE;
        throw SmbAuthException(SmbException.getMessageByCode(errorCode));
        // return false;
      }
      var resp2 = await ntlmSSP(ctx, anonymous, doSigning, negoResp, nextToken);
      nextToken = resp2?.blob;
      if (nextToken == null) {
        var errorCode = resp2?.errorCode ?? NtStatus.NT_STATUS_LOGON_FAILURE;
        throw SmbAuthException(SmbException.getMessageByCode(errorCode));
        // return false;
      }
      nextToken = ctx.initSecContext(nextToken, 0, nextToken.length);
      if (ctx.isEstablished()) {
        // print("Context is established");
        // setNetbiosName(ctx.getNetbiosName());
        sessionKey = ctx.getSigningKey();
        // if (request != null && request.getDigest() != null) {
        //   /// success - install the signing digest
        //   setDigest(request.getDigest());
        // }
        return true;
      } else if (!anonymous && isSignatureSetupRequired()) {
        final signingKey = ctx.getSigningKey();
        if (signingKey != null) {
          setDigest(SMB1SigningDigest(signingKey, signSequence: 2));
        } else if (Configuration.isSigningEnabled) {
          throw SmbException("Signing required but no session key available");
        }
        sessionKey = signingKey;
        return true;
      }
      return false;
      // log.debug("Extended security negotiated");
      // break;
      // return;
    } else {
      // else if ( config.isForceExtendedSecurity() ) {
      //     throw SmbException("Server does not supported extended security");
      // }
      if (credentials is! NtlmPasswordAuthenticator) {
        throw SmbAuthException("Incompatible credentials");
      }
      NtlmPasswordAuthenticator npa = credentials as NtlmPasswordAuthenticator;

      var request = SmbComSessionSetupAndX(config, negoResp, andx, credentials);
      // if the connection already has a digest set up this needs to be used
      request.setDigest(getDigest());
      var response = SmbComSessionSetupAndXResponse(config, andx: andxResponse);
      response.setExtendedSecurity(false);

      /// Create SMB signature digest if necessary
      /// Only the first SMB_COM_SESSION_SETUP_ANX with non-null or
      /// blank password initializes signing.

      if (!anonymous && isSignatureSetupRequired()) {
        // if (isExternalAuth(getContext(), npa)) {
        //   /// preauthentication
        //   SmbSessionImpl? smbSession;
        //   SmbTreeImpl? t;

        //   try {
        //     //( SmbSessionImpl smbSession = trans.getSmbSession(getContext().withDefaultCredentials());
        //     // SmbTreeImpl t = smbSession.getSmbTree(getContext().getConfig().getLogonShare(), null) ) {
        //     smbSession =
        //         transport.getSmbSession(getContext().withDefaultCredentials());
        //     t = smbSession.getSmbTree(
        //         getContext().getConfig().getLogonShare(), null);
        //     t.treeConnect(null, null);
        //   } finally {
        //     smbSession?.close();
        //     t?.close();
        //   }
        // } else {
        // log.debug("Initialize signing");
        Uint8List? signingKey =
            npa.getSigningKey(config, negoResp.getServerData().encryptionKey!);
        if (signingKey == null) {
          throw SmbException(
              "Need a signature key but the server did not provide one");
        }
        request.setDigest(SMB1SigningDigest(signingKey, bypass: false));
        // }
      }

      await transport.sendrecv(request, response: response);
      if (response.errorCode != 0) {
        throw "Can't create session";
      }

      if (response.isLoggedInAsGuest && //!config.isAllowGuestFallback() &&
          negoResp.getServerData().security != SmbConstants.SECURITY_SHARE &&
          !(credentials.isGuest() || credentials.isAnonymous())) {
        throw SmbAuthException(
            SmbException.getMessageByCode(NtStatus.NT_STATUS_LOGON_FAILURE));
      } else if (!credentials.isAnonymous() && response.isLoggedInAsGuest) {
        anonymous = true;
      }

      // if (ex != null) {
      //   throw ex;
      // }

      uid = response.getUid(); //setUid(response.getUid());

      var digest = request.getDigest();
      if (digest != null) {
        // success - install the signing digest
        setDigest(digest);
      } else if (!anonymous && isSignatureSetupRequired()) {
        throw SmbException("Signing required but no session key available");
      }

      // setSessionSetup(response);
      // state = 0;
      return true;
    }
  }

  Future<SmbComSessionSetupAndXResponse?> ntlmSSP(
      SSPContext ctx,
      bool anonymous,
      bool doSigning,
      SmbComNegotiateResponse negoResp,
      Uint8List prevToken) async {
    // final curToken = token;
    // if ( s != null ) {
    //     try {
    //         token = Subject.doAs(s, new PrivilegedExceptionAction<byte[]>() {

    //             @Override
    //             public byte[] run () throws Exception {
    //                 return curCtx.initSecContext(curToken, 0, curToken == null ? 0 : curToken.length);
    //             }

    //         });
    //     }
    //     catch ( PrivilegedActionException e ) {
    //         if ( e.getException() instanceof SmbException )

    //         {
    //             throw (SmbException) e.getException();
    //         }
    //         throw new SmbException("Unexpected exception during context initialization", e);
    //     }
    // }
    // else {
    var nextToken = ctx.initSecContext(prevToken, 0, prevToken.length);
    if (nextToken == null) {
      return null;
    }
    var request = SmbComSessionSetupAndX(config, negoResp, null, nextToken);
    // if the connection already has a digest set up this needs to be used
    request.setDigest(getDigest());
    if (doSigning && ctx.isEstablished() && isSignatureSetupRequired()) {
      var signingKey = ctx.getSigningKey();
      if (signingKey != null) {
        request.setDigest(SMB1SigningDigest(signingKey));
      }
      sessionKey = signingKey;
    } else {
      // print("Not yet initializing signing");
    }

    var response = SmbComSessionSetupAndXResponse(config, andx: null);
    response.setExtendedSecurity(true);
    request.setUid(uid);
    uid = 0;

    // try {
    await transport.sendrecv(request, response: response);
    // }
    // catch ( SmbAuthException sae ) {
    // throw sae;
    // }
    // catch ( SmbException se ) {
    //     ex = se;
    //     if ( se.getNtStatus() == NtStatus.NT_STATUS_INVALID_PARAMETER ) {
    //         // a relatively large range of samba versions has a bug causing
    //         // an invalid parameter error when a SPNEGO MIC is in place and auth fails
    //         ex = new SmbAuthException("Login failed", se);
    //     }
    //     /*
    //      * Apparently once a successful NTLMSSP login occurs, the
    //      * server will return "Access denied" even if a logoff is
    //      * sent. Unfortunately calling disconnect() doesn't always
    //      * actually shutdown the connection before other threads
    //      * have committed themselves (e.g. InterruptTest example).
    //      */
    //     try {
    //         trans.disconnect(true);
    //     }
    //     catch ( Exception e ) {
    //         log.debug("Failed to disconnect transport", e);
    //     }
    // }

    if (response.isLoggedInAsGuest && //!config.isAllowGuestFallback() &&
        !(credentials.isGuest() || credentials.isAnonymous())) {
      throw SmbAuthException(
          SmbException.getMessageByCode(NtStatus.NT_STATUS_LOGON_FAILURE));
    } else if (!credentials.isAnonymous() && response.isLoggedInAsGuest) {
      anonymous = true;
    }

    // if (ex != null) {
    //   throw ex;
    // }
    // var s = SmbException.getMessageByCode(response.errorCode);
    // print(s);

    uid = response.getUid();
    var digest = request.getDigest();
    if (digest != null) {
      /// success - install the signing digest
      // log.debug("Setting digest");
      setDigest(digest);
    }
    return response; //.blob;
  }

  @override
  Future close() async {
    bool shareSecurity =
        (transport.getNegotiatedResponse() as SmbComNegotiateResponse)
                .getServerData()
                .security ==
            SmbConstants.SECURITY_SHARE;
    if (!shareSecurity) {
      SmbComLogoffAndX request = SmbComLogoffAndX(config, null);
      request.setDigest(getDigest());
      request.setUid(uid);
      try {
        await transport.send(request, SmbComBlankResponse(config));
      } catch (se) {
        // log.debug("SmbComLogoffAndX failed", se);
      }
      uid = 0;
    }
  }
}
