import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block_request.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block_response.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_constants.dart';
import 'package:smb_connect/src/utils/extensions.dart';

import '../../../smb/nt_status.dart';
import 'server_message_block2.dart';
import 'smb2_signing_digest.dart';

abstract class ServerMessageBlock2Response extends ServerMessageBlock2
    implements CommonServerMessageBlockResponse {
  bool received = false;
  bool _error = false;
  int? expiration;

  bool verifyFailed = false;
  Exception? _exception;
  bool asyncHandled = false;

  ServerMessageBlock2Response(super.config, {super.command = 0});

  @override
  CommonServerMessageBlockResponse? getNextResponse() {
    return getNext() as CommonServerMessageBlockResponse?;
  }

  @override
  void prepare(CommonServerMessageBlockRequest next) {
    CommonServerMessageBlockResponse? n = getNextResponse();
    if (n != null) {
      n.prepare(next);
    }
  }

  @override
  void reset() {
    super.reset();
    received = false;
  }

  @override
  void setReceived() {
    if (async && getStatus() == NtStatus.NT_STATUS_PENDING) {
      return;
    }
    received = true;
  }

  @override
  void setException(Exception? e) {
    _error = true;
    _exception = e;
    received = true;
  }

  @override
  void error() {
    _error = true;
  }

  @override
  void clearReceived() {
    received = false;
  }

  @override
  bool isReceived() {
    return received;
  }

  @override
  bool isError() {
    return _error;
  }

  bool isSigned() {
    return (flags & Smb2Constants.SMB2_FLAGS_SIGNED) != 0;
  }

  @override
  int? getExpiration() {
    return expiration;
  }

  @override
  void setExpiration(int? exp) {
    expiration = exp;
  }

  bool isAsyncHandled() {
    return asyncHandled;
  }

  void setAsyncHandled(bool asyncHandled) {
    this.asyncHandled = asyncHandled;
  }

  @override
  Exception? getException() {
    return _exception;
  }

  @override
  int getErrorCode() {
    return getStatus();
  }

  @override
  bool isVerifyFailed() {
    return verifyFailed;
  }

  @override
  int getGrantedCredits() {
    return credit;
  }

  @override
  void haveResponse(Uint8List buffer, int start, int len) {
    if (isRetainPayload()) {
      Uint8List payload = Uint8List(len);
      byteArrayCopy(
          src: buffer,
          srcOffset: start,
          dst: payload,
          dstOffset: 0,
          length: len);
      setRawPayload(payload);
    }

    if (!verifySignature(buffer, start, len)) {
      throw SmbProtocolDecodingException(
          "Signature verification failed for ${runtimeType.toString()}"); // + getClass().getName());
    }

    setAsyncHandled(false);
    setReceived();
  }

  @override
  bool verifySignature(Uint8List buffer, int i, int size) {
    // observed too that signatures on error responses are sometimes wrong??
    // Looks like the failure case also is just reflecting back the signature we sent

    // with SMB3's negotiation validation it's no longer possible to ignore this (on the validation response)
    // make sure that validation is performed in any case
    Smb2SigningDigest? dgst = getDigest();
    if (dgst != null &&
        !async &&
        (Configuration.isRequireSecureNegotiate ||
            getErrorCode() == NtStatus.NT_STATUS_OK)) {
      // We only read what we were waiting for, so first guess would be no.
      bool verify = dgst.verify(buffer, i, size, 0, this);
      verifyFailed = verify;
      return !verify;
    }
    return true;
  }
}
