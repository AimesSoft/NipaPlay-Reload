import 'package:smb_connect/src/connect/impl/smb1/smb1_session.dart';
import 'package:smb_connect/src/connect/smb_transport.dart';
import 'package:smb_connect/src/connect/smb_tree.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_blank_response.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_negotiate_response.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_tree_connect_and_x.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_tree_connect_and_x_response.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_tree_disconnect.dart';
import 'package:smb_connect/src/connect/common/smb_negotiation_response.dart';

class Smb1Tree extends SmbTree {
  final Smb1Session _session;

  Smb1Tree(SmbTransport transport, this._session, String share, String? service)
      : super(transport, _session, share, service);

  @override
  Future<void> setup() async {
    String tconHostName = session.getTargetHost();
    SmbNegotiationResponse? nego = transport.getNegotiatedResponse();
    String unc = "\\\\$tconHostName\\$share";
    //
    // IBM iSeries doesn't like specifying a service. Always reset
    // the service to whatever was determined in the constructor.
    //
    String? svc = service0;

    var response = SmbComTreeConnectAndXResponse(config, null);
    var request = SmbComTreeConnectAndX(config.credentials, config,
        (nego as SmbComNegotiateResponse).getServerData(), unc, svc, null);
    await _session.setup(andx: request, andxResponse: response);

    session.prepareRequest(request);

    response = await transport.sendrecv(request, response: response);
    treeId = response.getTid();
  }

  @override
  bool isSMB2() => false;

  @override
  Future close() async {
    var disconnectReq = SmbComTreeDisconnect(config);
    var disconnectResp = SmbComBlankResponse(config);
    prepare(disconnectReq);
    await transport.sendrecv(disconnectReq, response: disconnectResp);
    await session.close();
  }
}
