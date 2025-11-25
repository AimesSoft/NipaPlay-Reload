import 'dart:typed_data';

import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/smb_transport.dart';
import 'package:smb_connect/src/credentials.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block_request.dart';
import 'package:smb_connect/src/connect/common/smb_signing_digest.dart';

abstract class SmbSession {
  final Configuration config;
  final SmbTransport transport;
  final Credentials credentials;

  int sessionId = 0;
  int uid = 0;
  Uint8List? sessionKey;
  Uint8List? preauthIntegrityHash;
  SMBSigningDigest? _digest;

  SmbSession(
    this.config,
    this.transport, [
    Credentials? credentials,
  ]) : credentials = credentials ?? config.credentials;

  SMBSigningDigest? getDigest() {
    return _digest;
  }

  void setDigest(SMBSigningDigest digest) {
    _digest = digest;
  }

  bool isSignatureSetupRequired() {
    SMBSigningDigest? cur = getDigest();
    if (cur != null) {
      return false;
    } else if (transport.isSigningEnforced()) {
      return true;
    }
    return transport.getNegotiatedResponse()?.isSigningNegotiated() == true;
  }

  String getTargetHost() {
    return transport.host;
  }

  void prepareRequest(CommonServerMessageBlockRequest request) {
    request.setSessionId(sessionId);
    request.setUid(uid);
    if (_digest != null) {
      request.setDigest(_digest);
    }
  }

  Future<bool> setup();

  Future close();
}
