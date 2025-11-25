import 'dart:typed_data';

import 'package:smb_connect/src/connect/dcerpc.dart';
import 'package:smb_connect/src/connect/impl/smb1/trans/trans_transact_named_pipe.dart';
import 'package:smb_connect/src/connect/impl/smb1/trans/trans_transact_named_pipe_response.dart';
import 'package:smb_connect/src/smb/request_param.dart';

class DcerpcSmb1 extends DcerpcBase {
  final int fid;

  DcerpcSmb1(super.transport, super.tree, this.fid);

  @override
  Future<int> doSendRecieve(
      Uint8List buf, int offset, int length, Uint8List inB) async {
    TransTransactNamedPipe req =
        TransTransactNamedPipe(transport.config, fid, buf, offset, length);
    TransTransactNamedPipeResponse resp =
        TransTransactNamedPipeResponse(transport.config, inB);
    // if ((getPipeType() & SmbPipeResource.PIPE_TYPE_DCE_TRANSACT) ==
    // SmbPipeResource.PIPE_TYPE_DCE_TRANSACT) {
    req.setMaxDataCount(1024);
    // }
    tree.prepare(req);
    await transport.sendrecvComTransaction(req, resp, {RequestParam.NO_RETRY});
    return resp.getLength();
  }
}
