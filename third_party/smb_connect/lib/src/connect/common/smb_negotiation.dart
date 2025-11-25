import 'dart:typed_data';

import 'package:smb_connect/src/connect/common/smb_negotiation_request.dart';
import 'package:smb_connect/src/connect/common/smb_negotiation_response.dart';

final class SmbNegotiation {
  final SmbNegotiationRequest request;
  final SmbNegotiationResponse response;
  final Uint8List? requestBuffer;
  final Uint8List? responseBuffer;

  SmbNegotiation(
    this.request,
    this.response,
    this.requestBuffer,
    this.responseBuffer,
  );
}
