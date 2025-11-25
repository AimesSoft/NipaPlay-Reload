import 'dart:typed_data';

import 'package:smb_connect/src/connect/dcerpc.dart';
import 'package:smb_connect/src/connect/impl/smb2/create/smb2_create_response.dart';
import 'package:smb_connect/src/connect/impl/smb2/ioctl/smb2_ioctl_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/ioctl/smb2_ioctl_response.dart';
import 'package:smb_connect/src/smb/request_param.dart';
import 'package:smb_connect/src/utils/byte_encodable.dart';

class DcerpcSmb2 extends DcerpcBase {
  final Smb2CreateResponse req;

  DcerpcSmb2(super.transport, super.tree, this.req);

  @override
  Future<int> doSendRecieve(
      Uint8List buf, int offset, int length, Uint8List inB) async {
    Smb2IoctlRequest ioctlReq = Smb2IoctlRequest(
      transport.config,
      Smb2IoctlRequest.FSCTL_PIPE_TRANSCEIVE,
      fileId: req.fileId,
      outputBuffer: inB,
      maxOutputResponse: DcerpcBase.maxRecv,
      flags2: Smb2IoctlRequest.SMB2_O_IOCTL_IS_FSCTL,
      inputData: ByteEncodable(buf, offset, length),
    );
    tree.prepare(ioctlReq);
    var ioctlResp = await transport
        .sendrecv<Smb2IoctlResponse>(ioctlReq, params: {RequestParam.NO_RETRY});
    // print(ioctlResp);
    // // ioctlReq.flags = Smb2IoctlRequest.SMB2_O_IOCTL_IS_FSCTL;
    // // ioctlReq.inputData = ByteEncodable(buf, off, length);
    // // ioctlReq.maxOutputResponse = maxRecvSize;
    // Smb2IoctlResponse resp = th.send(ioctlReq, params: {RequestParam.NO_RETRY});
    return ioctlResp.outputLength;
  }
}
