import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/smb_session.dart';
import 'package:smb_connect/src/connect/smb_transport.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block_request.dart';

abstract class SmbTree {
  final SmbTransport transport;
  final Configuration config;
  final SmbSession session;
  final String share;
  late final String service0;
  String service = "?????";
  int treeId = 0;

  SmbTree(this.transport, this.session, String share, String? service)
      : config = transport.config,
        share = share.toUpperCase() {
    if (service != null && !service.startsWith("??")) {
      this.service = service;
    }
    service0 = this.service;
  }

  Future<void> setup();

  void _prepareRequest(CommonServerMessageBlockRequest request) {
    session.prepareRequest(request);
    request.setTid(treeId);
  }

  void prepare(CommonServerMessageBlockRequest request) {
    _prepareRequest(request);
    var next = request.getNext();
    if (next != null) {
      prepare(next);
    }
  }

  bool hasCapability(int cap) {
    return transport.getNegotiatedResponse()?.haveCapabilitiy(cap) == true;
  }

  bool isSMB2() => transport.isSMB2();

  Future close(); // async {
  //   if (isSMB2()) {
  //     Smb2TreeDisconnectRequest disconnectReq =
  //         Smb2TreeDisconnectRequest(config);
  //     prepare(disconnectReq);
  //     await transport.sendrecv(disconnectReq);
  //   } else {
  //     var disconnectReq = SmbComTreeDisconnect(config);
  //     var disconnectResp = SmbComBlankResponse(config);
  //     prepare(disconnectReq);
  //     await transport.sendrecv(disconnectReq, response: disconnectResp);
  //   }
  //   await session.close();
  // }
}
