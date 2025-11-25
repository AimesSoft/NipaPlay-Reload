import 'package:smb_connect/src/dialect_version.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block.dart';
import 'package:smb_connect/src/connect/transport/response.dart';

import 'smb_negotiation_request.dart';

abstract class SmbNegotiationResponse
    implements CommonServerMessageBlock, Response {
  bool isValid(SmbNegotiationRequest request);

  DialectVersion? getSelectedDialect();

  /// whether the server has singing enabled
  bool isSigningEnabled();

  /// whether the server requires signing
  bool isSigningRequired();

  void setupRequest(CommonServerMessageBlock request);

  void setupResponse(Response resp);

  /// whether signing has been negotiated
  bool isSigningNegotiated();

  /// whether capability is negotiated
  bool haveCapabilitiy(int cap);

  /// the send buffer size
  int getSendBufferSize();

  /// the receive buffer size
  int getReceiveBufferSize();

  /// the transaction buffer size
  int getTransactionBufferSize();

  /// number of initial credits the server grants
  int getInitialCredits();
}
