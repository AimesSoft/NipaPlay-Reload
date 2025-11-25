import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block_request.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block_response.dart';
import 'package:smb_connect/src/connect/common/request.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_response.dart';

abstract class ServerMessageBlock2Request<T extends ServerMessageBlock2Response>
    extends ServerMessageBlock2
    implements CommonServerMessageBlockRequest, Request<T> {
  T? response;
  int? overrideTimeout;

  ServerMessageBlock2Request(
    super.config, {
    super.command,
    super.credit = 0,
    super.retainPayload = false,
  });

  // @override
  // ServerMessageBlock2Request<T> ignoreDisconnect() {
  //   return this;
  // }

  @override
  ServerMessageBlock2Request? getNext() {
    return super.getNext() as ServerMessageBlock2Request?;
  }

  @override
  void setNext(ServerMessageBlock2? next) {
    //ServerMessageBlock2Request<T>?
    super.setNext(next);
  }

  @override
  int getCreditCost() {
    return 1;
  }

  @override
  void setRequestCredits(int value) {
    credit = value;
  }

  @override
  int? getOverrideTimeout() {
    return this.overrideTimeout;
  }

  void setOverrideTimeout(int? overrideTimeout) {
    this.overrideTimeout = overrideTimeout;
  }

  @override
  T initResponse(Configuration config) {
    T resp = createResponse(config, this);
    resp.setDigest(getDigest());
    setResponse(resp);

    ServerMessageBlock2? n = getNext();
    if (n is ServerMessageBlock2Request) {
      resp.setNext(n.initResponse(config));
    }
    return resp;
  }

  @override
  void setTid(int t) {
    setTreeId(t);
  }

  @override
  int encode(Uint8List dst, int dstIndex) {
    int len = super.encode(dst, dstIndex);
    int exp = size();
    int actual = getLength();
    if (exp != actual) {
      throw SmbIllegalStateException(
          "Wrong size calculation have $exp expect $actual");
    }
    return len;
  }

  @override
  T? getResponse() {
    return response;
  }

  T createResponse(Configuration config, ServerMessageBlock2Request<T> req);

  @override
  void setResponse(CommonServerMessageBlockResponse? msg) {
    if (msg != null && msg is! ServerMessageBlock2) {
      throw SmbIllegalArgumentException("Incompatible response");
    }
    this.response = msg as T?;
  }
}
