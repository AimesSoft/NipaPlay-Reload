import 'package:smb_connect/src/connect/impl/smb2/smb2_session.dart';
import 'package:smb_connect/src/connect/smb_transport.dart';
import 'package:smb_connect/src/connect/smb_tree.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/tree/smb2_tree_connect_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/tree/smb2_tree_disconnect_request.dart';
import 'package:smb_connect/src/connect/common/tree_connect_response.dart';

class Smb2Tree extends SmbTree {
  final Smb2Session _session;

  Smb2Tree(SmbTransport transport, this._session, String share, String? service)
      : super(transport, _session, share, service);

  @override
  Future<void> setup() async {
    await _session.setup();

    CommonServerMessageBlockRequest request;
    TreeConnectResponse? response;

    String tconHostName = session.getTargetHost();
    String unc = "\\\\$tconHostName\\$share";

    request = Smb2TreeConnectRequest(config, unc);
    session.prepareRequest(request);
    response = await transport.sendrecv(request);
    treeId = response.getTid();
  }

  @override
  bool isSMB2() => true;

  @override
  Future close() async {
    Smb2TreeDisconnectRequest disconnectReq = Smb2TreeDisconnectRequest(config);
    prepare(disconnectReq);
    await transport.sendrecv(disconnectReq);
    await session.close();
  }
}
