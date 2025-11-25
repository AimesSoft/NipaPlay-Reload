import 'dart:async';
import 'dart:typed_data';

import 'package:smb_connect/src/buffer_cache.dart';
import 'package:smb_connect/src/connect/smb_tree.dart';
import 'package:smb_connect/src/dcerpc/dcerpc_bind.dart';
import 'package:smb_connect/src/dcerpc/dcerpc_binding.dart';
import 'package:smb_connect/src/dcerpc/dcerpc_constants.dart';
import 'package:smb_connect/src/dcerpc/dcerpc_message.dart';
import 'package:smb_connect/src/dcerpc/msrpc/msrpc_share_enum.dart';
import 'package:smb_connect/src/dcerpc/ndr/ndr_buffer.dart';
import 'package:smb_connect/src/fixes/atomic_integer.dart';
import 'package:smb_connect/src/smb/file_entry.dart';

class Dcerpc {
  static const defaultMaxXmit = 4280;
  final SmbTree tree;
  final BufferCache bufferCache;
  final String host;
  final int maxXmit;
  final int maxRecv;
  final AtomicInteger callId = AtomicInteger();

  Dcerpc(this.tree, this.host,
      {this.maxXmit = defaultMaxXmit, this.maxRecv = defaultMaxXmit})
      : bufferCache = tree.config.bufferCache;

  Future<List<FileEntry>> requestEntries() async {
    var server = host;
    String bindingUrl =
        "ncacn_np:localhost[endpoint=\\PIPE\\srvsvc,address=127.0.0.1]";
    DcerpcBinding binding = DcerpcBinding.parse(bindingUrl);
    DcerpcMessage bind =
        DcerpcBind(binding: binding, maxXmit: maxXmit, maxRecv: maxRecv);

    await sendrecv(bind);

    MsrpcShareEnum rpc = MsrpcShareEnum(server);
    await sendrecv(rpc);

    return [];
  }

  Future sendrecv(DcerpcMessage msg) async {
    var inpB = bufferCache.getBuffer();
    var outB = bufferCache.getBuffer();
    try {
      encodeMessage(msg, outB);
    } finally {
      bufferCache.releaseBuffer(inpB);
      bufferCache.releaseBuffer(outB);
    }
  }

  NdrBuffer encodeMessage(DcerpcMessage msg, Uint8List out) {
    NdrBuffer buf = NdrBuffer(out, 0);

    msg.flags =
        DcerpcConstants.DCERPC_FIRST_FRAG | DcerpcConstants.DCERPC_LAST_FRAG;
    msg.callId = callId.incrementAndGet();

    msg.encode(buf);

    return buf;
  }
}
